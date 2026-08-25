import 'package:arklores/core/agent/loop_memory.dart';
import 'package:arklores/core/agent/react_loop.dart';
import 'package:arklores/core/agent/tools/agent_tool.dart';
import 'package:arklores/core/agent/tools/tool_registry.dart';
import 'package:arklores/core/llm/llm_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LoopMemory', () {
    test('read index merges paged reads of the same story', () {
      final memory = LoopMemory();
      memory.noteRead('activities/x/level_x_09_beg.txt', 0, 100);
      memory.noteRead('activities/x/level_x_09_beg.txt', 100, 200);
      memory.noteRead('activities/x/level_x_10_end.txt', 0, 50);
      final block = memory.buildBlock();
      expect(block, contains('activities/x/level_x_09_beg.txt:0-200'));
      expect(block, contains('activities/x/level_x_10_end.txt:0-50'));
    });

    test('tracks mapped scopes and collected evidence', () {
      final memory = LoopMemory();
      memory.noteMapped('activity:act33side');
      memory.noteMapped('obt:main');
      memory.noteEvidence('enemy:enemy_1276_telex');
      final block = memory.buildBlock();
      expect(block, contains('已查地图: activity:act33side, obt:main'));
      expect(block, contains('已收集证据: enemy:enemy_1276_telex'));
    });

    test('thought notes are truncated to a guardrail length', () {
      final memory = LoopMemory();
      memory.noteThought(3, '关键结论：${'很长的内容' * 100}');
      final block = memory.buildBlock();
      expect(block, contains('[3]'));
      expect(block, contains('关键结论'));
      expect(block.length, lessThan(400));
    });

    test('empty memory renders an empty block', () {
      expect(LoopMemory().buildBlock(), isEmpty);
    });
  });

  group('ReActLoop layered request (M1)', () {
    test('request size stays bounded across many iterations', () async {
      final mock = _ScriptedLLM(iterations: 14);
      final loop = ReActLoop(
        llmClient: mock,
        toolRegistry: ToolRegistry()..register(_FixedObservationTool()),
      );
      await loop
          .run(
            systemPrompt: 'You are a helper.',
            chatHistory: [],
            userQuery: 'investigate',
          )
          .toList();

      final last = mock.receivedMessages.last;
      final observationCount = last
          .where((m) => m.content.startsWith('Observation: '))
          .length;
      // Recent window only: 2 turns max, regardless of iteration count.
      expect(observationCount, lessThanOrEqualTo(LoopMemory.recentWindowSize));
      expect(last.length, lessThan(20));
    });

    test('memory block carries read index and thought notes', () async {
      final mock = _ScriptedLLM(iterations: 6);
      final loop = ReActLoop(
        llmClient: mock,
        toolRegistry: ToolRegistry()..register(_ReadTool()),
      );
      await loop
          .run(
            systemPrompt: 'You are a helper.',
            chatHistory: [],
            userQuery: 'investigate',
          )
          .toList();

      final last = mock.receivedMessages.last;
      final joined = last.map((m) => m.content).join('\n');
      expect(joined, contains('已读章节: activities/x/level_x_09_beg.txt:0-100'));
      expect(joined, contains('[1] gather more evidence.'));
    });

    test('the model still sees a chapter was read long after its raw '
        'observation left the window (no re-read regression)', () async {
      final mock = _ScriptedLLM(iterations: 12);
      final loop = ReActLoop(
        llmClient: mock,
        toolRegistry: ToolRegistry()..register(_ReadTool()),
      );
      await loop
          .run(
            systemPrompt: 'You are a helper.',
            chatHistory: [],
            userQuery: 'investigate',
          )
          .toList();

      // Iteration 12's request: the raw 09_beg observation (read at
      // iteration 1) is long gone, but the memory block must still list it.
      expect(mock.receivedMessages.length, 13);
      final last = mock.receivedMessages[12];
      final joined = last.map((m) => m.content).join('\n');
      expect(joined, contains('已读章节: activities/x/level_x_09_beg.txt:0-100'));
    });

    test('onMemoryChanged reports the memory block', () async {
      final mock = _ScriptedLLM(iterations: 4);
      final loop = ReActLoop(
        llmClient: mock,
        toolRegistry: ToolRegistry()..register(_ReadTool()),
      );
      final snapshots = <String>[];
      await loop
          .run(
            systemPrompt: 'You are a helper.',
            chatHistory: [],
            userQuery: 'investigate',
            onMemoryChanged: snapshots.add,
          )
          .toList();
      expect(snapshots, isNotEmpty);
      expect(snapshots.last, contains('已读章节'));
    });

    test('fallback request uses the layered context, not the full history',
        () async {
      final mock = _ScriptedLLM(iterations: 10, neverFinalizes: true);
      final loop = ReActLoop(
        llmClient: mock,
        toolRegistry: ToolRegistry()..register(_FixedObservationTool()),
      );
      await loop
          .run(
            systemPrompt: 'You are a helper.',
            chatHistory: [],
            userQuery: 'investigate',
          )
          .toList();

      final fallback = mock.receivedMessages.last;
      final observationCount = fallback
          .where((m) => m.content.startsWith('Observation: '))
          .length;
      expect(observationCount, lessThanOrEqualTo(LoopMemory.recentWindowSize));
      expect(
        fallback.map((m) => m.content).join('\n'),
        contains('Please summarize'),
      );
    });
  });

  group('R7 robustness', () {
    test('memory block lives inside the system message, not as a user message',
        () async {
      final mock = _ScriptedLLM(iterations: 4);
      final loop = ReActLoop(
        llmClient: mock,
        toolRegistry: ToolRegistry()..register(_ReadTool()),
      );
      await loop
          .run(
            systemPrompt: 'You are a helper.',
            chatHistory: [],
            userQuery: 'investigate',
          )
          .toList();

      final last = mock.receivedMessages.last;
      expect(last.first.role, MessageRole.system);
      expect(last.first.content, contains('调查记忆'));
      expect(last.first.content, contains('请勿续写'));
      // No standalone user message may start with the memory block header.
      final userMessages = last
          .where((m) => m.role == MessageRole.user)
          .map((m) => m.content);
      expect(userMessages.any((c) => c.contains('## 调查记忆')), isFalse);
    });

    test('bare prose without Action/Final Answer is retried, not answered',
        () async {
      final mock = _BareProseThenActionLLM();
      final loop = ReActLoop(
        llmClient: mock,
        toolRegistry: ToolRegistry()..register(_FixedObservationTool()),
      );
      final events = await loop
          .run(
            systemPrompt: 'You are a helper.',
            chatHistory: [],
            userQuery: 'investigate',
          )
          .toList();

      final answers = events
          .where((e) => e.type == ReActEventType.finalAnswerToken)
          .map((e) => e.content)
          .join();
      // The final answer is the scripted one, NOT the bare prose.
      expect(answers, contains('结论。'));
      expect(answers, isNot(contains('这是裸思考')));
      // The malformed step produced a format-error observation.
      final joined = mock.receivedMessages
          .expand((m) => m)
          .map((m) => m.content)
          .join('\n');
      expect(joined, contains('did not contain a valid Action or Final Answer'));
    });

    test('repeated malformed responses terminate with an error', () async {
      final mock = _AlwaysBareProseLLM();
      final loop = ReActLoop(
        llmClient: mock,
        toolRegistry: ToolRegistry()..register(_FixedObservationTool()),
      );
      final events = await loop
          .run(
            systemPrompt: 'You are a helper.',
            chatHistory: [],
            userQuery: 'investigate',
          )
          .toList();
      expect(
        events.any((e) =>
            e.type == ReActEventType.error &&
            e.content.contains('repeatedly failed to output'),),
        isTrue,
      );
    });

    test('a truncated step is retried with a concise hint, then completes',
        () async {
      final mock = _TruncateOnceLLM();
      final loop = ReActLoop(
        llmClient: mock,
        toolRegistry: ToolRegistry()..register(_FixedObservationTool()),
      );
      final events = await loop
          .run(
            systemPrompt: 'You are a helper.',
            chatHistory: [],
            userQuery: 'investigate',
          )
          .toList();
      expect(
        events.where((e) => e.type == ReActEventType.error),
        isEmpty,
      );
      final answers = events
          .where((e) => e.type == ReActEventType.finalAnswerToken)
          .map((e) => e.content)
          .join();
      expect(answers, contains('结论。'));
      // The retry hint was injected after the truncation.
      final joined = mock.receivedMessages
          .expand((m) => m)
          .map((m) => m.content)
          .join('\n');
      expect(joined, contains('your previous response was truncated'));
    });

    test('repeated truncation still terminates with the truncation error',
        () async {
      final mock = _AlwaysTruncateLLM();
      final loop = ReActLoop(
        llmClient: mock,
        toolRegistry: ToolRegistry()..register(_FixedObservationTool()),
      );
      final events = await loop
          .run(
            systemPrompt: 'You are a helper.',
            chatHistory: [],
            userQuery: 'investigate',
          )
          .toList();
      expect(
        events.any((e) =>
            e.type == ReActEventType.error &&
            e.content.contains('was truncated'),),
        isTrue,
      );
    });
  });
}

