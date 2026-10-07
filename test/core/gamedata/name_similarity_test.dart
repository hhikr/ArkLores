// R15: names the knowledge base does not have get near names, by reading
// and by characters; the hint only says the strings are similar. All names
// are fictional.
import 'package:arklores/core/gamedata/name_similarity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const inventory = [
    NameOccurrence('洛蕾西娅', 600, '剧情提及'),
    NameOccurrence('洛雷西斯', 900, '剧情提及'),
    NameOccurrence('谬安', 2, '干员'),
    NameOccurrence('凯伦', 50, '说话人'),
  ];

  test('a homophone spelling ranks above a one-character neighbour', () {
    // `洛雷西亚` differs from `洛雷西斯` by one character but sounds like
    // `洛蕾西娅` (two homophone substitutions): reading wins.
    final ranked = rankSimilarNames('洛雷西亚', inventory);
    expect(ranked.map((s) => s.name), ['洛蕾西娅', '洛雷西斯']);
    expect(ranked.first.cost, closeTo(2 * homophoneCost, 1e-9));
    expect(rankSimilarNames('缪安', inventory).first.name, '谬安');
  });

  test('nothing for names without a shared character or too far away', () {
    expect(rankSimilarNames('完全无关', inventory), isEmpty);
    expect(
      rankSimilarNames('洛蕾西娅', inventory).map((s) => s.name),
      isNot(contains('洛蕾西娅')),
    );
  });

  test('the hint states string similarity only', () {
    final hint = describeSimilarNames('缪安', rankSimilarNames('缪安', inventory))!;
    expect(hint, contains('谬安（干员，2 次）'));
    expect(hint, contains('只是字符串相近'));
  });

  test('names in a question: longer known strings block their parts', () {
    const known = [
      NameOccurrence('伊塔利亚', 300, '剧情提及'),
      NameOccurrence('塔利', 40, '说话人'),
      NameOccurrence('凯伦', 50, '说话人'),
      NameOccurrence('路人', 2, '说话人'),
    ];
    expect(namesMentionedIn('伊塔利亚的凯伦和路人', known), ['凯伦']);
    expect(namesMentionedIn('塔利去哪了', known), ['塔利']);
  });
}
