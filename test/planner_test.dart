import 'package:arklores/core/agent/entity_disambiguator.dart';
import 'package:arklores/core/agent/investigation_state.dart';
import 'package:arklores/core/agent/planner_intent.dart';
import 'package:arklores/core/agent/planner_loop.dart';
import 'package:arklores/core/agent/react_loop.dart';
import 'package:arklores/core/agent/story_answer.dart';
import 'package:arklores/core/agent/tools/agent_tool.dart';
import 'package:arklores/core/agent/tools/tool_registry.dart';
import 'package:arklores/core/llm/llm_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  String answerOf(List<ReActEvent> events) => events
      .where((e) => e.type == ReActEventType.finalAnswerToken)
      .map((e) => e.content)
      .join();

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

    test('parses COLLECT terms (and the pre-R13 claim_terms spelling)', () {
      final intent = parseIntent('COLLECT speaker:博士 terms=[王冠,誓言]');
      expect(intent!.action, 'COLLECT');
      expect(intent.args['entity_id'], 'speaker:博士');
      expect(intent.args['terms'], ['王冠', '誓言']);

      final legacy = parseIntent('COLLECT speaker:博士 claim_terms=[王冠]');
      expect(legacy!.args['terms'], ['王冠']);
      expect(legacy.args.containsKey('claim_terms'), isFalse);
    });

    test('ANSWER takes an optional confidence; VERDICT is an alias', () {
      final bare = parseIntent('ANSWER');
      expect(bare!.action, 'ANSWER');
      expect(bare.args.containsKey('confidence'), isFalse);
      expect(parseIntent('ANSWER 0.8')!.args['confidence'], '0.8');

      final legacy = parseIntent('VERDICT char_b 0.8 multi_hypothesis_contrast');
      expect(legacy!.action, 'ANSWER');
      expect(legacy.args['confidence'], '0.8');
      expect(legacy.args.keys, ['confidence']);

      expect(parseIntent('DONE')!.action, 'DONE');
      expect(parseIntent('MAP activity:act33side')!.args['scope_id'],
          'activity:act33side',);
    });

    test('SEARCH strips surrounding quotes from the query', () {
      final quoted = parseIntent('SEARCH "特蕾西娅" 10');
      expect(quoted!.action, 'SEARCH');
      expect(quoted.args['query'], '特蕾西娅');
      expect(quoted.args['top_k'], 10);

      final single = parseIntent("SEARCH '博士' 5");
      expect(single!.args['query'], '博士');
    });

    test('SEARCH supports id= entity syntax and multi-word queries', () {
      final byId = parseIntent('SEARCH id=enemy:enemy_1554_lrtsia 10');
      expect(byId!.args['entity_id'], 'enemy:enemy_1554_lrtsia');
      expect(byId.args['top_k'], 10);

      final compound =
          parseIntent('SEARCH 特蕾西娅 王冠 id=enemy:enemy_1554_lrtsia top_k=20');
      expect(compound!.args['query'], '特蕾西娅 王冠');
      expect(compound.args['entity_id'], 'enemy:enemy_1554_lrtsia');
      expect(compound.args['top_k'], 20);

      final phrase = parseIntent('SEARCH "特蕾西娅 王冠" 10');
      expect(phrase!.args['query'], '特蕾西娅 王冠');
    });

    test('FIND keeps large numbers (years) in the query', () {
      final year = parseIntent('FIND 罗德岛 庆典 2030');
      expect(year!.args['query'], '罗德岛 庆典 2030');
      expect(year.args.containsKey('top_k'), isFalse);
      expect(parseIntent('FIND 罗德岛 庆典 8')!.args['top_k'], 8);
    });

    test('RESELECT parses entity_id', () {
      final reselect = parseIntent('RESELECT enemy:enemy_3006_tersia');
      expect(reselect!.action, 'RESELECT');
      expect(reselect.args['entity_id'], 'enemy:enemy_3006_tersia');
    });

    test('multi-intent and non-intent lines are rejected', () {
      expect(parseIntent('SEARCH 特蕾西娅 10\nSEARCH 特蕾西娅 王冠 10'), isNull);
      expect(parseIntent('READ a.txt 1 10\nMAP b'), isNull);
      expect(parseIntent('READ a.txt 1 10\nANSWER'), isNull);
      expect(parseIntent('随便说点什么'), isNull);
      expect(parseIntent(''), isNull);
      expect(parseIntent('Thought: 思考'), isNull);
    });
  });

  group('InvestigationState', () {
    test('serializes reads, notes, evidence, mapped', () {
      final state = InvestigationState();
      state.noteRead('activities/x/level_x_09_beg.txt', 0, 103);
      state.addNotes(const [
        EvidenceNote(
          storyId: 'activities/x/level_x_09_beg.txt',
          line: 42,
          fact: '信使送来了王冠',
          quote: '信使：这是给您的王冠。',
        ),
      ]);
      state.noteEvidence('speaker:博士', evidenceRows: 14, scopes: ['obt:main']);
      state.noteMapped('activity:act33side');

      final text = state.serialize();
      expect(text, contains('09_beg.txt:0-103'));
      expect(text, contains('09_beg.txt:42 信使送来了王冠 「信使：这是给您的王冠。」'));
      expect(text, contains('speaker:博士: 14行'));
      expect(text, contains('act33side'));
    });

    test('read merges adjacent ranges but keeps gaps unread (R12)', () {
      final state = InvestigationState();
      state.noteRead('s1', 0, 99);
      state.noteRead('s1', 100, 200);
      state.noteRead('s1', 300, 320);
      expect(state.serialize(), contains('s1:0-200,300-320'));
      expect(state.wasLineRead('s1', 150), isTrue);
      expect(state.wasLineRead('s1', 250), isFalse);
      expect(state.wasLineRead('s2', 0), isFalse);
    });
  });

  group('PlannerLoop execution', () {
    test('READ -> ANSWER finishes answered with bounded requests', () async {
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
            userQuery: '某角色最后怎么样了',
          )
          .toList();

      // The scripted VERDICT line is read as the ANSWER alias; status is
      // decided by code, never by the model.
      expect(
        answerOf(events),
        startsWith('[STORY_ANSWER: status=answered | confidence=0.8]'),
      );
      expect(answerOf(events), isNot(contains('char_b |')));
      // Request context stays tiny: state + recent observation only.
      expect(mock.receivedRequests.length, greaterThan(1));
      for (final request in mock.receivedRequests) {
        expect(request.length, lessThan(8));
      }
    });

    test('DONE without ANSWER still produces an answer', () async {
      final loop = PlannerLoop(
        llmClient: _ReadThenDoneLLM(),
        toolRegistry: ToolRegistry()..register(_ReadTool()),
        minimumToolCalls: 1,
      );
      final events = await loop
          .run(systemPrompt: 's', chatHistory: [], userQuery: 'q')
          .toList();
      expect(answerOf(events), contains('status=answered'));
    });

    test('invalid intents are retried, then terminate', () async {
      final loop = PlannerLoop(
        llmClient: _AlwaysInvalidIntentLLM(),
        toolRegistry: ToolRegistry()..register(_ReadTool()),
      );
      final events = await loop
          .run(systemPrompt: 's', chatHistory: [], userQuery: 'q')
          .toList();
      expect(
        events.any((e) =>
            e.type == ReActEventType.error && e.content.contains('无效意图'),),
        isTrue,
      );
    });

    test('network errors (incl. HandshakeException) are retried', () async {
      for (final mock in <_CountingLLM>[_NetworkOnceLLM(), _HandshakeOnceLLM()]) {
        final loop = PlannerLoop(
          llmClient: mock,
          toolRegistry: ToolRegistry()..register(_ReadTool()),
          minimumToolCalls: 1,
        );
        final events = await loop
            .run(systemPrompt: 's', chatHistory: [], userQuery: 'q')
            .toList();
        expect(answerOf(events), contains('STORY_ANSWER'));
        expect(mock.receivedRequests.length, greaterThan(1));
      }
    });

    test('ambiguous SEARCH auto-resolves the top candidate into state',
        () async {
      final loop = PlannerLoop(
        llmClient: _AmbiguousThenResolveLLM(),
        toolRegistry: ToolRegistry()
          ..register(_AmbiguousSearchTool())
          ..register(_CollectTool()),
        minimumToolCalls: 1,
      );
      final states = <String>[];
      await loop
          .run(
            systemPrompt: 's',
            chatHistory: [],
            userQuery: '特蕾西娅做过什么',
            onStateChanged: states.add,
          )
          .toList();
      expect(
        states.any((s) => s.contains('目标实体: enemy:enemy_1554_lrtsia')),
        isTrue,
      );
    });

    test('disambiguation helper picks candidate #2 (not blindly #1)',
        () async {
      final loop = PlannerLoop(
        llmClient: _AmbiguousThenResolveLLM(),
        toolRegistry: ToolRegistry()
          ..register(_AmbiguousSearchTool())
          ..register(_CollectTool()),
        disambiguator: EntityDisambiguator(llmClient: _PickSecondDisambiguator()),
        minimumToolCalls: 1,
      );
      final states = <String>[];
      await loop
          .run(
            systemPrompt: 's',
            chatHistory: [],
            userQuery: '特蕾西娅做过什么',
            onStateChanged: states.add,
          )
          .toList();
      expect(
        states.any((s) => s.contains('目标实体: enemy:enemy_3006_tersia')),
        isTrue,
      );
    });

    test('disambiguation helper failure falls back to top candidate',
        () async {
      final loop = PlannerLoop(
        llmClient: _AmbiguousThenResolveLLM(),
        toolRegistry: ToolRegistry()
          ..register(_AmbiguousSearchTool())
          ..register(_CollectTool()),
        disambiguator: EntityDisambiguator(llmClient: _FailDisambiguator()),
        minimumToolCalls: 1,
      );
      final states = <String>[];
      await loop
          .run(
            systemPrompt: 's',
            chatHistory: [],
            userQuery: '特蕾西娅做过什么',
            onStateChanged: states.add,
          )
          .toList();
      expect(
        states.any((s) => s.contains('目标实体: enemy:enemy_1554_lrtsia')),
        isTrue,
      );
    });

    test('SEARCH of an already-disambiguated name injects entity_id, and a '
        'repeat of that exact search is not re-run', () async {
      final search = _AmbiguousSearchTool();
      final loop = PlannerLoop(
        llmClient: _RepeatNameLLM(),
        toolRegistry: ToolRegistry()..register(search),
        disambiguator: EntityDisambiguator(llmClient: _PickSecondDisambiguator()),
        minimumToolCalls: 1,
      );
      final observations = <String>[];
      final events = await loop
          .run(systemPrompt: 's', chatHistory: [], userQuery: '特蕾西娅做过什么')
          .toList();
      for (final e in events) {
        if (e.type == ReActEventType.toolObservation) observations.add(e.content);
      }
      expect(observations[1], contains('特蕾西娅档案内容'));
      expect(observations[1], isNot(contains('Ambiguous')));
      expect(observations[2], contains('已执行过'));
      expect(search.calls, 2);
    });

    test('RESELECT switches to an untried candidate and refuses retried ones',
        () async {
      final loop = PlannerLoop(
        llmClient: _ReselectLLM(),
        toolRegistry: ToolRegistry()..register(_AmbiguousSearchTool()),
        disambiguator: EntityDisambiguator(llmClient: _PickSecondDisambiguator()),
        minimumToolCalls: 1,
      );
      final states = <String>[];
      await loop
          .run(
            systemPrompt: 's',
            chatHistory: [],
            userQuery: '特蕾西娅做过什么',
            onStateChanged: states.add,
          )
          .toList();
      expect(states.last, contains('目标实体: trap_762_skztxy'));
    });

    test('identical searches run once; a run that only repeats itself ends '
        'not_covered through the duplicate guard', () async {
      final search = _HitSearchTool();
      final mock = _AlwaysSearchNoResultLLM();
      final loop = PlannerLoop(
        llmClient: mock,
        toolRegistry: ToolRegistry()..register(search),
        minimumToolCalls: 1,
        safetyMaxIterations: 30,
      );
      final events = await loop
          .run(systemPrompt: 's', chatHistory: [], userQuery: '虚构的人做了什么')
          .toList();
      expect(search.calls, 1);
      expect(answerOf(events), startsWith('[STORY_ANSWER: status=not_covered'));
      expect(events.any((e) => e.type == ReActEventType.complete), isTrue);
      // 1 search + 3 blocked repeats (R14 duplicate guard) + the writer.
      expect(mock.callCount, lessThanOrEqualTo(6));
    });

    test('semantic-only FIND hits are not progress, so re-phrased searches '
        'stall out', () async {
      final mock = _RephrasedFindLLM();
      final loop = PlannerLoop(
        llmClient: mock,
        toolRegistry: ToolRegistry()..register(_SemanticOnlyFindTool()),
        minimumToolCalls: 1,
        safetyMaxIterations: 40,
      );
      final events = await loop
          .run(systemPrompt: 's', chatHistory: [], userQuery: 'q')
          .toList();
      expect(answerOf(events), startsWith('[STORY_ANSWER: status=not_covered'));
      // 1 step + 8 stalled steps (+ the writer call), well under the
      // 24-step budget that the live negative case used to exhaust.
      expect(mock.callCount, lessThanOrEqualTo(11));
    });

    test('a stalled run that read something ends partial via the writer',
        () async {
      final loop = PlannerLoop(
        llmClient: _ReadThenSearchLLM(),
        toolRegistry: ToolRegistry()
          ..register(_HitSearchTool())
          ..register(_ReadTool()),
        minimumToolCalls: 1,
        safetyMaxIterations: 30,
      );
      final events = await loop
          .run(systemPrompt: 's', chatHistory: [], userQuery: 'q')
          .toList();
      expect(answerOf(events), startsWith('[STORY_ANSWER: status=partial'));
    });

    test('empty responses finish from state, not an invalid-intent error',
        () async {
      final loop = PlannerLoop(
        llmClient: _EmptyResponseLLM(),
        toolRegistry: ToolRegistry()..register(_HitSearchTool()),
        minimumToolCalls: 1,
        safetyMaxIterations: 30,
      );
      final events = await loop
          .run(systemPrompt: 's', chatHistory: [], userQuery: 'q')
          .toList();
      expect(answerOf(events), contains('status=not_covered'));
      expect(
        events.any((e) =>
            e.type == ReActEventType.error && e.content.contains('无效意图'),),
        isFalse,
      );
    });
  });

  group('answer styles (R13)', () {
    Future<(String, _RecordingWriter)> runStyle(
      AnswerStyle style,
      String writerReply, {
      bool read = true,
    }) async {
      final writer = _RecordingWriter(writerReply);
      final loop = PlannerLoop(
        llmClient: read ? _ReadThenDoneLLM() : _SearchThenAnswerLLM(),
        writerClient: writer,
        toolRegistry: ToolRegistry()
          ..register(_ReadTool())
          ..register(_HitSearchTool()),
        minimumToolCalls: 1,
      );
      final events = await loop
          .run(systemPrompt: 's', chatHistory: [], userQuery: 'q', style: style)
          .toList();
      return (answerOf(events), writer);
    }

    test('style only changes the writer format, not the envelope', () async {
      final (answer, writer) = await runStyle(AnswerStyle.answer, '回答 s.txt:0');
      expect(writer.system, contains('开头一行直接回答问题'));
      expect(answer, startsWith('[STORY_ANSWER: status=answered'));

      final (summary, summaryWriter) =
          await runStyle(AnswerStyle.summary, '梗概 s.txt:0');
      expect(summaryWriter.system, contains('梗概'));
      expect(summary, startsWith('[STORY_ANSWER: status=answered'));
    });

    test('fact check keeps a cited definite verdict', () async {
      final (answer, writer) = await runStyle(
        AnswerStyle.factCheck,
        '[FACT_CHECK_VERDICT:supported]\n原文 s.txt:0 支持。',
      );
      expect(writer.system, contains('FACT_CHECK_VERDICT'));
      expect(answer, contains('[FACT_CHECK_VERDICT:supported]'));
    });

    test('fact check downgrades an uncited or unread-backed verdict',
        () async {
      final (uncited, _) = await runStyle(
        AnswerStyle.factCheck,
        '[FACT_CHECK_VERDICT:refuted]\n没有引用。',
      );
      expect(uncited, contains('[FACT_CHECK_VERDICT:uncertain]'));

      final (nothingRead, _) = await runStyle(
        AnswerStyle.factCheck,
        '[FACT_CHECK_VERDICT:supported]\n凭记忆。',
        read: false,
      );
      expect(nothingRead, contains('status=not_covered'));
      expect(nothingRead, contains('[FACT_CHECK_VERDICT:unavailable]'));
    });

    test('normalizeFactCheckBody rules', () {
      expect(
        normalizeFactCheckBody('无标记', nothingRead: false, hasValidCitation: true),
        startsWith('[FACT_CHECK_VERDICT:uncertain]'),
      );
      expect(
        normalizeFactCheckBody(
          '[FACT_CHECK_VERDICT:uncertain]\nx',
          nothingRead: true,
          hasValidCitation: false,
        ),
        startsWith('[FACT_CHECK_VERDICT:unavailable]'),
      );
    });
  });
}