/// Always returns a tool action until [iterations] calls, then a final
/// answer; optionally never finalizes (fallback path). Records requests.
class _ScriptedLLM extends LLMClient {
  _ScriptedLLM({required this.iterations, this.neverFinalizes = false});
  final int iterations;
  final bool neverFinalizes;
  int callCount = 0;
  final List<List<Message>> receivedMessages = [];

  @override
  Future<String> chat(
    List<Message> messages, {
    List<Map<String, dynamic>>? tools,
    double temperature = 0.7,
    int maxTokens = 2048,
    List<String>? stop,
  }) async {
    callCount++;
    receivedMessages.add(List.of(messages));
    final action = callCount <= iterations ? 'read_story_lines' : 'no_tool';
    if (neverFinalizes) {
      return '''
Thought: gather more evidence.
Action: read_story_lines
Action Input: {"story_id": "activities/x/level_x_09_beg.txt", "start_line": 0, "max_lines": 100}
''';
    }
    if (callCount <= iterations) {
      return '''
Thought: gather more evidence.
Action: $action
Action Input: ${action == 'read_story_lines' ? '{"story_id": "activities/x/level_x_09_beg.txt", "start_line": 0, "max_lines": 100}' : '{}'}
''';
    }
    return '''
Thought: I have enough information.
Final Answer: 结论。
''';
  }

