import 'dart:convert';

import 'package:arklores/core/llm/llm_client.dart';

Map<String, dynamic> replayMessageJson(Message m) => {
      ...m.toJson(),
      if (m.reasoningContent != null) 'reasoning_content': m.reasoningContent,
    };

int replayChars(String text) => text.runes.length;

Map<String, dynamic> replayArguments(ToolCall call) =>
    jsonDecode(call.arguments) as Map<String, dynamic>;

/// Counts payload text rather than JSON framing; tool arguments and reasoning
/// are text the provider receives too. Tool schemas use their complete JSON.
Map<String, Object?> measureReplayRequest(
  List<Message> messages,
  List<Map<String, dynamic>>? tools,
) {
  int chars(Message m) =>
      replayChars(m.content) +
      replayChars(m.reasoningContent ?? '') +
      (m.toolCalls == null ? 0 : replayChars(jsonEncode(m.toolCalls)));
  final system = messages
      .where((m) => m.role == MessageRole.system)
      .fold(0, (n, m) => n + chars(m));
  final dialogue = messages
      .where((m) => m.role != MessageRole.system)
      .fold(0, (n, m) => n + chars(m));
  final specs =
      tools == null || tools.isEmpty ? 0 : replayChars(jsonEncode(tools));
  return {
    'system_chars': system,
    'tool_schema_chars': specs,
    'dialogue_chars': dialogue,
    'total_chars': system + specs + dialogue,
    'message_count': messages.length,
  };
}

/// Exhaustion is an error, so a rejected answer cannot silently reuse a reply.
class ReplayLLM extends LLMClient {
  ReplayLLM(this.script, {required this.phase, required this.requests});
  final List<Message> script;
  final String phase;
  final List<Map<String, Object?>> requests;
  int next = 0;

  @override
  Future<String> chat(
    List<Message> messages, {
    List<Map<String, dynamic>>? tools,
    double temperature = 0.7,
    int maxTokens = 2048,
    List<String>? stop,
  }) async =>
      (await chatCompletion(messages, tools: tools)).content;

  @override
  Future<ChatCompletionResult> chatCompletion(
    List<Message> messages, {
    List<Map<String, dynamic>>? tools,
    double temperature = 0.7,
    int maxTokens = 2048,
    List<String>? stop,
    Future<void>? abortTrigger,
  }) async {
    requests.add({
      'index': requests.length + 1,
      'phase': phase,
      'script_index': next + 1,
      ...measureReplayRequest(messages, tools),
    });
    if (next >= script.length) throw StateError('$phase script exhausted');
    final m = script[next++];
    return ChatCompletionResult(
      content: m.content,
      reasoningContent: m.reasoningContent ?? '',
      toolCalls: [
        for (final c in m.toolCalls ?? <Map<String, dynamic>>[])
          ToolCall.fromJson(c),
      ],
    );
  }
}

Map<String, dynamic> replayPlan(List<Message> messages, {required bool wiki}) {
  final calls = [
    for (final c in messages
        .firstWhere(
          (m) => (m.toolCalls ?? [])
              .any((c) => '${c['id']}'.startsWith('planned_')),
        )
        .toolCalls!)
      ToolCall.fromJson(c),
  ];
  final searches = [
    for (final c in calls)
      if (c.name == 'search') jsonDecode(c.arguments) as Map<String, dynamic>,
  ];
  return {
    'search': [for (final s in searches) s['query']],
    if (wiki && searches.isNotEmpty) 'wiki': searches.first['wiki'],
    'anchors': [
      for (final c in calls)
        if (c.name == 'gather') ...(replayArguments(c)['names'] as List),
    ],
    'outline': [
      for (final c in calls)
        if (c.name == 'outline') replayArguments(c)['collection'],
    ],
    if (wiki)
      'wiki_search': [
        for (final c in calls)
          if (c.name == 'wiki_search') replayArguments(c)['query'],
      ],
  };
}

List<Message> replayScript(List<Message> messages, {required bool wiki}) => [
      for (final m in messages)
        if (m.role == MessageRole.assistant &&
            !(m.toolCalls ?? [])
                .any((c) => '${c['id']}'.startsWith('planned_')))
          Message(
            role: m.role,
            content: m.content,
            reasoningContent: m.reasoningContent,
            toolCalls: m.toolCalls == null
                ? null
                : [
                    for (final raw in m.toolCalls!)
                      (() {
                        final c = ToolCall.fromJson(raw);
                        if (wiki || c.name != 'search') return c.toJson();
                        final args =
                            jsonDecode(c.arguments) as Map<String, dynamic>;
                        args.remove('wiki');
                        return ToolCall(
                          id: c.id,
                          name: c.name,
                          arguments: jsonEncode(args),
                        ).toJson();
                      })(),
                  ],
          ),
    ];

