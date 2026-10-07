// The text-protocol ReAct loop (the roleplay agent's engine): parsing the
// model's steps, tool calls, the layered request with its memory block,
// malformed/truncated output, the fallback answer and the live preview.
import 'package:arklores/core/agent/loop_memory.dart';
import 'package:arklores/core/agent/react_loop.dart';
import 'package:arklores/core/agent/tools/agent_tool.dart';
import 'package:arklores/core/agent/tools/tool_registry.dart';
import 'package:arklores/core/llm/llm_client.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_llm.dart';

const _read = '{"story_id": "activities/x/level_x_09_beg.txt", '
    '"start_line": 0, "max_lines": 100}';

/// Reads a chapter [n] times, then answers `结论。`.
ScriptedLLM _reads(int n) => ScriptedLLM([
      for (var i = 0; i < n; i++)
        reactAction('read_story_lines', _read, thought: 'gather more evidence.'),
      reactFinal('结论。'),
    ]);

Future<List<ReActEvent>> _run(
  LLMClient llm, {
  List<AgentTool> tools = const [],
  int minimumToolCalls = 0,
  int safetyMaxIterations = 1000,
  String query = 'q',
  void Function(String)? onMemoryChanged,
}) {
  final registry = ToolRegistry();
  for (final t in tools) {
    registry.register(t);
  }
  return ReActLoop(
    llmClient: llm,
    toolRegistry: registry,
    minimumToolCalls: minimumToolCalls,
    safetyMaxIterations: safetyMaxIterations,
  )
      .run(
        systemPrompt: 'You are a helper.',
        chatHistory: const [],
        userQuery: query,
        onMemoryChanged: onMemoryChanged,
      )
      .toList();
}

String _joined(List<Message> request) =>
    request.map((m) => m.content).join('\n');

