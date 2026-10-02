import 'package:arklores/core/agent/entity_disambiguator.dart';
import 'package:arklores/core/agent/evidence_notebook.dart';
import 'package:arklores/core/agent/investigation_state.dart';
import 'package:arklores/core/agent/planner_intent.dart';
import 'package:arklores/core/agent/planner_loop.dart';
import 'package:arklores/core/agent/react_event.dart';
import 'package:arklores/core/agent/tools/agent_tool.dart';
import 'package:arklores/core/agent/tools/observation_data.dart';
import 'package:arklores/core/agent/tools/tool_registry.dart';
import 'package:arklores/core/llm/llm_client.dart';
import 'package:flutter_test/flutter_test.dart';

/// R12 evidence-notebook tests. Fixture names are synthetic: every
/// assertion checks generic behavior (anchoring, citation checks, routing),
/// never special treatment of a specific entity.
void main() {
  group('parseIntent COVER / FIND (R12)', () {
    test('COVER takes a name or an entity id and an optional scope', () {
      final byName = parseIntent('COVER 角色B scope=activity:act_fixture')!;
      expect(byName.action, 'COVER');
      expect(byName.args['query'], '角色B');
      expect(byName.args['scope_filter'], 'activity:act_fixture');

      final byId = parseIntent('COVER char:char_b')!;
      expect(byId.args['entity_id'], 'char:char_b');
      expect(byId.args.containsKey('query'), isFalse);
    });

    test('FIND keeps a multi-word phrase, scope and top_k', () {
      final find = parseIntent('FIND 染血 匕首 scope=obt:main 4')!;
      expect(find.action, 'FIND');
      expect(find.args['query'], '染血 匕首');
      expect(find.args['scope_id'], 'obt:main');
      expect(find.args['top_k'], 4);

      expect(parseIntent('FIND "藏起 匕首"')!.args['query'], '藏起 匕首');
      expect(parseIntent('FIND'), isNull);
    });

    test('FIND drops repeated terms (degenerate repetition)', () {
      expect(parseIntent('FIND 某名 某名 某名')!.args['query'], '某名');
      expect(parseIntent('FIND 甲 乙 甲 scope=obt:main')!.args['query'], '甲 乙');
    });

    test('a line carrying two intents is still rejected', () {
      expect(parseIntent('FIND 匕首\nREAD s.txt 0 10'), isNull);
    });
  });

  group('evidence notebook helpers', () {
    test('parseReadObservation honors the DATA range and speaker column', () {
      final page = parseReadObservation(_readObservation)!;
      expect(page.storyId, 'activities/x/level_x_05.txt');
      expect(page.lines.map((l) => l.index), [10, 11, 12]);
      expect(page.line(11)!.speaker, '角色B');
      expect(page.line(11)!.content, '当年我藏起匕首。');
      expect(page.line(10)!.speaker, isNull);
    });

    test('notes drop hallucinated line numbers and quote the real line', () {
      final page = parseReadObservation(_readObservation)!;
      final notes = parseEvidenceNotes(
        'L11: 角色B承认藏起匕首\nL99: 编造的行\n12：火光熄灭',
        page,
      );
      expect(notes.map((n) => n.line), [11, 12]);
      expect(notes.first.quote, '角色B：当年我藏起匕首。');
      expect(notes.first.fact, '角色B承认藏起匕首');
      expect(parseEvidenceNotes('NONE', page), isEmpty);
    });

    test('unreadCitations flags lines and ranges outside read segments', () {
      final state = InvestigationState()
        ..noteRead('activities/x/level_x_05.txt', 10, 12);
      const answer = '证据见 activities/x/level_x_05.txt:11 与 '
          'activities/x/level_x_05.txt:10-12，另见 '
          'activities/x/level_x_05.txt:11-40 和 activities/y/other.txt:3。';
      expect(unreadCitations(answer, state), [
        'activities/x/level_x_05.txt:11-40',
        'activities/y/other.txt:3',
      ]);
    });
  });

  group('PlannerLoop evidence flow (R12)', () {
    test('READ notes are line-anchored and the writer sees raw text', () async {
      final llm = _RoleLLM(
        planner: [
          'READ activities/x/level_x_05.txt 0 100',
          'VERDICT char_b 0.8 multi_hypothesis_contrast',
        ],
        extractor: 'L11: 角色B承认藏起匕首\nL77: 幻觉行',
        writer: ['结论。证据：activities/x/level_x_05.txt:11'],
      );
      final events = await PlannerLoop(
        llmClient: llm,
        extractorClient: llm,
        toolRegistry: ToolRegistry()..register(_DataReadTool()),
        minimumToolCalls: 1,
      )
          .run(
            systemPrompt: 'sys',
            chatHistory: const [],
            userQuery: '谁藏起了匕首',
          )
          .toList();

      // The requested window was 0-100 but only 10-12 came back.
      final lastPlannerRequest = llm.plannerRequests.last
          .map((m) => m.content)
          .join('\n');
      expect(lastPlannerRequest, contains('level_x_05.txt:10-12'));
      expect(lastPlannerRequest, isNot(contains('0-100')));
      expect(
        lastPlannerRequest,
        contains('level_x_05.txt:11 角色B承认藏起匕首 「角色B：当年我藏起匕首。」'),
      );
      expect(lastPlannerRequest, isNot(contains('幻觉行')));
      // The extractor saw the user question.
      expect(llm.extractorRequests.single.last.content, contains('谁藏起了匕首'));
      // The writer received the raw read lines.
      expect(
        llm.writerRequests.single.last.content,
        contains('activities/x/level_x_05.txt:11 角色B：当年我藏起匕首。'),
      );
      final answer = _answer(events);
      expect(answer, contains('level_x_05.txt:11'));
      expect(answer, isNot(contains('来源警告')));
    });

    test('an unread citation triggers one rewrite, then a warning', () async {
      final llm = _RoleLLM(
        planner: [
          'READ activities/x/level_x_05.txt 0 100',
          'VERDICT char_b 0.8 multi_hypothesis_contrast',
        ],
        extractor: 'NONE',
        writer: [
          '证据：activities/x/level_x_05.txt:50',
          '证据：activities/x/level_x_05.txt:60',
        ],
      );
      final events = await PlannerLoop(
        llmClient: llm,
        extractorClient: llm,
        toolRegistry: ToolRegistry()..register(_DataReadTool()),
        minimumToolCalls: 1,
      )
          .run(systemPrompt: 'sys', chatHistory: const [], userQuery: 'q')
          .toList();

      expect(llm.writerRequests, hasLength(2));
      expect(
        llm.writerRequests.last.last.content,
        contains('activities/x/level_x_05.txt:50'),
      );
      final answer = _answer(events);
      expect(answer, contains('来源警告'));
      expect(answer, contains('activities/x/level_x_05.txt:60'));
    });

    test('COVER and FIND route to the coverage and line-search tools',
        () async {
      final coverage = _RecordingTool('search_story_coverage');
      final lines = _RecordingTool('search_story_lines');
      final llm = _RoleLLM(
        planner: ['COVER 角色B', 'FIND 染血 匕首', 'DONE'],
        extractor: 'NONE',
        writer: const [],
      );
      await PlannerLoop(
        llmClient: llm,
        toolRegistry: ToolRegistry()..registerAll([coverage, lines]),
      ).run(systemPrompt: 'sys', chatHistory: const [], userQuery: 'q').toList();

      expect(coverage.calls.single['query'], '角色B');
      expect(lines.calls.single['query'], '染血 匕首');
    });

    test('identical lookups and already-read ranges are not re-executed',
        () async {
      final lines = _RecordingTool('search_story_lines');
      final read = _CountingReadTool();
      final llm = _RoleLLM(
        planner: [
          'FIND 染血 匕首',
          'FIND 染血 匕首', // identical -> answered from state
          'READ activities/x/level_x_05.txt 10 12',
          'READ activities/x/level_x_05.txt 11 12', // inside read segment
          'READ activities/x/level_x_05.txt 11 12', // asked again
          'DONE',
        ],
        extractor: 'NONE',
        writer: const [],
      );
      await PlannerLoop(
        llmClient: llm,
        toolRegistry: ToolRegistry()..registerAll([lines, read]),
      ).run(systemPrompt: 'sys', chatHistory: const [], userQuery: 'q').toList();

      expect(lines.calls, hasLength(1));
      expect(read.calls, 1);
      String request(int fromEnd) =>
          llm.plannerRequests[llm.plannerRequests.length - 1 - fromEnd]
              .map((m) => m.content)
              .join('\n');
      expect(request(0), contains('已检索:'));
      expect(request(0), contains('FIND 染血 匕首'));
      // R16: the first re-read shows the lines again from the pages in
      // hand (no tool call); the second is refused.
      expect(request(1), contains('再给你看一次'));
      expect(request(1), contains('11 | 角色B：当年我藏起匕首。'));
      expect(request(0), contains('已经读过，不再重复提供'));
    });

    test('a stalled run is answered from what was read, via the writer',
        () async {
      final llm = _RoleLLM(
        planner: [
          'READ activities/x/level_x_05.txt 10 12',
          // Afterwards the model keeps issuing searches that add nothing.
          for (var i = 0; i < 20; i++) 'SEARCH 无此人',
        ],
        extractor: 'L11: 角色B承认藏起匕首',
        writer: ['部分回答：activities/x/level_x_05.txt:11'],
      );
      final events = await PlannerLoop(
        llmClient: llm,
        extractorClient: llm,
        toolRegistry: ToolRegistry()
          ..registerAll([_DataReadTool(), _NoResultSearchTool()]),
      ).run(systemPrompt: 'sys', chatHistory: const [], userQuery: 'q').toList();

      final answer = _answer(events);
      expect(answer, startsWith('[STORY_ANSWER: status=partial'));
      expect(answer, contains('部分回答'));
      expect(llm.writerRequests, hasLength(1));
    });

    test('re-phrased searches that surface only known stories stall out',
        () async {
      // Live negative case: the same fruitless search re-phrased many times.
      final llm = _RoleLLM(
        planner: [
          for (var i = 0; i < 30; i++) 'FIND 无此名 变体$i',
        ],
        extractor: 'NONE',
        writer: const [],
      );
      final events = await PlannerLoop(
        llmClient: llm,
        toolRegistry: ToolRegistry()..register(_SameStoriesFindTool()),
      ).run(systemPrompt: 'sys', chatHistory: const [], userQuery: 'q').toList();

      final answer = _answer(events);
      expect(answer, startsWith('[STORY_ANSWER: status=not_covered'));
      // 1 productive search + 8 stalled steps, far below the 24/40 budgets.
      expect(llm.plannerRequests.length, lessThanOrEqualTo(10));
    });

    test('the step budget ends a busy run through the writer', () async {
      final llm = _RoleLLM(
        planner: [
          'READ activities/x/level_x_05.txt 10 12',
          for (var i = 0; i < 20; i++) 'FIND 线索$i', // each adds a log entry
        ],
        extractor: 'NONE',
        writer: ['按预算结束的回答'],
      );
      final events = await PlannerLoop(
        llmClient: llm,
        extractorClient: llm,
        maxToolSteps: 6,
        toolRegistry: ToolRegistry()
          ..registerAll([_DataReadTool(), _RecordingTool('search_story_lines')]),
      ).run(systemPrompt: 'sys', chatHistory: const [], userQuery: 'q').toList();

      expect(_answer(events), startsWith('[STORY_ANSWER: status=partial'));
      expect(_answer(events), contains('按预算结束的回答'));
    });

    test('the disambiguator receives each candidate type and source',
        () async {
      final picker = _CapturingPicker();
      final llm = _RoleLLM(
        planner: ['SEARCH 同名者', 'DONE'],
        extractor: 'NONE',
        writer: const [],
      );
      await PlannerLoop(
        llmClient: llm,
        toolRegistry: ToolRegistry()..register(_TypedAmbiguousSearchTool()),
        disambiguator: EntityDisambiguator(llmClient: picker),
      ).run(systemPrompt: 'sys', chatHistory: const [], userQuery: 'q').toList();

      final prompt = picker.prompts.single;
      expect(prompt, contains('enemy:enemy_x | 同名者 | enemy | enemy_handbook'));
      expect(prompt, contains('char:char_x | 同名者 | operator | operator_profile'));
      expect(prompt, isNot(contains('| entity | game_data')));
    });
  });
}