/// Common shape of the scripted LLMs that record their requests.
abstract class _CountingLLM extends LLMClient {
  List<List<Message>> get receivedRequests;
}

/// Scripted planner: READ once, then DONE (no ANSWER line).
class _ReadThenDoneLLM extends LLMClient {
  int callCount = 0;

  @override
  Future<String> chat(
    List<Message> messages, {
    List<Map<String, dynamic>>? tools,
    double temperature = 0.7,
    int maxTokens = 2048,
    List<String>? stop,
  }) async {
    callCount++;
    return callCount == 1 ? 'READ s 0 100' : 'DONE';
  }

  @override
  Future<String> chatStream(
    List<Message> messages, {
    void Function(String token)? onToken,
    double temperature = 0.7,
    int maxTokens = 2048,
    List<String>? stop,
  }) async =>
      chat(messages, temperature: temperature, maxTokens: maxTokens, stop: stop);
}

/// Scripted planner: one SEARCH (nothing read), then ANSWER.
class _SearchThenAnswerLLM extends LLMClient {
  int callCount = 0;

  @override
  Future<String> chat(
    List<Message> messages, {
    List<Map<String, dynamic>>? tools,
    double temperature = 0.7,
    int maxTokens = 2048,
    List<String>? stop,
  }) async {
    callCount++;
    return callCount == 1 ? 'SEARCH 无此人 5' : 'ANSWER 0.9';
  }

