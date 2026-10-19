// The reader's view of an answer's work: tool calls paired with their
// outputs (also when calls run in parallel), counts for the summary line.
import 'package:arklores/core/agent/chat_message.dart';
import 'package:arklores/core/agent/react_event.dart';
import 'package:arklores/features/ai/work_steps.dart';
import 'package:flutter_test/flutter_test.dart';

ReActStep _call(String tool, Map<String, dynamic> args) => ReActStep(
      type: ReActEventType.toolCall,
      content: '',
      toolName: tool,
      toolArgs: args,
    );

ReActStep _out(String tool, String text) => ReActStep(
      type: ReActEventType.toolObservation,
      content: text,
      toolName: tool,
    );

void main() {
  test('parallel calls get their own outputs, oldest first per tool', () {
    final steps = workStepsOf([
      _call('read_story', {'story_id': 'a/x.txt'}),
      _call('sql', {'query': 'SELECT 1'}),
      _call('read_story', {'story_id': 'a/y.txt'}),
      _out('sql', 'n\n1\n（共 1 行）'),
      _out('read_story', '【X】 a/x.txt\nL5 [甲] 一\nL9 [乙] 二'),
    ]);
    expect(steps.map((s) => s.kind),
        [WorkKind.read, WorkKind.sql, WorkKind.read],);
    expect(steps[0].done, isTrue);
    expect(steps[0].storyTitle, 'X');
    expect(steps[0].lineRange, (5, 9));
    expect(steps[1].rowCount, 1);
    // Still running: titled from its file name.
    expect(steps[2].done, isFalse);
    expect(steps[2].storyTitle, 'y');
    // A read still running has shown nothing yet.
    expect(workCounts(steps), (calls: 3, reads: 1));
  });

  // 0.14 phone: "nine citations, no story read" — the summary counted
  // read_story alone, while the lines a search or a grep prints are read
  // (and can be cited) just the same.
  test('the stories read are those any tool showed lines of', () {
    final steps = workStepsOf([
      _call('search', {'query': '甲 乙'}),
      _out(
        'search',
        '检索“甲 乙”：按意思检索 + 关键词；关键词：甲（3 行）\n'
            '## 明日方舟剧情（最相关的 2 篇）\n'
            '1. 《一》 a/one.txt（意思相近 0.62；关键词 3 行）\n'
            '   L12 [甲] 一句。\n'
            '   …（L13-15 没有列出，要引用先用 read_story 读）\n'
            '2. 《二》 a/two.txt（意思相近 0.60）\n'
            '   L3 [乙] 一句。\n'
            '## 明日方舟资料（档案、干员资料、语音等）\n'
            '   record:r1 | item | 灯 | 一盏灯\n'
            '## 终末地剧情：只有意思较远的段落（最接近 0.50），已略去',
      ),
      _call('grep', {'pattern': '甲', 'story_ids': ['ef/three.txt']}),
      _out('grep', '## 《三》 ef/three.txt（1 处）\n* L7 [甲] 一句。\n  …\n（* 为命中行）'),
      // Counts over the whole library show no line.
      _call('grep', {'pattern': '乙'}),
      _out('grep', '全库共 32 行命中，分布在 16 个故事\n《四》 a/four.txt 2 行'),
      _call('read_story', {'story_id': 'a/one.txt'}),
      _out('read_story', '《一》 a/one.txt\nL0 开头。'),
      _call('sql', {
        'query': 'SELECT story_id, line_index, content FROM story_lines',
      }),
      _out('sql', 'story_id | line_index | content\na/five.txt | 4 | 一句。\n（共 1 行）'),
      _call('sql', {'query': 'SELECT story_id, line_index FROM story_lines'}),
      _out('sql', 'story_id | line_index\na/six.txt | 4\n（共 1 行）'),
      _call('read_record', {'id': 'r1'}),
      _out('read_record', 'record:r1 | operator·voice | 交谈1 | 所属：守灯人\n一句话。'),
    ]);
    expect(steps[0].storiesShown, {'a/one.txt', 'a/two.txt'});
    expect(steps[2].grepCounts, (32, 16));
    expect(steps[2].storiesShown, isEmpty);
    expect(steps.last.kind, WorkKind.readRecord);
    expect(steps.last.recordTitle, '守灯人 · 交谈1');
    // one, two, three, five: read_story of a story a search listed counts
    // once; a query without the text and library-wide counts show nothing.
    expect(workCounts(steps), (calls: 7, reads: 4));
  });

  // 0.14: an answer taken back is not a step.
  test('notes and errors are steps too; empty and failed outputs are '
      'recognised', () {
    final steps = workStepsOf([
      const ReActStep(type: ReActEventType.thought, content: '  想一想  '),
      const ReActStep(type: ReActEventType.thought, content: ' '),
      _call('grep', {'pattern': '甲'}),
      _out('grep', '没有找到“甲”。'),
      _call('sql', {'query': 'DROP x'}),
      _out('sql', '错误：只允许 SELECT'),
      const ReActStep(type: ReActEventType.finalAnswerReset, content: ''),
      const ReActStep(type: ReActEventType.error, content: 'LLM Error: 500'),
    ]);
    expect(steps.map((s) => s.kind), [
      WorkKind.note,
      WorkKind.grep,
      WorkKind.sql,
      WorkKind.error,
    ]);
    expect(steps[0].text, '想一想');
    expect(steps[1].empty, isTrue);
    expect(steps[2].failed, isTrue);
    expect(steps[2].empty, isFalse);
    expect(workCounts(steps), (calls: 2, reads: 0));
  });

  // 0.14: read_story's output starts `《title》 story_id`; the row showed the
  // file name because it looked for 【】.
  test('a read is titled by the story name the tool printed', () {
    final step = workStepsOf([
      _call('read_story', {'story_id': 'activities/a/level_a_07_end.txt'}),
      _out(
        'read_story',
        '《活动 A-7 行动后《结尾》》 activities/a/level_a_07_end.txt\nL0 一',
      ),
    ]).single;
    expect(step.storyTitle, '活动 A-7 行动后《结尾》');
  });

  test('every way a tool refuses or fails is a failed step, with its reason',
      () {
    for (final text in [
      '错误：grep 缺少必填参数 pattern\n收到的参数：{}',
      '工具出错：DatabaseException(error database_closed)',
      '参数不是合法的 JSON：{}{}',
      'SQL 错误：no such column: name',
      '子任务出错：x',
    ]) {
      final step = workStepsOf([_call('grep', {}), _out('grep', text)]).single;
      expect(step.failed, isTrue, reason: text);
      expect(step.failure, text.split('\n').first);
    }
    // A search whose wiki part could not be reached still found stories.
    final search = workStepsOf([
      _call('search', {'query': '甲'}),
      _out('search', '## 明日方舟剧情（最相关的 2 篇）\n## 终末地剧情（最相关的 1 篇）\n'
          '## Wiki\nPRTS 暂时无法访问（超时）'),
    ]).single;
    expect(search.kind, WorkKind.find);
    expect(search.failed, isFalse);
    expect(search.searchStoryCount, 3);
    // Gathering says how many stories hold the names and how many it gave.
    final gather = workStepsOf([
      _call('gather', {
        'names': ['甲'],
      }),
      _out('gather', '按名字取材：这些名字出现在 12 篇剧情里，给了 5 篇剧情的原文（30000 字）。'),
    ]).single;
    expect(gather.kind, WorkKind.gather);
    expect(gather.gatherStoryCount, 5);
    expect(gather.gatherLocatedCount, 12);
  });

  test("a helper's outputs go to the helper's own calls", () {
    final steps = workStepsOf([
      _call('delegate', {'task': '甲'}),
      const ReActStep(
        type: ReActEventType.toolCall,
        content: '',
        toolName: 'read_story',
        toolArgs: {'story_id': 'a/x.txt'},
        subtask: 1,
      ),
      _call('read_story', {'story_id': 'a/y.txt'}),
      const ReActStep(
        type: ReActEventType.toolObservation,
        content: '《X》 a/x.txt\nL0 一',
        toolName: 'read_story',
        subtask: 1,
      ),
    ]);
    expect(steps[1].subtask, 1);
    expect(steps[1].done, isTrue);
    expect(steps[1].storyTitle, 'X');
    expect(steps[2].done, isFalse);
  });

  test('grep counts hits and stories', () {
    final step = workStepsOf([
      _call('grep', {'pattern': '甲|乙'}),
      _out('grep', '## 《一》 a.txt（3 处）\n L1 x\n## 《二》 b.txt（4 处）\n L2 y'),
    ]).single;
    expect(step.grepCounts, (7, 2));
    expect(step.arg('pattern'), '甲|乙');
  });
}
