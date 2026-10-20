import 'package:flutter_test/flutter_test.dart';

import '../../support/scene_cards.dart';

void main() {
  final lines = [
    for (var i = 0; i < 80; i++)
      (
        line: i,
        speaker: i.isEven ? '甲' : '乙',
        content: i == 10 ? '丙离开了灯塔。' : '第$i行',
      ),
  ];

  test('a card keeps only names in the story and lines inside it', () {
    final card = parseSceneCard(
      '说明文字 {"people": ["甲", "丙", "丁"], '
      '"events": [{"text": "甲与乙谈话。", "lines": [2, 5]}, '
      '{"text": "超出范围。", "lines": [90, 95]}, '
      '{"text": "很长的一段。", "lines": [70, 5]}], '
      '"changes": [{"text": "丙离开。", "lines": [10]}], '
      '"open": ["", "丙去了哪里。"]}',
      storyId: 'x.txt',
      title: '集 · 篇',
      lines: lines,
    )!;
    // 丁 is nowhere in the lines.
    expect(card.people, ['甲', '丙']);
    expect(
      [for (final e in card.events) '${e.text} ${e.first}-${e.last}'],
      // Out of the story: dropped; reversed and too long: cut to 30 lines.
      ['甲与乙谈话。 2-5', '很长的一段。 5-34'],
    );
    expect([for (final c in card.changes) '${c.first}-${c.last}'], ['10-10']);
    expect(card.open, ['丙去了哪里。']);
    expect(card.ranges, [(2, 34)]);
    expect(SceneCard.fromJson(card.toJson()).embeddingText, card.embeddingText);
  });

  test('a reply with no events or no JSON is no card', () {
    expect(
      parseSceneCard('{"people": ["甲"], "events": []}',
          storyId: 'x.txt', title: '', lines: lines,),
      isNull,
    );
    expect(
      parseSceneCard('没有 JSON', storyId: 'x.txt', title: '', lines: lines),
      isNull,
    );
  });

  test('the prompt names no story, person or place', () {
    // Placeholders only (anti-fixture rule).
    expect(sceneCardPrompt, isNot(matches(RegExp(r'[《》]'))));
    expect(sceneCardPrompt, contains('<人名>'));
  });
}
