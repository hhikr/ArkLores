import 'package:arklores/core/library/story_art.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  StoryArtEvent e(int at, String kind, [String? image]) => StoryArtEvent(storyId: 's', seq: at, at: at, kind: kind, image: image);
  bool? lookup(String image, String kind) => image == 'missing' ? null : image == 'solid';
  test('scenes ignore null and solid, but count returns after other scenes', () {
    final shots = arrangeStoryArt([e(0,'background','a'), e(1,'background','solid'), e(2,'background','a'), e(3,'background'), e(4,'background','a'), e(5,'background','b'), e(6,'background','a')], lookup);
    expect(shots.map((s) => s.image), ['a','b','a']);
    expect(shots.map((s) => s.number), [1,2,3]);
    expect(shots.every((s) => s.total == 3), isTrue);
  });
  test('background changes behind CG appear after it is removed', () {
    final shots = arrangeStoryArt([e(0,'background','a'), e(1,'cg','x'), e(2,'background','b'), e(3,'cg_off')], lookup);
    expect(shots.map((s) => s.kind), ['scene','cg','scene']);
    expect(shots.last.at, 3);
    expect(shots[1].until, 3);
  });
  test('CG numbering repeats and segments retain end or extend to end', () {
    final shots = arrangeStoryArt([e(0,'cg','x'), e(1,'cg','y'), e(2,'cg_off'), e(3,'cg','x'), e(4,'cg','missing')], lookup);
    expect(shots.map((s) => s.number), [1,2,1,3]);
    expect(shots.map((s) => s.total), [3,3,3,3]);
    expect(shots.map((s) => s.until), [2,2,null,null]);
    expect(shots.last.missing, isTrue);
  });
  test('missing backgrounds are skipped and item remains unnumbered', () {
    final shots = arrangeStoryArt([e(0,'background','missing'), e(1,'item','item')], lookup);
    expect(shots.single.kind, 'item');
    expect(shots.single.number, isNull);
  });
}
