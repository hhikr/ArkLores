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
    expect(workCounts(steps), (calls: 3, reads: 2));
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