void main() {
  group('steps and tool calls', () {
    test('runs a tool, then yields the final answer', () async {
      final events = await _run(
        ScriptedLLM([
          reactAction('search_local_lore', '{"query": "W"}'),
          reactFinal('W is a mercenary.'),
        ]),
        tools: [_Tool.fixed('search_local_lore', 'W is a mercenary.')],
      );
      expect(
        events.map((e) => e.type),
        containsAll([
          ReActEventType.thought,
          ReActEventType.toolCall,
          ReActEventType.toolObservation,
          ReActEventType.finalAnswerToken,
          ReActEventType.complete,
        ]),
      );
      expect(finalAnswerOf(events), contains('W is a mercenary'));
    });

    // Action inputs as providers actually write them.
    for (final (name, step, query, topK) in [
      (
        'loose key-value maps',
        'Thought: x\nAction: search_local_lore\nAction Input: {query: 缪因, top_k: 5}',
        '缪因',
        5,
      ),
      (
        'prose after the JSON',
        'Thought: x\nAction: search_local_lore\n'
            'Action Input: {"query": "阿米娅 档案 干员 罗德岛", "top_k": 5}\n'
            'Based on the search results, I should continue reasoning here.',
        '阿米娅 档案 干员 罗德岛',
        5,
      ),
      (
        'extra action metadata lines',
        'Action: search_local_lore\nAction Query: arg/search\n'
            'Action Tool: search_local_lore\n'
            'Action Input: {"query":"scope entity relation"}',
        'scope entity relation',
        null,
      ),
      (
        'an action right after sentence punctuation',
        '现在查询实体。Action: search_local_lore\nAction Input: {"query":"米格鲁"}',
        '米格鲁',
        null,
      ),
    ]) {
      test('parses $name', () async {
        final tool = _Tool.capture('search_local_lore');
        final events = await _run(
          ScriptedLLM([step, reactFinal('done')]),
          tools: [tool],
        );
        expect(tool.lastArgs?['query'], query);
        if (topK != null) expect(tool.lastArgs?['top_k'], topK);
        expect(finalAnswerOf(events), contains('done'));
      });
    }

    test('a required tool call refuses an early answer', () async {
      final tool = _Tool.capture('search_local_lore');
      final events = await _run(
        ScriptedLLM([
          'Final Answer: unverified',
          reactAction('search_local_lore', '{"query":"required evidence"}'),
          'Final Answer: verified',
        ]),
        tools: [tool],
        minimumToolCalls: 1,
      );
      expect(tool.lastArgs?['query'], 'required evidence');
      expect(finalAnswerOf(events), 'verified');
    });

    test('handbook metadata in an answer is not a Book source claim', () async {
      final answer = finalAnswerOf(await _run(
        ScriptedLLM(['Final Answer: Content Type: operator_handbook_profile']),
      ),);
      expect(answer, contains('operator_handbook_profile'));
      expect(answer, isNot(contains('mentions Book evidence')));
    });
  });

  group('layered request', () {
    test('only the recent observations stay; the memory block replaces the rest',
        () async {
      final llm = _reads(14);
      await _run(llm, tools: [_Tool.fixed('read_story_lines', 'Fixed observation')]);
      final last = llm.received.last;
      expect(
        last.where((m) => m.content.startsWith('Observation: ')).length,
        lessThanOrEqualTo(LoopMemory.recentWindowSize),
      );
      expect(last.length, lessThan(20));
      expect(_joined(last), contains('调查要点'));
      expect(_joined(last), isNot(contains('[prior observation trimmed')));
    });

    test('the memory block carries the read index and thought notes', () async {
      final llm = _reads(6);
      await _run(llm, tools: [_Tool.story()]);
      final joined = _joined(llm.received.last);
      expect(joined, contains('已读章节: activities/x/level_x_09_beg.txt:0-100'));
      expect(joined, contains('[1] gather more evidence.'));
    });

    test('a chapter read long ago is still listed as read', () async {
      final llm = _reads(12);
      await _run(llm, tools: [_Tool.story()]);
      // Request 13: the raw observation of read 1 is long gone.
      expect(llm.calls, 13);
      expect(_joined(llm.received[12]),
          contains('已读章节: activities/x/level_x_09_beg.txt:0-100'),);
    });

    test('the memory block sits in the system message', () async {
      final llm = _reads(4);
      await _run(llm, tools: [_Tool.story()]);
      final last = llm.received.last;
      expect(last.first.role, MessageRole.system);
      expect(last.first.content, contains('调查记忆'));
      expect(last.first.content, contains('请勿续写'));
      expect(
        last
            .where((m) => m.role == MessageRole.user)
            .any((m) => m.content.contains('## 调查记忆')),
        isFalse,
      );
    });

    test('onMemoryChanged reports the memory block', () async {
      final snapshots = <String>[];
      await _run(_reads(4), tools: [_Tool.story()], onMemoryChanged: snapshots.add);
      expect(snapshots, isNotEmpty);
      expect(snapshots.last, contains('已读章节'));
    });
  });

  group('malformed and truncated output', () {
    test('bare prose is retried, not taken as the answer', () async {
      final llm = ScriptedLLM([
        '这是裸思考文本，没有任何格式键。',
        reactAction('read_story_lines', '{"story_id": "s"}'),
        reactFinal('结论。'),
      ]);
      final events = await _run(llm, tools: [_Tool.story()]);
      expect(finalAnswerOf(events), contains('结论。'));
      expect(finalAnswerOf(events), isNot(contains('这是裸思考')));
      expect(llm.received.map(_joined).join(),
          contains('did not contain a valid Action or Final Answer'),);
    });

    test('repeated bare prose ends with an error', () async {
      final events = await _run(ScriptedLLM(['又是裸思考文本，还是没有格式键。']),
          tools: [_Tool.story()],);
      expect(
        events.any((e) =>
            e.type == ReActEventType.error &&
            e.content.contains('repeatedly failed to output'),),
        isTrue,
      );
    });

    test('an empty final answer is an error', () async {
      final events = await _run(ScriptedLLM(['Thought: done\nFinal Answer:']));
      expect(
        events.firstWhere((e) => e.type == ReActEventType.error).content,
        contains('empty final answer'),
      );
    });

    test('a truncated step is retried with a hint, then completes', () async {
      final llm = _Truncating(truncatedCalls: {1}, then: [
        reactAction('read_story_lines', '{"story_id": "s"}'),
        reactFinal('结论。'),
      ],);
      final events = await _run(llm, tools: [_Tool.story()]);
      expect(events.where((e) => e.type == ReActEventType.error), isEmpty);
      expect(finalAnswerOf(events), contains('结论。'));
      expect(llm.received.map(_joined).join(),
          contains('your previous response was truncated'),);
    });

    test('repeated truncation ends with the truncation error', () async {
      final events = await _run(_Truncating(truncatedCalls: null, then: const []),
          tools: [_Tool.story()],);
      expect(
        events.any((e) =>
            e.type == ReActEventType.error && e.content.contains('truncated'),),
        isTrue,
      );
    });
  });

  group('fallback answer at the iteration limit', () {
    test('uses the layered context, not the full history', () async {
      final llm = ScriptedLLM(
          [reactAction('read_story_lines', _read, thought: 'gather more.')],);
      await _run(llm, tools: [_Tool.fixed('read_story_lines', 'Fixed observation')]);
      final fallback = llm.received.last;
      expect(
        fallback.where((m) => m.content.startsWith('Observation: ')).length,
        lessThanOrEqualTo(LoopMemory.recentWindowSize),
      );
      expect(_joined(fallback), contains('Please summarize'));
    });

    test('warns when the answer claims a source nothing returned', () async {
      final llm = ScriptedLLM([
        reactAction('search_local_lore', '{"query": "阿米娅"}'),
        'Final Answer: 我已通过 Wiki 获取了阿米娅的背景概述。',
      ]);
      final events = await _run(
        llm,
        tools: [_Tool.fixed('search_local_lore', 'No matching records found in the database.')],
        safetyMaxIterations: 1,
        query: '阿米娅',
      );
      expect(llm.received.last.last.content, contains('Wiki evidence available: no'));
      expect(finalAnswerOf(events), contains('Source warning'));
      expect(finalAnswerOf(events), contains('did not retrieve any observation'));
    });

    test('counts GameData no-result observations', () async {
      final llm = ScriptedLLM([
        reactAction('search_local_lore', '{"query": "阿米娅"}'),
        'Final Answer: x',
      ]);
      await _run(
        llm,
        tools: [
          _Tool.fixed(
            'search_local_lore',
            'No matching GameData result found for "阿米娅 主线". The local '
                'GameData knowledge DB is installed, but structured/FTS search '
                'returned no result.',
          ),
        ],
        safetyMaxIterations: 1,
      );
      final prompt = llm.received.last.last.content;
      expect(prompt, contains('Empty/error observations seen: 1'));
      expect(prompt, contains('Do not add well-known lore'));
    });
  });

  group('live preview', () {
    test('text after "Final Answer:" streams, then is replaced', () async {
      final events = await _run(_Streaming([
        ['Thought: 好。\nFinal', ' Answer: 你', '好，博士。'],
      ]),);
      expect(
        events
            .where((e) => e.type == ReActEventType.finalAnswerToken)
            .map((e) => e.content)
            .join(),
        '你好，博士。',
      );
      expect(events.any((e) => e.type == ReActEventType.finalAnswerReplace),
          isTrue,);
      expect(finalAnswerOf(events), '你好，博士。');
    });

    test('a refused early answer is cleared before the next step', () async {
      final events = await _run(
        _Streaming([
          ['Thought: 直接答。\nFinal Answer: 太早了'],
          ['Thought: 查一下。\nAction: lookup\nAction Input: {"query": "x"}'],
          ['Thought: 好。\nFinal Answer: 查过了'],
        ]),
        tools: [_Tool.fixed('lookup', 'found')],
        minimumToolCalls: 1,
      );
      expect(events.map((e) => e.type), contains(ReActEventType.finalAnswerReset));
      expect(finalAnswerOf(events), '查过了');
    });
  });
}