String _answer(List<ReActEvent> events) => finalAnswerOf(events);

final String _readObservation = appendDataBlock(
  'Story: activities/x/level_x_05.txt\n'
  'Scope: activity:x\n'
  '10 | 夜里火光闪烁。\n'
  '11 | 角色B | 当年我藏起匕首。\n'
  '12 | 火光熄灭了。\n'
  '\n'
  'Read Lines: 3\n'
  'Next Page Token: 13',
  {
    'type': 'read_story_lines',
    'story_id': 'activities/x/level_x_05.txt',
    'first_line': 10,
    'last_line': 12,
    'read_lines': 3,
  },
);

/// Routes each request by role: extractor and writer are recognized by their
/// system prompts, everything else is the planner.
class _RoleLLM extends LLMClient {
  _RoleLLM({
    required List<String> planner,
    required this.extractor,
    required List<String> writer,
  })  : _planner = List.of(planner),
        _writer = List.of(writer);

  final List<String> _planner;
  final String extractor;
  final List<String> _writer;
  final List<List<Message>> plannerRequests = [];
  final List<List<Message>> extractorRequests = [];
  final List<List<Message>> writerRequests = [];

  @override
  Future<String> chat(
    List<Message> messages, {
    List<Map<String, dynamic>>? tools,
    double temperature = 0.7,
    int maxTokens = 2048,
    List<String>? stop,
  }) async {
    final system = messages.first.content;
    if (system.contains('剧情证据摘录员')) {
      extractorRequests.add(List.of(messages));
      return extractor;
    }
    if (system.contains('只根据下方')) {
      writerRequests.add(List.of(messages));
      return _writer.isEmpty ? '' : _writer.removeAt(0);
    }
    plannerRequests.add(List.of(messages));
    return _planner.isEmpty ? 'DONE' : _planner.removeAt(0);
  }
}