  @override
  Future<String> chatStream(
    List<Message> messages, {
    void Function(String token)? onToken,
    double temperature = 0.7,
    int maxTokens = 2048,
    List<String>? stop,
  }) async {
    return chat(
      messages,
      temperature: temperature,
      maxTokens: maxTokens,
      stop: stop,
    );
  }
}

/// `read_story_lines`-shaped tool: returns a story-like observation.
class _ReadTool extends AgentTool {
  @override
  String get name => 'read_story_lines';

  @override
  String get description => 'Reads story lines.';

  @override
  Map<String, dynamic> get parameters => {
        'type': 'object',
        'properties': {
          'story_id': {'type': 'string'},
          'start_line': {'type': 'integer'},
          'max_lines': {'type': 'integer'},
        },
        'required': ['story_id'],
      };

  @override
  Future<dynamic> execute(Map<String, dynamic> arguments) async {
    final storyId = '${arguments['story_id']}';
    return ToolExecutionResult(
      observation: 'Story: $storyId\n0 | 角色A | 台词',
    );
  }
}

/// Any tool returning a fixed observation.
class _FixedObservationTool extends AgentTool {
  @override
  String get name => 'read_story_lines';

  @override
  String get description => 'Reads story lines.';

  @override
  Map<String, dynamic> get parameters => {
        'type': 'object',
        'properties': {
          'story_id': {'type': 'string'},
        },
        'required': ['story_id'],
      };

  @override
  Future<dynamic> execute(Map<String, dynamic> arguments) async {
    return const ToolExecutionResult(observation: 'Fixed observation');
  }
}

/// First output is bare prose (no Thought/Action/Final Answer keys), then a
/// proper tool step, then a final answer. Records requests.
class _BareProseThenActionLLM extends LLMClient {
  int callCount = 0;
  final List<List<Message>> receivedMessages = [];