/// A tool named [name]: returns a fixed text, echoes a story read, or keeps
/// the arguments it got.
class _Tool extends AgentTool {
  _Tool.fixed(this.name, String text) : _reply = ((_) => text);
  _Tool.story()
      : name = 'read_story_lines',
        _reply = ((a) => 'Story: ${a['story_id']}\n0 | 角色A | 台词');
  _Tool.capture(this.name) : _reply = ((_) => 'captured');

  @override
  final String name;
  final String Function(Map<String, dynamic>) _reply;
  Map<String, dynamic>? lastArgs;

  @override
  String get description => 'test tool';

  @override
  Map<String, dynamic> get parameters => const {
        'type': 'object',
        'properties': {
          'query': {'type': 'string'},
          // The loose `key: value` parser reads types from the schema.
          'top_k': {'type': 'integer'},
          'story_id': {'type': 'string'},
        },
      };

  @override
  Future<dynamic> execute(Map<String, dynamic> arguments) async {
    lastArgs = Map.of(arguments);
    return ToolExecutionResult(observation: _reply(arguments));
  }
}

/// Answers `finish_reason: length` on [truncatedCalls] (every call when
/// null), otherwise the next step of [then].
class _Truncating extends ScriptedLLM {
  _Truncating({required this.truncatedCalls, required List<String> then})
      : super(then.isEmpty ? [''] : then);
  final Set<int>? truncatedCalls;
  var _call = 0;

  @override
  Future<ChatCompletionResult> chatCompletion(
    List<Message> messages, {
    List<Map<String, dynamic>>? tools,
    double temperature = 0.7,
    int maxTokens = 2048,
    List<String>? stop,
  }) async {
    _call++;
    if (truncatedCalls == null || truncatedCalls!.contains(_call)) {
      received.add(List.of(messages));
      return const ChatCompletionResult(content: '', finishReason: 'length');
    }
    return ChatCompletionResult(content: await chat(messages));
  }
}

/// Streams scripted chunks, one script per step.
class _Streaming extends LLMClient {
  _Streaming(this.steps);
  final List<List<String>> steps;
  var _step = 0;

  @override
  Future<String> chat(
    List<Message> messages, {
    List<Map<String, dynamic>>? tools,
    double temperature = 0.7,
    int maxTokens = 2048,
    List<String>? stop,
  }) async =>
      steps.last.join();

  @override
  Stream<CompletionDelta> streamCompletion(
    List<Message> messages, {
    double temperature = 0.7,
    int maxTokens = 2048,
    List<String>? stop,
  }) async* {
    final chunks = steps[_step < steps.length ? _step : steps.length - 1];
    _step++;
    for (final chunk in chunks) {
      yield CompletionDelta(content: chunk);
    }
    yield const CompletionDelta(done: true, finishReason: 'stop');
  }
}
