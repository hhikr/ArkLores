// The compact history a question gets after a restored session (or after an
// error): earlier questions, answers, and the chapters each answer read.
import 'package:arklores/core/agent/chat_message.dart';
import 'package:arklores/core/agent/chat_notifier_base.dart';
import 'package:arklores/core/agent/react_event.dart';
import 'package:arklores/core/llm/llm_client.dart';
import 'package:flutter_test/flutter_test.dart';

ReActStep _call(String tool, Map<String, dynamic> args, {int? subtask}) =>
    ReActStep(
      type: ReActEventType.toolCall,
      content: '',
      toolName: tool,
      toolArgs: args,
      subtask: subtask,
    );

ReActStep _out(String tool, String text, {int? subtask}) => ReActStep(
      type: ReActEventType.toolObservation,
      content: text,
      toolName: tool,
      subtask: subtask,
    );

void main() {
  test('reads are taken from the read_story steps, also for helpers', () {
    final steps = [
      _call('read_story', {'story_id': 'a/x.txt'}),
      _call('grep', {'pattern': '甲'}),
      _call('read_story', {'story_id': 'a/y'}),
      _out('read_story', '《X》 a/x.txt\nL3 一\nL40 二\n（本页到 L40）'),
      _out('grep', '## …'),
      _out('read_story', '《Y》 a/y.txt\nL0 三'),
      _call('read_story', {'story_id': 'b/z.txt'}, subtask: 1),
      _out('read_story', '没有这个 story_id：b/z.txt。', subtask: 1),
    ];
    expect(storyReadsOf(steps), [('a/x.txt', 3, 40), ('a/y.txt', 0, 0)]);

    final history = buildStoryQaHistory([
      ChatMessage(
        id: 'u',
        role: MessageRole.user,
        content: '甲是谁？',
        timestamp: DateTime(2026),
      ),
      ChatMessage(
        id: 'a',
        role: MessageRole.assistant,
        content: '甲是乙。',
        steps: steps,
        timestamp: DateTime(2026),
      ),
    ]);
    expect(history.last.content, contains('这一轮已读原文: a/x.txt:3-40；a/y.txt:0-0'));
  });
}
