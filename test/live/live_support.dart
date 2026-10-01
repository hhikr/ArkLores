/// Case loading and per-turn metrics for the live Ask harness and the R12
/// evaluation set. Metrics are computed only from the recorded session turn
/// (the same record the app writes), never from agent internals.
library;

import 'dart:convert';
import 'dart:io';

import 'package:arklores/core/agent/chat_session_models.dart';
import 'package:arklores/core/llm/llm_client.dart';

/// Sums provider-reported token usage of chat completions (cost control).
class UsageMeter {
  int calls = 0;
  int promptTokens = 0;
  int completionTokens = 0;
  int cachedPromptTokens = 0;

  void add(ChatCompletionResult result) {
    calls++;
    promptTokens += result.promptTokens ?? 0;
    completionTokens += result.completionTokens ?? 0;
    cachedPromptTokens += result.cachedPromptTokens ?? 0;
  }

  void reset() {
    calls = 0;
    promptTokens = 0;
    completionTokens = 0;
    cachedPromptTokens = 0;
  }

  Map<String, int> toJson() => {
        'llm_calls': calls,
        'prompt_tokens': promptTokens,
        'cached_prompt_tokens': cachedPromptTokens,
        'completion_tokens': completionTokens,
      };
}

/// One live question, optionally with gold story ids for recall scoring.
class LiveCase {
  const LiveCase({
    required this.id,
    required this.query,
    this.type,
    this.goldStories = const [],
  });
  final String id;
  final String query;
  final String? type;

  /// Story ids an answer should rest on (any one read counts toward recall).
  final List<String> goldStories;
}

/// Cases from `ARKLORES_LIVE_EVAL` (JSON file) or `ARKLORES_LIVE_QUERIES`
/// (`||`-separated). `ARKLORES_LIVE_IDS` (comma list) filters eval cases.
List<LiveCase> loadLiveCases(Map<String, String> env) {
  final evalPath = env['ARKLORES_LIVE_EVAL'];
  if (evalPath != null && evalPath.trim().isNotEmpty) {
    final raw = jsonDecode(File(evalPath.trim()).readAsStringSync());
    final items = (raw is Map ? raw['cases'] : raw) as List;
    final only = env['ARKLORES_LIVE_IDS']
        ?.split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toSet();
    return [
      for (final item in items.cast<Map<String, dynamic>>())
        if (only == null || only.isEmpty || only.contains(item['id']))
          LiveCase(
            id: '${item['id']}',
            query: '${item['query']}',
            type: item['type'] as String?,
            goldStories: [
              for (final g in (item['gold_stories'] as List? ?? const []))
                g is Map ? '${g['story_id']}' : '$g',
            ],
          ),
    ];
  }
  final queries = env['ARKLORES_LIVE_QUERIES'];
  if (queries == null || queries.trim().isEmpty) return const [];
  final parts = queries
      .split('||')
      .map((q) => q.trim())
      .where((q) => q.isNotEmpty)
      .toList();
  return [
    for (var i = 0; i < parts.length; i++)
      LiveCase(id: 'q${i + 1}', query: parts[i]),
  ];
}

final RegExp _citation =
    RegExp(r'([\w\-/\.\[\]]+\.txt)\s*[:：]\s*(\d+)(?:\s*[-–~]\s*(\d+))?');

/// Metrics for one recorded turn.
Map<String, Object?> summarizeTurn(
  LiveCase liveCase,
  ChatSessionFile session,
  ChatSessionTurn turn, {
  UsageMeter? usage,
}) {
  final toolCounts = <String, int>{};
  final readStories = <String>{};
  var emptyResponses = 0;
  for (final it in turn.iterations) {
    final tool = it.tool;
    if (tool != null && tool.isNotEmpty) {
      toolCounts[tool] = (toolCounts[tool] ?? 0) + 1;
    }
    if (tool == 'read_story_lines') {
      final story = it.toolArgs?['story_id'];
      if (story is String && story.isNotEmpty) readStories.add(story);
    }
    if (it.rawResponse.trim().isEmpty) emptyResponses++;
  }
  final goldHit = [
    for (final g in liveCase.goldStories)
      if (readStories.contains(g)) g,
  ];
  // Same scheme as tools/summarize_eval.dart: a state dump (`调查无法推进`)
  // is not an answer and its read ranges are not citations.
  final answer = turn.answer;
  final terminal = turn.status != ChatTurnStatus.completed
      ? 'error'
      : answer.trim().isEmpty || answer.contains('调查无法推进')
          ? 'no_answer'
          : answer.contains('culprit=unresolved')
              ? 'partial'
              : 'answered';
  final citations = terminal == 'no_answer' || terminal == 'error'
      ? const <String>{}
      : {for (final m in _citation.allMatches(answer)) m.group(0)!};
  return {
    'id': liveCase.id,
    'type': liveCase.type,
    'query': liveCase.query,
    'session_id': session.sessionId,
    'model': turn.model,
    'effective_mode': turn.effectiveMode.name,
    'router_raw': turn.router?.rawResponse,
    'status': turn.status.name,
    'terminal': terminal,
    'error': turn.error,
    'duration_ms': turn.durationMs,
    'iterations': turn.iterations.length,
    'empty_responses': emptyResponses,
    'tool_counts': toolCounts,
    'read_stories': readStories.toList()..sort(),
    'gold_stories': liveCase.goldStories,
    'gold_recall': liveCase.goldStories.isEmpty
        ? null
        : goldHit.length / liveCase.goldStories.length,
    'citations': citations.length,
    'source_warning': turn.answer.contains('来源警告'),
    'answer_chars': turn.answer.length,
    if (usage != null) 'usage': usage.toJson(),
    'answer': turn.answer,
  };
}
