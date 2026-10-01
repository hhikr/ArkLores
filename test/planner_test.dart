import 'package:arklores/core/agent/entity_disambiguator.dart';
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

    test('SEARCH strips surrounding quotes from the query', () {
      final quoted = parseIntent('SEARCH "特蕾西娅" 10');
      expect(quoted!.action, 'SEARCH');
      expect(quoted.args['query'], '特蕾西娅');
      expect(quoted.args['top_k'], 10);

      final single = parseIntent("SEARCH '博士' 5");
      expect(single!.args['query'], '博士');
    });

    test('SEARCH keeps quoted multi-word phrases intact', () {
      final phrase = parseIntent('SEARCH "特蕾西娅 死亡" 10');
      expect(phrase!.action, 'SEARCH');
      expect(phrase.args['query'], '特蕾西娅 死亡');
      expect(phrase.args['top_k'], 10);
    });

    test('SEARCH supports id= entity syntax', () {
      final byId = parseIntent('SEARCH id=enemy:enemy_1554_lrtsia 10');
      expect(byId!.action, 'SEARCH');
      expect(byId.args['entity_id'], 'enemy:enemy_1554_lrtsia');
      expect(byId.args['top_k'], 10);

      final named = parseIntent('SEARCH 特蕾西娅 id=enemy:enemy_3006_tersia 5');
      expect(named!.args['query'], '特蕾西娅');
      expect(named.args['entity_id'], 'enemy:enemy_3006_tersia');
    });

    test('RESELECT parses entity_id', () {
      final reselect = parseIntent('RESELECT enemy:enemy_3006_tersia');
      expect(reselect!.action, 'RESELECT');
      expect(reselect.args['entity_id'], 'enemy:enemy_3006_tersia');
    });

    test('multi-intent lines are rejected, not silently truncated', () {
      expect(
        parseIntent('SEARCH 特蕾西娅 10\nSEARCH 特蕾西娅 死亡 10'),
        isNull,
      );
      expect(parseIntent('READ a.txt 1 10\nMAP b'), isNull);
    });

    test('SEARCH merges unquoted multi-word queries (R11.2)', () {
      final compound =
          parseIntent('SEARCH 特蕾西娅 死亡 id=enemy:enemy_1554_lrtsia top_k=20');
      expect(compound!.action, 'SEARCH');
      expect(compound.args['query'], '特蕾西娅 死亡');
      expect(compound.args['entity_id'], 'enemy:enemy_1554_lrtsia');
      expect(compound.args['top_k'], 20);

      final naked = parseIntent('SEARCH 特蕾西娅 5');
      expect(naked!.args['query'], '特蕾西娅');
      expect(naked.args['top_k'], 5);

      final phrase = parseIntent('SEARCH "特蕾西娅 死亡" 10');
      expect(phrase!.args['query'], '特蕾西娅 死亡');
      expect(phrase.args['top_k'], 10);
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

    test('HandshakeException is treated as a retryable network error',
        () async {
      final mock = _HandshakeOnceLLM();
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
      expect(mock.receivedRequests.length, greaterThan(1));
    });

    test('ambiguous SEARCH auto-resolves the top candidate into state',
        () async {
      final mock = _AmbiguousThenResolveLLM();
      final loop = PlannerLoop(
        llmClient: mock,
        toolRegistry: ToolRegistry()
          ..register(_AmbiguousSearchTool())
          ..register(_CollectTool()),
        minimumToolCalls: 1,
      );
      final states = <String>[];
      await loop
          .run(
            systemPrompt: 'You are a helper.',
            chatHistory: [],
            userQuery: '特蕾西娅之死',
            onStateChanged: states.add,
          )
          .toList();

      // State now carries the auto-resolved target entity.
      expect(
        states.any((s) => s.contains('目标实体: enemy:enemy_1554_lrtsia')),
        isTrue,
      );
    });

    test('disambiguation helper picks candidate #2 (not blindly #1)',
        () async {
      final mock = _AmbiguousThenResolveLLM();
      final loop = PlannerLoop(
        llmClient: mock,
        toolRegistry: ToolRegistry()
          ..register(_AmbiguousSearchTool())
          ..register(_CollectTool()),
        disambiguator: EntityDisambiguator(llmClient: _PickSecondDisambiguator()),
        minimumToolCalls: 1,
      );
      final states = <String>[];
      await loop
          .run(
            systemPrompt: 'You are a helper.',
            chatHistory: [],
            userQuery: '导致特蕾西娅死亡的罪魁祸首是谁',
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
      final mock = _AmbiguousThenResolveLLM();
      final loop = PlannerLoop(
        llmClient: mock,
        toolRegistry: ToolRegistry()
          ..register(_AmbiguousSearchTool())
          ..register(_CollectTool()),
        disambiguator: EntityDisambiguator(llmClient: _FailDisambiguator()),
        minimumToolCalls: 1,
      );
      final states = <String>[];
      await loop
          .run(
            systemPrompt: 'You are a helper.',
            chatHistory: [],
            userQuery: '特蕾西娅之死',
            onStateChanged: states.add,
          )
          .toList();

      expect(
        states.any((s) => s.contains('目标实体: enemy:enemy_1554_lrtsia')),
        isTrue,
      );
    });

    test('SEARCH of an already-disambiguated name injects entity_id',
        () async {
      // Script: SEARCH 特蕾西娅 (ambiguous -> resolved to #2), then SEARCH
      // 特蕾西娅 again — the executor must inject entity_id into the second
      // call so the tool returns a direct hit instead of the ambiguity branch.
      final search = _AmbiguousSearchTool();
      final mock = _RepeatNameLLM();
      final loop = PlannerLoop(
        llmClient: mock,
        toolRegistry: ToolRegistry()
          ..register(search)
          ..register(_CollectTool()),
        disambiguator: EntityDisambiguator(llmClient: _PickSecondDisambiguator()),
        minimumToolCalls: 1,
      );
      final observations = <String>[];
      await loop
          .run(
            systemPrompt: 'You are a helper.',
            chatHistory: [],
            userQuery: '特蕾西娅之死',
          )
          .forEach((e) {
        if (e.type == ReActEventType.toolObservation) {
          observations.add(e.content);
        }
      });

      // Second SEARCH went straight to an entity-id hit (not "Ambiguous").
      final second = observations.length >= 2 ? observations[1] : '';
      expect(second, contains('特蕾西娅档案内容'));
      expect(second, isNot(contains('Ambiguous')));
    });

    test('RESELECT switches to an untried candidate and refuses retried ones',
        () async {
      final search = _AmbiguousSearchTool();
      final mock = _ReselectLLM();
      final loop = PlannerLoop(
        llmClient: mock,
        toolRegistry: ToolRegistry()..register(search),
        disambiguator: EntityDisambiguator(llmClient: _PickSecondDisambiguator()),
        minimumToolCalls: 1,
      );
      final states = <String>[];
      await loop
          .run(
            systemPrompt: 'You are a helper.',
            chatHistory: [],
            userQuery: '特蕾西娅之死',
            onStateChanged: states.add,
          )
          .toList();

      // After disambiguation picked #2, RESELECT re-picks #1 -> should be
      // refused (attempted), then RESELECT #3 -> accepted.
      final last = states.last;
      expect(last, contains('目标实体: trap_762_skztxy'));
    });

    test('repeated SEARCH with identical results is counted as no-progress '
        '(R11.2)', () async {
      // Script: SEARCH id=... five times; tool returns the SAME hit every
      // time. R11.2 treats "has result but identical content" as a repeat:
      // the executor must eventually fall back to coverage instead of
      // looping forever on the same data.
      final search = _HitSearchTool();
      final coverage = _CoverageTool();
      final mock = _ResultRepeatedLLM();
      final loop = PlannerLoop(
        llmClient: mock,
        toolRegistry: ToolRegistry()
          ..register(search)
          ..register(coverage),
        minimumToolCalls: 1,
        safetyMaxIterations: 20,
      );
      await loop
          .run(
            systemPrompt: 'You are a helper.',
            chatHistory: [],
            userQuery: '调查某角色',
          )
          .toList();

      // Identical-content repeats accumulate -> coverage fallback fires.
      expect(coverage.calls, greaterThanOrEqualTo(1));
    });

    test('no-progress SEARCH with read progress guides instead of terminating '
        '(R11.1)', () async {
      // READ (progress) then repeated no-result SEARCH. The executor must
      // inject a guidance observation (COLLECT/VERDICT) instead of an
      // unresolved verdict.
      final search = _HitSearchTool();
      final read = _ReadTool();
      final mock = _ReadThenSearchLLM();
      final loop = PlannerLoop(
        llmClient: mock,
        toolRegistry: ToolRegistry()
          ..register(search)
          ..register(read),
        minimumToolCalls: 1,
        safetyMaxIterations: 30,
      );
      final observations = <String>[];
      await loop
          .run(
            systemPrompt: 'You are a helper.',
            chatHistory: [],
            userQuery: '调查某角色',
          )
          .forEach((e) {
        if (e.type == ReActEventType.toolObservation) {
          observations.add(e.content);
        }
      });

      final guided = observations.any((o) => o.contains('请停止重复搜索'));
      final unresolved = observations.any((o) =>
          o.contains('INVESTIGATION_VERDICT') && o.contains('unresolved'),);
      expect(guided, isTrue);
      expect(unresolved, isFalse);
    });

    test('no-progress SEARCH with NO progress terminates with unresolved '
        '(R11.1)', () async {
      // No READ / evidence; repeated no-result SEARCH -> unresolved.
      final search = _HitSearchTool();
      final mock = _AlwaysSearchNoResultLLM();
      final loop = PlannerLoop(
        llmClient: mock,
        toolRegistry: ToolRegistry()..register(search),
        minimumToolCalls: 1,
        safetyMaxIterations: 30,
      );
      final events = await loop
          .run(
            systemPrompt: 'You are a helper.',
            chatHistory: [],
            userQuery: '调查某角色',
          )
          .toList();

      final answer = events
          .where((e) => e.type == ReActEventType.finalAnswerToken)
          .map((e) => e.content)
          .join();
      expect(answer, contains('culprit=unresolved'));
      expect(events.any((e) => e.type == ReActEventType.complete), isTrue);
    });

    test('no-progress SEARCH without target guides (not terminates) (R11.1)',
        () async {
      // No READ/evidence; repeated no-result SEARCH; no entity resolved yet.
      // The executor must NOT emit unresolved — it guides (coverage fallback
      // or "target not disambiguated") and the loop continues.
      final search = _HitSearchTool();
      final coverage = _CoverageTool();
      final mock = _AlwaysSearchNoResultLLM();
      final loop = PlannerLoop(
        llmClient: mock,
        toolRegistry: ToolRegistry()
          ..register(search)
          ..register(coverage),
        minimumToolCalls: 1,
        safetyMaxIterations: 30,
      );
      final observations = <String>[];
      final events = await loop
          .run(
            systemPrompt: 'You are a helper.',
            chatHistory: [],
            userQuery: '调查某角色',
          )
          .toList();
      for (final e in events) {
        if (e.type == ReActEventType.toolObservation) {
          observations.add(e.content);
        }
      }

      // A guidance/coverage observation was injected instead of a terminal
      // unresolved verdict.
      expect(
        observations.any((o) =>
            o.contains('已自动转 search_story_coverage') ||
            o.contains('无法自动转枚举出场'),),
        isTrue,
      );
      final answer = events
          .where((e) => e.type == ReActEventType.finalAnswerToken)
          .map((e) => e.content)
          .join();
      expect(answer, isNot(contains('culprit=unresolved')));
    });

    test('RESELECT resets search counts for the new candidate (R11.1)',
        () async {
      // Script: SEARCH id=A no-result several times (accumulates), then
      // RESELECT B. The new candidate must NOT inherit A's counts — a fresh
      // SEARCH of B (no-result first) must not immediately terminate.
      final search = _HitSearchTool();
      final mock = _ReselectResetLLM();
      final loop = PlannerLoop(
        llmClient: mock,
        toolRegistry: ToolRegistry()
          ..register(search)
          ..register(_CollectTool()),
        minimumToolCalls: 1,
        safetyMaxIterations: 30,
      );
      final states = <String>[];
      await loop
          .run(
            systemPrompt: 'You are a helper.',
            chatHistory: [],
            userQuery: '调查某角色',
            onStateChanged: states.add,
          )
          .toList();

      // After RESELECT B, the observation for the first B search must be the
      // no-result hint, NOT an immediate "已切换候选" + unresolved or coverage
      // termination — i.e. B starts its own baseline.
      final last = states.last;
      expect(last, contains('目标实体: enemy:enemy_3006_tersia'));
    });

    test('empty responses wind down to unresolved, not invalid-intent error '
        '(R11.2)', () async {
      // Script: model always returns empty content. The loop must terminate
      // with a gentle unresolved verdict (not "模型连续输出无效意图" error) after
      // the empty-response cap.
      final search = _HitSearchTool();
      final mock = _EmptyResponseLLM();
      final loop = PlannerLoop(
        llmClient: mock,
        toolRegistry: ToolRegistry()..register(search),
        minimumToolCalls: 1,
        safetyMaxIterations: 30,
      );
      final events = await loop
          .run(
            systemPrompt: 'You are a helper.',
            chatHistory: [],
            userQuery: '调查某角色',
          )
          .toList();

      final answer = events
          .where((e) => e.type == ReActEventType.finalAnswerToken)
          .map((e) => e.content)
          .join();
      expect(answer, contains('culprit=unresolved'));
      expect(
        events.any((e) =>
            e.type == ReActEventType.error &&
            e.content.contains('无效意图'),),
        isFalse,
      );
    });

    test('changing search content resets counters, never terminates (R11.2)',
        () async {
      // READ (progress) then SEARCH returning CHANGING hits each time —
      // productive repeats must not trigger coverage/unresolved.
      final search = _FreshHitSearchTool();
      final read = _ReadTool();
      final coverage = _CoverageTool();
      final mock = _FreshContentSearchLLM();
      final loop = PlannerLoop(
        llmClient: mock,
        toolRegistry: ToolRegistry()
          ..register(search)
          ..register(read)
          ..register(coverage),
        minimumToolCalls: 1,
        safetyMaxIterations: 30,
      );
      await loop
          .run(
            systemPrompt: 'You are a helper.',
            chatHistory: [],
            userQuery: '调查某角色',
          )
          .toList();

      expect(coverage.calls, 0);
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

/// collect_suspect_evidence-shaped tool returning an evidence DATA block.
class _CollectTool extends AgentTool {
  @override
  String get name => 'collect_suspect_evidence';

  @override
  String get description => 'Collects evidence.';

  @override
  Map<String, dynamic> get parameters => {
        'type': 'object',
        'properties': {
          'entity_id': {'type': 'string'},
          'claim_terms': {'type': 'array', 'items': {'type': 'string'}},
        },
        'required': ['entity_id'],
      };

  @override
  Future<dynamic> execute(Map<String, dynamic> arguments) async {
    return const ToolExecutionResult(
      observation:
          'Suspect: x | Total appearance runs: 5\nEnd of Evidence: yes\n'
          'DATA: {"type":"collect_suspect_evidence","entity_id":"x",'
          '"evidence_rows":4,"scopes":["obt:main"],"total_runs":5,'
          '"next_page_token":null}',
    );
  }
}

/// search_local_lore-shaped tool that returns an ambiguous observation.
class _AmbiguousSearchTool extends AgentTool {
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

/// search_story_coverage-shaped tool: counts calls so tests can assert the
/// executor's automatic coverage fallback ran.
class _CoverageTool extends AgentTool {
  int calls = 0;

  @override
  String get name => 'search_story_coverage';

  @override
  String get description => 'Enumerates story appearances.';

  @override
  Map<String, dynamic> get parameters => {
        'type': 'object',
        'properties': {
          'entity_id': {'type': 'string'},
        },
        'required': ['entity_id'],
      };

  @override
  Future<dynamic> execute(Map<String, dynamic> arguments) async {
    calls++;
    return const ToolExecutionResult(
      observation:
          'Entity: x (x)\nScope: obt:main\n'
          'Story: activities/x/level_x.txt | Lines: 0-100 | Mentions: 5\n'
          'Coverage Scopes: 1\nCoverage Stories: 1',
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

class _HandshakeOnceLLM extends LLMClient {
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
      observation: 'Story: s\n0 | 角色A | 台词\nRead Lines: 100',
    );
  }
}

/// Scripts: repeated SEARCH with a RESULT (but identical content each time)
/// — must NOT be treated as a productive loop that resets, let alone
/// terminated, until no-progress repeats accumulate.
class _ResultRepeatedLLM extends LLMClient {
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
    // Always SEARCH with explicit resolver id -> tool returns a hit.
    return 'SEARCH id=enemy:enemy_1554_lrtsia 5';
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

/// Scripts: SEARCH A (no result) x2 -> RESELECT B -> SEARCH B (no result).
/// Asserts the executor keeps B on its own baseline instead of terminating
/// with A's accumulated counts.
class _ReselectResetLLM extends LLMClient {
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
      case 2:
        return 'SEARCH id=enemy:enemy_1554_lrtsia 5';
      case 3:
        return 'RESELECT enemy:enemy_3006_tersia';
      case 4:
        return 'SEARCH id=enemy:enemy_3006_tersia 5';
      case 5:
        return 'VERDICT enemy:enemy_3006_tersia 0.5 multi_hypothesis_contrast';
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

/// Scripts: READ once, then SEARCH where the tool returns CHANGING content
/// each call (fresh hit) — productive repeats must reset counters and never
/// trigger coverage/unresolved.
class _FreshContentSearchLLM extends LLMClient {
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
    return 'SEARCH id=enemy:enemy_1554_lrtsia 5';
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

/// search_local_lore-shaped tool that returns a hit whose content CHANGES on
/// every call (simulates genuinely new information per search).
class _FreshHitSearchTool extends AgentTool {
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
        },
        'required': ['query'],
      };

  @override
  Future<dynamic> execute(Map<String, dynamic> arguments) async {
    calls++;
    return ToolExecutionResult(
      observation: '=== Result #1 ===\nEntity ID: hit\nTitle: x\n'
          'Content Excerpt:\n新信息 #$calls\n',
    );
  }
}