/// A read-only run may be interleaved with reads of other stories. A different
/// tool ends the run: later searches may depend on what the preceding read found.
/// Disjoint union ranges become parallel calls in the first message, avoiding
/// the production tool's 300-line limit without adding unread gaps.
List<Message> mergeReplayReads(List<Message> script) {
  final output = <Message>[];
  var run = <Message>[];
  void flush() {
    if (run.isEmpty) return;
    final ranges = <String, List<(int, int)>>{};
    for (final m in run) {
      for (final raw in m.toolCalls!) {
        final c = ToolCall.fromJson(raw);
        if (c.name != 'read_story') continue;
        final a = jsonDecode(c.arguments) as Map<String, dynamic>;
        final start = (a['start'] as int? ?? 0).clamp(0, 1 << 30);
        final count = (a['count'] as int? ?? 200).clamp(1, 300);
        (ranges['${a['story_id']}'] ??= []).add((start, start + count));
      }
    }
    final emitted = <String>{};
    for (final m in run) {
      final calls = <ToolCall>[];
      for (final raw in m.toolCalls!) {
        final c = ToolCall.fromJson(raw);
        if (c.name != 'read_story') {
          calls.add(c);
          continue;
        }
        final id = '${replayArguments(c)['story_id']}';
        if (!emitted.add(id)) continue;
        final sorted = ranges[id]!..sort((a, b) => a.$1.compareTo(b.$1));
        final union = <(int, int)>[];
        for (final r in sorted) {
          if (union.isNotEmpty && r.$1 <= union.last.$2) {
            final last = union.removeLast();
            union.add((last.$1, r.$2 > last.$2 ? r.$2 : last.$2));
          } else {
            union.add(r);
          }
        }
        var part = 0;
        for (final r in union) {
          for (var start = r.$1; start < r.$2; start += 100) {
            // Smaller pages keep the 8k character cap from hiding a union tail.
            calls.add(
              ToolCall(
                id: '${c.id}_merge_${part++}',
                name: 'read_story',
                arguments: jsonEncode({
                  'story_id': id,
                  'start': start,
                  'count': (r.$2 - start).clamp(1, 100),
                }),
              ),
            );
          }
        }
      }
      if (calls.isNotEmpty) {
        output.add(
          Message.assistantToolCalls(
            m.content,
            calls,
            reasoningContent: m.reasoningContent,
          ),
        );
      }
    }
    run = [];
  }

  for (final m in script) {
    final calls = m.toolCalls ?? [];
    if (calls.isNotEmpty &&
        calls.every((c) => ToolCall.fromJson(c).name == 'read_story')) {
      run.add(m);
    } else if (calls.any((c) => ToolCall.fromJson(c).name == 'read_story')) {
      run.add(m);
      flush();
    } else {
      flush();
      output.add(m);
    }
  }
  flush();
  return output;
}

/// Mirrors dup.py's cross-message counting; story identity uses the line index,
/// with the full text retained separately for checking the historical metric.
Map<String, Object?> replayDuplicates(List<Message> messages) {
  final headers = RegExp(r'^(?:\d+\. |## )?《(.+?)》 (\S+)');
  final line = RegExp(r'^\s*L(\d+) ');
  final prefix = RegExp(r'^(\s*L\d+ (?:\[[^\]]*\] )?)(.*)$');
  final seen = <String, int>{};
  final exactSeen = <String, int>{};
  var repeatedLines = 0, repeatedOther = 0, exact = 0;
  var tags = 0, body = 0, unknown = 0;
  final boilerplate = <String, int>{};
  for (final (i, m) in messages.indexed) {
    if (m.role != MessageRole.tool) continue;
    String? story;
    for (final text in m.content.split('\n')) {
      final h = headers.firstMatch(text);
      if (h != null) story = h.group(2);
      final l = line.firstMatch(text);
      final p = prefix.firstMatch(text);
      if (p != null) {
        tags += replayChars(p.group(1)!);
        body += replayChars(p.group(2)!);
      }
      final trimmed = text.trim();
      if (replayChars(trimmed) < 8) continue;
      final size = replayChars(text) + 1;
      final exactKey = l == null ? trimmed : '$story|$trimmed';
      if (exactSeen.containsKey(exactKey) && exactSeen[exactKey] != i) {
        exact += size;
      }
      exactSeen.putIfAbsent(exactKey, () => i);
      if (l != null && story == null) unknown++;
      final key = l == null ? trimmed : '$story|${l.group(1)}';
      if (seen.containsKey(key) && seen[key] != i) {
        if (l == null) {
          repeatedOther += size;
        } else {
          repeatedLines += size;
        }
      }
      seen.putIfAbsent(key, () => i);
      if (l == null && replayChars(text) > 20) {
        boilerplate.update(trimmed, (n) => n + 1, ifAbsent: () => 1);
      }
    }
  }
  final repeated = boilerplate.entries.where((e) => e.value > 1).toList()
    ..sort(
      (a, b) => ((b.value - 1) * replayChars(b.key)).compareTo(
        (a.value - 1) * replayChars(a.key),
      ),
    );
  return {
    'story_line_duplicate_chars': repeatedLines,
    'other_duplicate_chars': repeatedOther,
    'duplicate_chars': repeatedLines + repeatedOther,
    'dup_py_exact_duplicate_chars': exact,
    'fixed_line_repeat_chars':
        repeated.fold<int>(0, (n, e) => n + (e.value - 1) * replayChars(e.key)),
    'repeated_non_dialogue_lines': [
      for (final e in repeated)
        {
          'text': e.key,
          'occurrences': e.value,
          'repeat_chars': (e.value - 1) * replayChars(e.key),
        },
    ],
    'prefix_chars': tags,
    'story_body_chars': body,
    'prefix_ratio': tags + body == 0 ? 0 : tags / (tags + body),
    'lines_without_story_header': unknown,
  };
}