/// Returns a page shorter than requested (lines 10-12) with a DATA block.
class _DataReadTool extends AgentTool {
  @override
  String get name => 'read_story_lines';
  @override
  String get description => 'reads';
  @override
  Map<String, dynamic> get parameters => const {'type': 'object'};
  @override
  Future<dynamic> execute(Map<String, dynamic> arguments) async =>
      ToolExecutionResult(observation: _readObservation);
}

/// FIND that always surfaces the same two (unrelated) stories.
class _SameStoriesFindTool extends AgentTool {
  @override
  String get name => 'search_story_lines';
  @override
  String get description => 'find';
  @override
  Map<String, dynamic> get parameters => const {'type': 'object'};
  @override
  Future<dynamic> execute(Map<String, dynamic> arguments) async =>
      const ToolExecutionResult(
        observation: 'Story line hits:\n注意：原文中没有任何一行包含这些词。\n'
            'Story: a/x_01.txt | Scope: activity:x | 无字面命中（仅语义相近）\n'
            'Story: a/x_02.txt | Scope: activity:x | 无字面命中（仅语义相近）',
      );
}

class _NoResultSearchTool extends AgentTool {
  @override
  String get name => 'search_local_lore';
  @override
  String get description => 'search';
  @override
  Map<String, dynamic> get parameters => const {'type': 'object'};
  @override
  Future<dynamic> execute(Map<String, dynamic> arguments) async =>
      const ToolExecutionResult(observation: 'No matching GameData result found.');
}

