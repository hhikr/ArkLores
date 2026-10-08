// How the agent's tools print a story line (the tools themselves run over a
// knowledge base in lore_agent_loop_test).
import 'package:arklores/core/agent/lore_tools.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a line with breaks of its own stays one printed line', () {
    expect(
      formatStoryLine(108, null, '展信佳。\n恩希亚，你好。\n\n另：记得回信。',
          kind: 'document',),
      startsWith('L108 '),
    );
    final printed = formatStoryLine(
      108,
      null,
      '展信佳。\n恩希亚，你好。\n\n另：记得回信。',
      kind: 'document',
    );
    expect(printed, isNot(contains('\n')));
    expect(printed, endsWith('展信佳。 / 恩希亚，你好。 / 另：记得回信。'));
    expect(formatStoryLine(3, '甲', '一句话'), 'L3 [甲] 一句话');
  });
}
