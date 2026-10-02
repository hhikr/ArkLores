import '../gamedata/gamedata_models.dart';
import '../llm/completion_budget.dart';
import '../llm/llm_client.dart';

/// Outcome of one disambiguation decision.
class DisambiguationResult {
  const DisambiguationResult({
    required this.entityId,
    required this.name,
    this.choseTopFallback = false,
  });

  /// The chosen entity id (always one of the candidates).
  final String entityId;

  /// Display name of the chosen candidate (for observations).
  final String name;

  /// True when the LLM helper could not decide and we fell back to the
  /// top-ranked candidate (R11 fallback: never produce a hard failure).
  final bool choseTopFallback;
}

/// R11 disambiguation helper: decides WHICH candidate matches the user
/// question, instead of the executor blindly picking the top candidate.
///
/// One lightweight LLM call (~150–250 tokens, temperature 0) is made ONLY when
/// a search hits multiple exact candidates. It sees the user question, the
/// compact candidate list (id | name | type | source …), and the ids already
/// tried in this investigation, so it can pick by semantic fit and will not
/// re-pick a previously tried candidate.
///
/// Any LLM/parse failure falls back to the top candidate (current behavior),
/// so a bad helper can never deadlock the loop — it degrades to "auto-pick #1".
class EntityDisambiguator {
  EntityDisambiguator({required LLMClient llmClient}) : _llmClient = llmClient;

  final LLMClient _llmClient;

  static const String _formatInstructions = '''
你是明日方舟实体消歧器。给你一个用户问题与若干同名候选实体，选出与你判断最匹配的一个。
只输出一个候选的编号（如 "2"），不要任何其他文字，不要解释。
如果无法判断（候选信息不足或问题与候选都无关），输出 0。''';

  Future<DisambiguationResult> choose({
    required String query,
    required List<GameDataEntityCandidate> candidates,
    List<String> excludeIds = const [],
  }) async {
    final exclude = excludeIds.toSet();
    final available = [
      for (final c in candidates)
        if (!exclude.contains(c.entityId)) c,
    ];
    final pool = available.isEmpty ? candidates : available;

    final lines = [
      for (var i = 0; i < pool.length; i++)
        '${i + 1}. ${pool[i].entityId} | ${pool[i].name} | '
            '${pool[i].entityType} | ${pool[i].sourceType}',
    ].join('\n');
    final excludeLine = exclude.isEmpty
        ? '（无）'
        : exclude.join(', ');

    final prompt = '''
$_formatInstructions

用户问题：「$query」

候选：
$lines

本次调查已尝试（不要再选）：
$excludeLine
''';

    final picked = await _tryPick(prompt, pool.length);
    final index = picked ?? 0; // null -> fallback to top of pool
    final selected = pool[index];
    return DisambiguationResult(
      entityId: selected.entityId,
      name: selected.name,
      choseTopFallback: picked == null,
    );
  }

  Future<int?> _tryPick(String prompt, int count) async {
    try {
      // R12: 32 tokens left reasoning models no room to answer (empty,
      // finish_reason=length), so the helper silently fell back to #1.
      final result = await completeWithHeadroom(
        _llmClient,
        [
          Message.system(_formatInstructions),
          Message.user(prompt),
        ],
        temperature: 0,
        maxTokens: 1024,
      );
      final raw = result.content.trim();
      if (raw.isEmpty) return null;
      final match = RegExp(r'^\s*(\d+)\s*$').firstMatch(raw);
      if (match == null) return null;
      final index = int.tryParse(match.group(1)!);
      if (index == null || index < 1 || index > count) return null;
      return index - 1;
    } catch (_) {
      return null;
    }
  }
}