  @override
  Future<String> chat(
    List<Message> messages, {
    List<Map<String, dynamic>>? tools,
    double temperature = 0.7,
    int maxTokens = 2048,
    List<String>? stop,
  }) async {
    callCount++;
    receivedMessages.add(List.of(messages));
    switch (callCount) {
      case 1:
        return '这是裸思考文本，没有任何格式键。';
      case 2:
        return '''
Thought: gather more evidence.
Action: read_story_lines
Action Input: {"story_id": "activities/x/level_x_09_beg.txt"}
''';
      default:
        return '''
Thought: I have enough information.
Final Answer: 结论。
''';
    }
  }

  @override
  Future<String> chatStream(
    List<Message> messages, {
    void Function(String token)? onToken,
    double temperature = 0.7,
    int maxTokens = 2048,
    List<String>? stop,
  }) async {
    return chat(
      messages,
      temperature: temperature,
      maxTokens: maxTokens,
      stop: stop,
    );
  }
}

/// Always outputs bare prose.
class _AlwaysBareProseLLM extends LLMClient {
  @override
  Future<String> chat(
    List<Message> messages, {
    List<Map<String, dynamic>>? tools,
    double temperature = 0.7,
    int maxTokens = 2048,
    List<String>? stop,
  }) async {
    return '又是裸思考文本，还是没有格式键。';
  }

  @override
  Future<String> chatStream(
    List<Message> messages, {
    void Function(String token)? onToken,
    double temperature = 0.7,
    int maxTokens = 2048,
    List<String>? stop,
  }) async {
    return chat(
      messages,
      temperature: temperature,
      maxTokens: maxTokens,
      stop: stop,
    );
  }
}

/// First `chatCompletion` returns a truncated result, later ones succeed.
class _TruncateOnceLLM extends LLMClient {
  int callCount = 0;
  final List<List<Message>> receivedMessages = [];

  @override
  Future<ChatCompletionResult> chatCompletion(
    List<Message> messages, {
    List<Map<String, dynamic>>? tools,
    double temperature = 0.7,
    int maxTokens = 2048,
    List<String>? stop,
  }) async {
    callCount++;
    receivedMessages.add(List.of(messages));
    if (callCount == 1) {
      return const ChatCompletionResult(
        content: '',
        finishReason: 'length',
      );
    }
    if (callCount == 2) {
      return const ChatCompletionResult(
        content: '''
Thought: gather more evidence.
Action: read_story_lines
Action Input: {"story_id": "activities/x/level_x_09_beg.txt"}
''',
      );
    }
    return const ChatCompletionResult(
      content: '''
Thought: I have enough information.
Final Answer: 结论。
''',
    );
  }

  @override
  Future<String> chat(
    List<Message> messages, {
    List<Map<String, dynamic>>? tools,
    double temperature = 0.7,
    int maxTokens = 2048,
    List<String>? stop,
  }) async {
    final result = await chatCompletion(
      messages,
      tools: tools,
      temperature: temperature,
      maxTokens: maxTokens,
      stop: stop,
    );
    return result.content;
  }

  @override
  Future<String> chatStream(
    List<Message> messages, {
    void Function(String token)? onToken,
    double temperature = 0.7,
    int maxTokens = 2048,
    List<String>? stop,
  }) async {
    return chat(
      messages,
      temperature: temperature,
      maxTokens: maxTokens,
      stop: stop,
    );
  }
}

/// Always returns a truncated result.
class _AlwaysTruncateLLM extends LLMClient {
  @override
  Future<ChatCompletionResult> chatCompletion(
    List<Message> messages, {
    List<Map<String, dynamic>>? tools,
    double temperature = 0.7,
    int maxTokens = 2048,
    List<String>? stop,
  }) async {
    return const ChatCompletionResult(content: '', finishReason: 'length');
  }

  @override
  Future<String> chat(
    List<Message> messages, {
    List<Map<String, dynamic>>? tools,
    double temperature = 0.7,
    int maxTokens = 2048,
    List<String>? stop,
  }) async {
    return '';
  }

  @override
  Future<String> chatStream(
    List<Message> messages, {
    void Function(String token)? onToken,
    double temperature = 0.7,
    int maxTokens = 2048,
    List<String>? stop,
  }) async {
    return '';
  }
}
