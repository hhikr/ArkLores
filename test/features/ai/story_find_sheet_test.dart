import 'package:arklores/core/gamedata/story_coverage_models.dart';
import 'package:arklores/features/ai/story_find_sheet.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const lines = [
    StoryLineEntry(lineIndex: 0, speaker: '甲', content: '灯塔还亮着。'),
    StoryLineEntry(lineIndex: 1, content: 'The LIGHT is cold.'),
    StoryLineEntry(lineIndex: 2, content: '甲', kind: 'divider'),
    StoryLineEntry(lineIndex: 3, speaker: '乙', content: '甲走了，灯塔熄了。'),
  ];

  test('every word in the text or the speaker, ignoring case', () {
    expect(findStoryLines(lines, '灯塔'), [0, 3]);
    expect(findStoryLines(lines, 'light'), [1]);
    expect(findStoryLines(lines, '甲 灯塔'), [0, 3]);
    expect(findStoryLines(lines, '乙 熄'), [3]);
    expect(findStoryLines(lines, '  '), isEmpty);
  });

  test('the heading of attached dialogue is not a line of the text', () {
    expect(findStoryLines(lines, '甲'), [0, 3]);
  });
}