  @override
  Future<String> chatStream(
    List<Message> messages, {
    void Function(String token)? onToken,
    double temperature = 0.7,
    int maxTokens = 2048,
    List<String>? stop,
  }) async =>
      chat(messages, temperature: temperature, maxTokens: maxTokens, stop: stop);
}

/// Writer that records its system prompt and returns a fixed reply.
class _RecordingWriter extends LLMClient {
  _RecordingWriter(this.reply);
  final String reply;
  String system = '';

  @override
  Future<String> chat(
    List<Message> messages, {
    List<Map<String, dynamic>>? tools,
    double temperature = 0.7,
    int maxTokens = 2048,
    List<String>? stop,
  }) async {
    system = messages.first.content;
    return reply;
  }

  @override
  Future<String> chatStream(
    List<Message> messages, {
    void Function(String token)? onToken,
    double temperature = 0.7,
    int maxTokens = 2048,
    List<String>? stop,
  }) async =>
      chat(messages, temperature: temperature, maxTokens: maxTokens, stop: stop);
}


/// Scripted planner LLM: READ once, then VERDICT, then DONE.
class _PlannerScriptLLM extends _CountingLLM {
  int callCount = 0;
  @override
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
class _NetworkOnceLLM extends _CountingLLM {
  int callCount = 0;
  @override
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

/// First call throws a TLS HandshakeException (flaky provider), then works.
/// First SEARCH returns an ambiguous-candidate observation; the executor
/// auto-picks the top candidate (disambiguator) into state, then the loop
/// proceeds.
class _AmbiguousThenResolveLLM extends LLMClient {
  int callCount = 0;

