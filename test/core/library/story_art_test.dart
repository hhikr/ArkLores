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
  test('missing backgrounds retain a scene label and item remains unnumbered', () {
    final shots = arrangeStoryArt([e(0,'background','missing'), e(1,'item','item')], lookup);
    expect(shots.first.kind, 'scene');
    expect(shots.first.missing, isTrue);
    expect(shots.last.kind, 'item');
    expect(shots.last.number, isNull);
  });
  test('removing a CG over an unchanged background adds no scene; solid close-ups are skipped', () {
    final shots = arrangeStoryArt([e(0,'background','a'), e(1,'cg','x'), e(2,'item','solid'), e(3,'cg_off')], lookup);
    expect(shots.map((s) => s.kind), ['scene','cg']);
  });
  test('scenes changed on one line join; numbers and total stay', () {
    StoryArtEvent at(int seq, int line, String kind, [String? image]) =>
        StoryArtEvent(storyId: 's', seq: seq, at: line, kind: kind, image: image);
    final shots = arrangeStoryArt([
      at(0, 0, 'background', 'a'),
      at(1, 5, 'background', 'b'),
      at(2, 5, 'background', 'c'),
      at(3, 5, 'background', 'd'),
      at(4, 5, 'cg', 'x'),
      at(5, 5, 'cg_off'),
      at(6, 5, 'background', 'e'),
      at(7, 9, 'background', 'f'),
    ], lookup,);
    expect(shots.map((s) => (s.kind, s.number, s.joined)), [
      ('scene', 1, false),
      ('scene', 2, false),
      ('scene', 3, true),
      ('scene', 4, true),
      ('cg', 1, false),
      ('scene', 5, false),
      ('scene', 6, false),
    ]);
    expect(shots.where((s) => s.kind == 'scene').every((s) => s.total == 6),
        isTrue,);
  });
  test('close-ups put up just before a CG on its line go into its segment', () {
    StoryArtEvent at(int seq, int line, String kind, [String? image]) =>
        StoryArtEvent(storyId: 's', seq: seq, at: line, kind: kind, image: image);
    final shots = arrangeStoryArt([
      at(0, 3, 'item', 'i1'),
      at(1, 3, 'item', 'i2'),
      at(2, 3, 'cg', 'x'),
      at(3, 6, 'cg_off'),
      // taken down in between, or the CG on a later line: not moved
      at(4, 8, 'item', 'i3'),
      at(5, 8, 'cg_off'),
      at(6, 8, 'cg', 'y'),
      at(7, 10, 'item', 'i4'),
      at(8, 11, 'cg', 'z'),
    ], lookup,);
    expect(shots.map((s) => (s.image, s.segment)), [
      ('x', 1),
      ('i1', 1),
      ('i2', 1),
      ('i3', null),
      ('y', 2),
      ('i4', 2),
      ('z', 2),
    ]);
  });
}
