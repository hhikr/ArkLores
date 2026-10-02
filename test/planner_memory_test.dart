// R16: the planner keeps what it has read in hand (chapter digests, folded
// rather than dropped notes, outline index with read marks, its own plan,
// the step budget), and the run's status follows the evidence instead of
// the reason the search stopped.
import 'package:arklores/core/agent/evidence_notebook.dart';
import 'package:arklores/core/agent/investigation_state.dart';
import 'package:arklores/core/agent/planner_intent.dart';
import 'package:arklores/core/agent/planner_loop.dart';
import 'package:arklores/core/agent/react_event.dart';
import 'package:arklores/core/agent/story_answer.dart';
import 'package:arklores/core/agent/tools/agent_tool.dart';
import 'package:arklores/core/agent/tools/observation_data.dart';
import 'package:arklores/core/agent/tools/tool_registry.dart';
import 'package:arklores/core/llm/llm_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('state the planner sees', () {
    test('a read chapter shows its digest; one without notes says so', () {
      final state = InvestigationState()
        ..noteRead('a/c1.txt', 0, 40)
        ..noteDigest('a/c1.txt', '甲与乙在港口争吵')
        ..noteRead('a/c2.txt', 0, 30)
        ..noteDigest('a/c2.txt', '乙独自离开');
      state.addNotes(const [
        EvidenceNote(storyId: 'a/c1.txt', line: 12, fact: '甲威胁乙', quote: '甲：你会后悔的。'),
      ]);
      final text = state.serialize();
      expect(text, contains('a/c1.txt:0-40'));
      expect(text, contains('摘要: 甲与乙在港口争吵'));
      expect(text, contains('a/c1.txt:12 甲威胁乙'));
      expect(text, contains('摘要: 乙独自离开'));
      expect(text, contains('（没有与问题直接相关的行）'));
    });

    test('notes beyond the shown budget fold for older chapters, never drop',
        () {
      final state = InvestigationState();
      for (var c = 0; c < 3; c++) {
        state.noteRead('a/c$c.txt', 0, 100);
        state.addNotes([
          for (var i = 0; i < 20; i++)
            EvidenceNote(storyId: 'a/c$c.txt', line: i, fact: 'f$c-$i', quote: 'q'),
        ]);
      }
      expect(state.notes, hasLength(60));
      final planner = state.serialize();
      // Newest chapters first: c2 and c1 fully shown (40), c0 folded.
      expect(planner, contains('a/c2.txt:19 f2-19'));
      expect(planner, contains('a/c1.txt:0 f1-0'));
      expect(planner, isNot(contains('f0-5 ')));
      expect(planner, contains('（另有 20 条笔记已折叠，写答案时完整使用）'));
      // The writer sees every note.
      final writer = state.serializeForWriter();
      expect(writer, contains('a/c0.txt:5 f0-5'));
      expect(writer, isNot(contains('已折叠')));
    });

    test('outlines stay as an index with read marks; synopses only for '
        'unread chapters of the newest outlines', () {
      String outline(String id) => compactOutline(
            'Outline: 《$id》（$id，共 2 章）\n'
            '1. $id-1《开端》 | a/$id-1.txt | 行动前\n'
            '   梗概: $id 第一章的梗概\n'
            '2. $id-2《结局》 | a/$id-2.txt | 行动后\n'
            '   梗概: $id 第二章的梗概\n',
          );
      final state = InvestigationState();
      for (final id in ['s1', 's2', 's3', 's4']) {
        state.noteOutline(id, outline(id));
      }
      state.noteRead('a/s4-1.txt', 0, 211);
      final text = state.serialize();
      // All four collections keep their chapter index.
      for (final id in ['s1', 's2', 's3', 's4']) {
        expect(text, contains('a/$id-2.txt'));
      }
      expect(text, contains('a/s4-1.txt ✓ 0-211'));
      expect(text, isNot(contains('s4 第一章的梗概')), reason: 'read chapter');
      expect(text, contains('s4 第二章的梗概'));
      expect(text, isNot(contains('s1 第二章的梗概')), reason: 'oldest outline');
    });

    test('the step budget is shown and warns when nearly spent', () {
      final state = InvestigationState()
        ..stepBudget = 24
        ..stepsUsed = 10;
      expect(state.serialize(), contains('步数: 已用 10 / 24'));
      expect(state.serialize(), isNot(contains('只剩')));
      state.stepsUsed = 21;
      expect(state.serialize(), contains('只剩 3 步'));
      expect(state.serializeForWriter(), isNot(contains('步数')));
    });

    test('a plan note is split off the intent', () {
      final split = splitPlanNote('READ a/c1.txt 0 200 # 接着读 c2、c3');
      expect(split.intent, 'READ a/c1.txt 0 200');
      expect(split.plan, '接着读 c2、c3');
      expect(parseIntent(split.intent)!.args['end_line'], 200);
      expect(splitPlanNote('ANSWER 0.8').plan, '');
    });

    test('the extractor digest line is parsed', () {
      expect(parseDigest('摘要: 两人对峙\nL3: 甲拔刀'), '两人对峙');
      expect(parseDigest('NONE'), '');
    });
  });

  group('status follows the evidence', () {
    test('coverage line decides; stop reason only without it', () {
      for (final stop in StopReason.values) {
        expect(
          answerStatus(nothingRead: false, coverage: StoryCoverage.full, stop: stop),
          StoryAnswerStatus.answered,
        );
        expect(
          answerStatus(nothingRead: false, coverage: StoryCoverage.gaps, stop: stop),
          StoryAnswerStatus.partial,
        );
        expect(
          answerStatus(nothingRead: true, coverage: StoryCoverage.full, stop: stop),
          StoryAnswerStatus.notCovered,
        );
      }
      expect(
        answerStatus(nothingRead: false, coverage: null, stop: StopReason.budget),
        StoryAnswerStatus.partial,
      );
      expect(
        answerStatus(nothingRead: false, coverage: null, stop: StopReason.answer),
        StoryAnswerStatus.answered,
      );
    });

    test('the coverage line is stripped from the answer', () {
      final split = splitCoverage('正文。\n\n**[COVERAGE: gaps]**');
      expect(split.body, '正文。');
      expect(split.coverage, StoryCoverage.gaps);
      expect(splitCoverage('没有标记').coverage, isNull);
    });

    test('a budget stop is neutral to the writer and can end answered',
        () async {
      final writer = _Writer('结论（s.txt:1）。\n[COVERAGE: full]');
      final events = await PlannerLoop(
        llmClient: _Planner(['READ s.txt 0 3', for (var i = 0; i < 10; i++) 'SEARCH 某人 $i']),
        writerClient: writer,
        toolRegistry: ToolRegistry()..registerAll([_ReadTool(), _SearchTool()]),
        maxToolSteps: 3,
      ).run(systemPrompt: 's', chatHistory: [], userQuery: 'q').toList();
      expect(finalAnswerOf(events), startsWith('[STORY_ANSWER: status=answered'));
      expect(writer.system, contains('步数上限结束，这本身不代表证据不足'));
      expect(writer.system, contains('[COVERAGE: full]'));
      expect(writer.system, isNot(contains('证据充分之前停止')));
    });

    test('after two re-shown passages, asking to re-read ends the search',
        () async {
      final planner = _Planner([
        'READ s.txt 0 3',
        'READ s.txt 0 2', // shown again (1)
        'READ s.txt 1 2', // shown again (2)
        'READ s.txt 0 1', // done reading: writer
        'SEARCH 不该执行',
      ]);
      final search = _SearchTool();
      final events = await PlannerLoop(
        llmClient: planner,
        writerClient: _Writer('结论（s.txt:1）。\n[COVERAGE: full]'),
        toolRegistry: ToolRegistry()..registerAll([_ReadTool(), search]),
      ).run(systemPrompt: 's', chatHistory: [], userQuery: 'q').toList();
      expect(
        events.where((e) => e.content.contains('再给你看一次')),
        hasLength(2),
      );
      expect(planner._script, ['SEARCH 不该执行']);
      expect(finalAnswerOf(events), startsWith('[STORY_ANSWER: status=answered'));
    });

    test('a READ past the end of a read chapter says so plainly', () async {
      final planner = _Planner(['READ s.txt 0 2', 'READ s.txt 0 120', 'ANSWER']);
      await PlannerLoop(
        llmClient: planner,
        writerClient: _Writer('结论（s.txt:1）。'),
        toolRegistry: ToolRegistry()..register(_EndAwareReadTool()),
      ).run(systemPrompt: 's', chatHistory: [], userQuery: 'q').toList();
      final last = planner.requests.last.map((m) => m.content).join('\n');
      expect(last, contains('s.txt 已经读到结尾（已读 0-2）'));
      expect(last, isNot(contains('No lines in the requested range')));
    });

    test('the writer is told how to treat a near name', () async {
      final writer = _Writer('结论（s.txt:1）。');
      await PlannerLoop(
        llmClient: _Planner(['READ s.txt 0 3', 'ANSWER']),
        writerClient: writer,
        toolRegistry: ToolRegistry()..register(_ReadTool()),
      ).run(systemPrompt: 's', chatHistory: [], userQuery: 'q').toList();
      expect(writer.system, contains('按那个名字作答'));
    });

    test('the writer saying gaps makes an ANSWER run partial', () async {
      final events = await PlannerLoop(
        llmClient: _Planner(['READ s.txt 0 3', 'ANSWER']),
        writerClient: _Writer('只知道一半（s.txt:1）。\n[COVERAGE: gaps]'),
        toolRegistry: ToolRegistry()..register(_ReadTool()),
      ).run(systemPrompt: 's', chatHistory: [], userQuery: 'q').toList();
      expect(finalAnswerOf(events), startsWith('[STORY_ANSWER: status=partial'));
    });
  });

  group('writer source', () {
    List<ReadPage> pages(int chapters, int lines) => [
          for (var c = 0; c < chapters; c++)
            ReadPage(
              storyId: 'a/c$c.txt',
              lines: [
                for (var i = 0; i < lines; i++)
                  ReadLine(index: i, content: '第$c章第$i行的内容，长度大约二十个字。'),
              ],
            ),
        ];

    test('everything fits: all lines, in chapter and line order', () {
      final text = buildWriterSource(pages(2, 5), InvestigationState());
      expect(text.indexOf('a/c0.txt:0 '), lessThan(text.indexOf('a/c0.txt:4 ')));
      expect(text.indexOf('a/c0.txt:4 '), lessThan(text.indexOf('a/c1.txt:0 ')));
      expect(text, isNot(contains('…')));
    });

    test('over the cap, the chapter read last still gets in and noted lines '
        'come first', () {
      final state = InvestigationState()
        ..addNotes(const [
          EvidenceNote(storyId: 'a/c0.txt', line: 150, fact: 'f', quote: 'q'),
        ]);
      final text = buildWriterSource(pages(6, 200), state, maxChars: 20000);
      expect(text.length, lessThanOrEqualTo(20000 + 600));
      expect(text, contains('a/c5.txt:0 '), reason: 'last chapter not cut whole');
      for (var i = 145; i <= 155; i++) {
        expect(text, contains('a/c0.txt:$i '), reason: 'note context $i');
      }
      expect(text, contains('…'));
    });
  });
}

