/// Case loading and per-turn metrics for the live Ask harness and the R12
/// evaluation set. Metrics are computed only from the recorded session turn
/// (the same record the app writes), never from agent internals.
library;

import 'dart:convert';
import 'dart:io';

import 'package:arklores/core/agent/chat_session_models.dart';
import 'package:arklores/core/agent/story_answer.dart';
import 'package:arklores/core/llm/usage_meter.dart';
import 'package:arklores/features/ai/investigation_ui.dart';

export 'package:arklores/core/llm/usage_meter.dart' show UsageMeter;


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

final RegExp _repeatObservation = RegExp('已执行过|已经读过|已经给你看过|再给你看一次|已获取|相同的梗概');

final RegExp _quoted = RegExp(r'[“"「『]([^”"」』\n]*)[”"」』]');
final RegExp _internalTerms = RegExp(
  r'库中|story_id|\.txt|说话人|line_index|\b[a-z][a-z0-9]*_[a-z0-9_]+\b',
);

/// R17b: how the answer reads (statistics only): the share of its prose
/// inside quotation marks, and mentions of knowledge-base internals in the
/// prose. Citations are removed first, as the app does.
Map<String, Object?> proseMetrics(String answer) {
  final prose = [
    for (final b in splitAnswerBlocks(answer)) b.markdown,
  ].join('\n').replaceAll(RegExp(r'\[[A-Z_]+:[^\]]*\]'), '');
  final chars = prose.replaceAll(RegExp(r'\s'), '').length;
  final quoted = _quoted
      .allMatches(prose)
      .fold<int>(0, (n, m) => n + m.group(1)!.length);
  return {
    'quoted_char_ratio':
        chars == 0 ? 0 : double.parse((quoted / chars).toStringAsFixed(3)),
    'quote_count': _quoted.allMatches(prose).length,
    'internal_terms_in_prose': _internalTerms.allMatches(prose).length,
  };
}

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
  // Steps answered from what the run already had (re-shown text, cached
  // outlines, refused repeats) — R16 measures these against R14/R15.
  var repeats = 0;
  for (final it in turn.iterations) {
    final tool = it.tool;
    if (tool != null && tool.isNotEmpty) {
      toolCounts[tool] = (toolCounts[tool] ?? 0) + 1;
    }
    // R16 planner READ / R17 tool agent read_story.
    if (tool == 'read_story_lines' || tool == 'read_story') {
      final story = it.toolArgs?['story_id'];
      if (story is String && story.isNotEmpty) {
        readStories.add(story.endsWith('.txt') ? story : '$story.txt');
      }
    }
    if (it.rawResponse.trim().isEmpty) emptyResponses++;
    if (_repeatObservation.hasMatch(it.observation)) repeats++;
  }
  final goldHit = [
    for (final g in liveCase.goldStories)
      if (readStories.contains(g)) g,
  ];
  // Same scheme as tools/summarize_eval.dart.
  final answer = turn.answer;
  final terminal = classifyAnswer(
    completed: turn.status == ChatTurnStatus.completed,
    answer: answer,
  );
  final citations = terminal == 'no_answer' || terminal == 'error'
      ? const <String>{}
      : {for (final m in _citation.allMatches(answer)) m.group(0)!};
  return {
    'id': liveCase.id,
    'type': liveCase.type,
    'query': liveCase.query,
    'session_id': session.sessionId,
    'model': turn.model,
    'status': turn.status.name,
    'terminal': terminal,
    'error': turn.error,
    'duration_ms': turn.durationMs,
    'iterations': turn.iterations.length,
    'empty_responses': emptyResponses,
    'repeat_steps': repeats,
    'tool_counts': toolCounts,
    'read_stories': readStories.toList()..sort(),
    'gold_stories': liveCase.goldStories,
    'gold_recall': liveCase.goldStories.isEmpty
        ? null
        : goldHit.length / liveCase.goldStories.length,
    'citations': citations.length,
    'source_warning': turn.answer.contains('来源警告'),
    'answer_chars': turn.answer.length,
    ...proseMetrics(answer),
    if (usage != null) 'usage': usage.toJson(),
    'answer': turn.answer,
  };
}