  @override
  Future<String> chat(
    List<Message> messages, {
    List<Map<String, dynamic>>? tools,
    double temperature = 0.7,
    int maxTokens = 2048,
    List<String>? stop,
  }) async {
    callCount++;
    switch (callCount) {
      case 1:
        return 'SEARCH 特蕾西娅 5';
      case 2:
        return 'COLLECT enemy:enemy_1554_lrtsia claim_terms=[杀,死亡]';
      case 3:
        return 'VERDICT enemy:enemy_1554_lrtsia 0.7 multi_hypothesis_contrast';
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

/// Script: SEARCH 特蕾西娅 repeatedly (for dead-loop tests); always the same
/// ambiguous name so the repeat guard counts up.
class _RepeatNameLLM extends LLMClient {
  int callCount = 0;

  @override
  Future<String> chat(
    List<Message> messages, {
    List<Map<String, dynamic>>? tools,
    double temperature = 0.7,
    int maxTokens = 2048,
    List<String>? stop,
  }) async {
    callCount++;
    return 'SEARCH 特蕾西娅 5';
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

/// Script: SEARCH (ambiguous) -> RESELECT #1 (refused) -> RESELECT #3
/// (accepted) -> VERDICT.
class _ReselectLLM extends LLMClient {
  int callCount = 0;

  @override
  Future<String> chat(
    List<Message> messages, {
    List<Map<String, dynamic>>? tools,
    double temperature = 0.7,
    int maxTokens = 2048,
    List<String>? stop,
  }) async {
    callCount++;
    switch (callCount) {
      case 1:
        return 'SEARCH 特蕾西娅 5';
      case 2:
        return 'RESELECT enemy:enemy_1554_lrtsia';
      case 3:
        return 'RESELECT trap_762_skztxy';
      case 4:
        return 'VERDICT trap_762_skztxy 0.6 multi_hypothesis_contrast';
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

/// collect_entity_evidence-shaped tool returning an evidence DATA block.
class _CollectTool extends AgentTool {
  @override
  String get name => 'collect_entity_evidence';

  @override
  String get description => 'Collects evidence.';

  @override
  Map<String, dynamic> get parameters => {
        'type': 'object',
        'properties': {
          'entity_id': {'type': 'string'},
          'terms': {'type': 'array', 'items': {'type': 'string'}},
        },
        'required': ['entity_id'],
      };

  @override
  Future<dynamic> execute(Map<String, dynamic> arguments) async {
    return const ToolExecutionResult(
      observation:
          'Entity: x | Total appearance runs: 5\nEnd of Evidence: yes\n'
          'DATA: {"type":"collect_entity_evidence","entity_id":"x",'
          '"evidence_rows":4,"scopes":["obt:main"],"total_runs":5,'
          '"next_page_token":null}',
    );
  }
}

/// search_local_lore-shaped tool that returns an ambiguous observation.
class _AmbiguousSearchTool extends AgentTool {
  int calls = 0;

  @override
  String get name => 'search_local_lore';

  @override
  String get description => 'Searches lore.';

  @override
  Map<String, dynamic> get parameters => {
        'type': 'object',
        'properties': {
          'query': {'type': 'string'},
          'top_k': {'type': 'integer'},
          'entity_id': {'type': 'string'},
        },
        'required': ['query'],
      };

  @override
  Future<dynamic> execute(Map<String, dynamic> arguments) async {
    calls++;
    final entityId = arguments['entity_id'] as String?;
    if (entityId != null && entityId.trim().isNotEmpty) {
      return ToolExecutionResult(
        observation:
            '=== Result #1 (Score: 5000.0000) ===\n'
            'Entity ID: $entityId\n'
            'Title: 特蕾西娅\n'
            'Content Excerpt:\n特蕾西娅档案内容\n',
      );
    }
    return const ToolExecutionResult(
      observation: 'Ambiguous GameData entity query: "特蕾西娅".\n'
          '候选实体（请用 Entity ID 消歧）:\n'
          '  1. enemy:enemy_1554_lrtsia | 特蕾西娅 | enemy | enemy_profile | name_exact | 1.00\n'
          '  2. enemy:enemy_3006_tersia | 特蕾西娅，"魔王" | enemy | enemy_profile | alias_exact | 0.80\n'
          '  3. trap_762_skztxy | 特蕾西娅，黑冠圣贤 | operator | operator_profile | alias_exact | 0.80',
    );
  }
}


/// Scripted disambiguator helper that always picks candidate #2.
class _PickSecondDisambiguator extends LLMClient {
  int calls = 0;

  @override
  Future<String> chat(
    List<Message> messages, {
    List<Map<String, dynamic>>? tools,
    double temperature = 0.7,
    int maxTokens = 2048,
    List<String>? stop,
  }) async {
    calls++;
    return '2';
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

/// Disambiguator helper that fails (garbage output) -> executor falls back
/// to candidate #1.
class _FailDisambiguator extends LLMClient {
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

class _HandshakeOnceLLM extends _CountingLLM {
  int callCount = 0;
  @override
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
      throw const LLMException(
        'HandshakeException: Connection terminated during handshake',
      );
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
      observation: 'Story: s.txt\n0 | 角色A | 台词\nRead Lines: 100',
    );
  }
}


/// Scripts: READ once (giving non-search progress), then repeatedly SEARCH a
/// name that returns no result — the executor must GUIDE (not terminate).
class _ReadThenSearchLLM extends LLMClient {
  int callCount = 0;

  @override
  Future<String> chat(
    List<Message> messages, {
    List<Map<String, dynamic>>? tools,
    double temperature = 0.7,
    int maxTokens = 2048,
    List<String>? stop,
  }) async {
    callCount++;
    if (callCount <= 2) return 'READ activities/x/level_x.txt 0 100';
    return 'SEARCH 无此人 5';
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

/// search_local_lore-shaped tool that returns a direct entity hit.
class _HitSearchTool extends AgentTool {
  int calls = 0;

  @override
  String get name => 'search_local_lore';

  @override
  String get description => 'Searches lore.';

  @override
  Map<String, dynamic> get parameters => {
        'type': 'object',
        'properties': {
          'query': {'type': 'string'},
          'entity_id': {'type': 'string'},
          'top_k': {'type': 'integer'},
        },
        'required': ['query'],
      };

  @override
  Future<dynamic> execute(Map<String, dynamic> arguments) async {
    calls++;
    final entityId = arguments['entity_id'] as String?;
    if (entityId != null && entityId.trim().isNotEmpty) {
      return const ToolExecutionResult(
        observation: '=== Result #1 ===\n'
            'Entity ID: hit | Title: x | Content Excerpt:\n档案\n',
      );
    }
    return const ToolExecutionResult(
      observation:
          'No matching GameData result found for "无此人". The local GameData '
          'knowledge DB is installed, but structured/FTS search returned no '
          'result.',
    );
  }
}

/// Scripts: always SEARCH a name with no result (no READ/evidence) — used for
/// the "no progress at all -> unresolved" test.
class _AlwaysSearchNoResultLLM extends LLMClient {
  int callCount = 0;

  @override
  Future<String> chat(
    List<Message> messages, {
    List<Map<String, dynamic>>? tools,
    double temperature = 0.7,
    int maxTokens = 2048,
    List<String>? stop,
  }) async {
    callCount++;
    return 'SEARCH 无此人 5';
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


/// Scripts: emits empty responses repeatedly (like a model that has nothing
/// to say after identical observations). The loop must wind down gently to
/// unresolved, not a hard "invalid intent" error.
class _EmptyResponseLLM extends LLMClient {
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
    return chat(
      messages,
      temperature: temperature,
      maxTokens: maxTokens,
      stop: stop,
    );
  }
}

/// Re-phrases a fruitless FIND every step (fresh signature each time).
class _RephrasedFindLLM extends LLMClient {
  int callCount = 0;

  @override
  Future<String> chat(
    List<Message> messages, {
    List<Map<String, dynamic>>? tools,
    double temperature = 0.7,
    int maxTokens = 2048,
    List<String>? stop,
  }) async {
    callCount++;
    return 'FIND 无此事 变体$callCount';
  }

  @override
  Future<String> chatStream(
    List<Message> messages, {
    void Function(String token)? onToken,
    double temperature = 0.7,
    int maxTokens = 2048,
    List<String>? stop,
  }) async =>
      chat(messages, temperature: temperature, maxTokens: maxTokens, stop: stop);
}

/// search_story_lines-shaped tool: every call returns DIFFERENT stories,
/// all marked as semantic-only neighbours (no literal hit).
class _SemanticOnlyFindTool extends AgentTool {
  int calls = 0;

  @override
  String get name => 'search_story_lines';

  @override
  String get description => 'Finds story lines.';

  @override
  Map<String, dynamic> get parameters => {
        'type': 'object',
        'properties': {
          'query': {'type': 'string'},
        },
        'required': ['query'],
      };

  @override
  Future<dynamic> execute(Map<String, dynamic> arguments) async {
    calls++;
    return ToolExecutionResult(
      observation: 'Story line hits:\n'
          'Story: s$calls.txt | Scope: x | 无字面命中（仅语义相近）\n'
          '  Lines 0-11 (semantic 0.5)',
    );
  }
}