class _Planner extends LLMClient {
  _Planner(List<String> script) : _script = List.of(script);
  final List<String> _script;
  final List<List<Message>> requests = [];
  @override
  Future<String> chat(
    List<Message> messages, {
    List<Map<String, dynamic>>? tools,
    double temperature = 0.7,
    int maxTokens = 2048,
    List<String>? stop,
  }) async {
    requests.add(List.of(messages));
    return _script.isEmpty ? 'DONE' : _script.removeAt(0);
  }
}

/// A 3-line chapter: a start past line 2 returns no lines.
class _EndAwareReadTool extends _ReadTool {
  @override
  Future<dynamic> execute(Map<String, dynamic> arguments) async {
    final start = (arguments['start_line'] as num?)?.toInt() ?? 0;
    if (start > 2) {
      return const ToolExecutionResult(
        observation: 'No lines in the requested range for story "s.txt". '
            'Story: s.txt\nRead Lines: 0',
      );
    }
    return super.execute(arguments);
  }
}

class _Writer extends LLMClient {
  _Writer(this.reply);
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
}

class _ReadTool extends AgentTool {
  @override
  String get name => 'read_story_lines';
  @override
  String get description => 'reads';
  @override
  Map<String, dynamic> get parameters => const {'type': 'object'};
  @override
  Future<dynamic> execute(Map<String, dynamic> arguments) async =>
      ToolExecutionResult(
        observation: appendDataBlock(
          'Story: s.txt\n0 | 旁白 | 夜。\n1 | B | 是我做的。\n2 | 旁白 | 天亮了。',
          {
            'type': 'read_story_lines',
            'story_id': 's.txt',
            'first_line': 0,
            'last_line': 2,
          },
        ),
      );
}

class _SearchTool extends AgentTool {
  var _n = 0;
  @override
  String get name => 'search_local_lore';
  @override
  String get description => 'search';
  @override
  Map<String, dynamic> get parameters => const {'type': 'object'};
  @override
  Future<dynamic> execute(Map<String, dynamic> arguments) async =>
      // A new story each time, so the run is not a stall: only the budget
      // stops it.
      ToolExecutionResult(observation: 'Story: x/new_${_n++}.txt | hit');
}