/// [_DataReadTool] that counts executions.
class _CountingReadTool extends _DataReadTool {
  int calls = 0;
  @override
  Future<dynamic> execute(Map<String, dynamic> arguments) {
    calls++;
    return super.execute(arguments);
  }
}

class _RecordingTool extends AgentTool {
  _RecordingTool(this._name);
  final String _name;
  final List<Map<String, dynamic>> calls = [];
  @override
  String get name => _name;
  @override
  String get description => 'records';
  @override
  Map<String, dynamic> get parameters => const {'type': 'object'};
  @override
  Future<dynamic> execute(Map<String, dynamic> arguments) async {
    calls.add(Map.of(arguments));
    return const ToolExecutionResult(observation: 'ok');
  }
}

/// Compact ambiguous observation in the search_local_lore R10/R11 format.
class _TypedAmbiguousSearchTool extends AgentTool {
  @override
  String get name => 'search_local_lore';
  @override
  String get description => 'search';
  @override
  Map<String, dynamic> get parameters => const {'type': 'object'};
  @override
  Future<dynamic> execute(Map<String, dynamic> arguments) async =>
      const ToolExecutionResult(
        observation: 'Ambiguous GameData entity query: "同名者".\n'
            '候选实体（请用 Entity ID 消歧）:\n'
            '  1. enemy:enemy_x | 同名者 | enemy | enemy_handbook | name_exact | 1.00\n'
            '  2. char:char_x | 同名者 | operator | operator_profile | alias_exact | 0.90',
      );
}

class _CapturingPicker extends LLMClient {
  final List<String> prompts = [];
  @override
  Future<String> chat(
    List<Message> messages, {
    List<Map<String, dynamic>>? tools,
    double temperature = 0.7,
    int maxTokens = 2048,
    List<String>? stop,
  }) async {
    prompts.add(messages.last.content);
    return '2';
  }
}
