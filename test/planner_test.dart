import 'package:arklores/core/agent/investigation_state.dart';
import 'package:arklores/core/agent/planner_intent.dart';
import 'package:arklores/core/agent/planner_loop.dart';
import 'package:arklores/core/agent/react_loop.dart';
import 'package:arklores/core/agent/tools/agent_tool.dart';
import 'package:arklores/core/agent/tools/tool_registry.dart';
import 'package:arklores/core/llm/llm_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseIntent', () {
    test('parses READ with and without line range', () {
      final withRange = parseIntent('READ activities/x/level_x.txt 100 200');
      expect(withRange!.action, 'READ');
      expect(withRange.args['story_id'], 'activities/x/level_x.txt');
      expect(withRange.args['start_line'], 100);
      expect(withRange.args['end_line'], 200);

      final bare = parseIntent('READ activities/x/level_x.txt');
      expect(bare!.args['story_id'], 'activities/x/level_x.txt');
      expect(bare.args.containsKey('start_line'), isFalse);
    });

    test('parses COLLECT with claim terms', () {
      final intent =
          parseIntent('COLLECT speaker:博士 claim_terms=[杀,特蕾西娅,血]');
      expect(intent!.action, 'COLLECT');
      expect(intent.args['entity_id'], 'speaker:博士');
      expect(intent.args['claim_terms'], ['杀', '特蕾西娅', '血']);
    });

    test('parses VERDICT / DONE / MAP', () {
      final verdict = parseIntent('VERDICT char_b 0.8 multi_hypothesis_contrast');
      expect(verdict!.action, 'VERDICT');
      expect(verdict.args['culprit'], 'char_b');
      expect(verdict.args['confidence'], '0.8');

      expect(parseIntent('DONE')!.action, 'DONE');
      expect(parseIntent('MAP activity:act33side')!.args['scope_id'],
          'activity:act33side',);
    });

    test('rejects non-intent lines', () {
      expect(parseIntent('随便说点什么'), isNull);
      expect(parseIntent(''), isNull);
      expect(parseIntent('Thought: 思考'), isNull);
    });
  });

  group('InvestigationState', () {
    test('serializes stages, reads, evidence, mapped', () {
      final state = InvestigationState();
      state.noteStage('S1');
      state.noteStage('S3');
      state.noteRead('activities/x/level_x_09_beg.txt', 0, 103);
      state.setKeyPoints('activities/x/level_x_09_beg.txt', '刺客受摄政王派遣');
      state.noteEvidence('speaker:博士', evidenceRows: 14, scopes: ['obt:main']);
      state.noteMapped('activity:act33side');

      final text = state.serialize();
      expect(text, contains('阶段: S1,S3'));
      expect(text, contains('09_beg.txt:0-103'));
      expect(text, contains('刺客受摄政王派遣'));
      expect(text, contains('speaker:博士: 14行'));
      expect(text, contains('act33side'));
    });

    test('read merges ranges and keeps key points', () {
      final state = InvestigationState();
      state.noteRead('s1', 0, 100);
      state.setKeyPoints('s1', '要点A');
      state.noteRead('s1', 100, 200);
      final text = state.serialize();
      expect(text, contains('s1:0-200'));
      expect(text, contains('要点A'));
    });
  });

  group('PlannerLoop execution', () {
    test('runs READ -> VERDICT -> DONE with bounded requests', () async {
      final mock = _PlannerScriptLLM();
      final loop = PlannerLoop(
        llmClient: mock,
        toolRegistry: ToolRegistry()..register(_ReadTool()),
        minimumToolCalls: 1,
      );
      final events = await loop
          .run(
            systemPrompt: 'You are a helper.',
            chatHistory: [],
            userQuery: '调查某角色之死',
          )
          .toList();

      // Finished with a verdict envelope.
      final answer = events
          .where((e) => e.type == ReActEventType.finalAnswerToken)
          .map((e) => e.content)
          .join();
      expect(answer, contains('[INVESTIGATION_VERDICT: culprit=char_b'));
      // Request context stays tiny: state + recent observation only.
      expect(mock.receivedRequests.length, greaterThan(1));
      for (final request in mock.receivedRequests) {
        expect(request.length, lessThan(8));
      }
    });

    test('invalid intents are retried, then terminate', () async {
      final mock = _AlwaysInvalidIntentLLM();
      final loop = PlannerLoop(
        llmClient: mock,
        toolRegistry: ToolRegistry()..register(_ReadTool()),
      );
      final events = await loop
          .run(
            systemPrompt: 'You are a helper.',
            chatHistory: [],
            userQuery: 'q',
          )
          .toList();
      expect(
        events.any((e) =>
            e.type == ReActEventType.error &&
            e.content.contains('无效意图'),),
        isTrue,
      );
    });

    test('network error retries then completes', () async {
      final mock = _NetworkOnceLLM();
      final loop = PlannerLoop(
        llmClient: mock,
        toolRegistry: ToolRegistry()..register(_ReadTool()),
        minimumToolCalls: 1,
      );
      final events = await loop
          .run(
            systemPrompt: 'You are a helper.',
            chatHistory: [],
            userQuery: 'q',
          )
          .toList();
      final answer = events
          .where((e) => e.type == ReActEventType.finalAnswerToken)
          .map((e) => e.content)
          .join();
      expect(answer, contains('INVESTIGATION_VERDICT'));
      // The network error was retried (a second request happened).
      expect(mock.receivedRequests.length, greaterThan(1));
    });
  });
}

/// Scripted planner LLM: READ once, then VERDICT, then DONE.
class _PlannerScriptLLM extends LLMClient {
  int callCount = 0;
  final List<List<Message>> receivedRequests = [];

  @override
  Future<String> chat(
    List<Message> messages, {
    List<Map<String, dynamic>>? tools,
    double temperature = 0.7,
    int maxTokens = 2048,
    List<String>? stop,
  }) async {
    callCount++;
    receivedRequests.add(List.of(messages));
    switch (callCount) {
      case 1:
        return 'READ activities/x/level_x.txt 0 100';
      case 2:
        return 'VERDICT char_b 0.8 multi_hypothesis_contrast';
      default:
        return 'DONE';
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

class _AlwaysInvalidIntentLLM extends LLMClient {
  @override
  Future<String> chat(
    List<Message> messages, {
    List<Map<String, dynamic>>? tools,
    double temperature = 0.7,
    int maxTokens = 2048,
    List<String>? stop,
  }) async {
    return '今天天气不错';
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

/// First call throws a network error, later ones succeed.
class _NetworkOnceLLM extends LLMClient {
  int callCount = 0;
  final List<List<Message>> receivedRequests = [];

  @override
  Future<String> chat(
    List<Message> messages, {
    List<Map<String, dynamic>>? tools,
    double temperature = 0.7,
    int maxTokens = 2048,
    List<String>? stop,
  }) async {
    callCount++;
    receivedRequests.add(List.of(messages));
    if (callCount == 1) {
      throw const LLMException('ClientException: Connection closed while receiving data');
    }
    switch (callCount) {
      case 2:
        return 'READ activities/x/level_x.txt 0 100';
      case 3:
        return 'VERDICT char_b 0.8 multi_hypothesis_contrast';
      default:
        return 'DONE';
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
          'end_line': {'type': 'integer'},
        },
        'required': ['story_id'],
      };

  @override
  Future<dynamic> execute(Map<String, dynamic> arguments) async {
    return const ToolExecutionResult(
      observation: 'Story: s\n0 | 角色A | 台词\nRead Lines: 100',
    );
  }
}
