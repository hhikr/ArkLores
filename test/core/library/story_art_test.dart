import 'package:arklores/core/library/story_art.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  StoryArtEvent e(int at, String kind, [String? image]) =>
      StoryArtEvent(storyId: 's', seq: at, at: at, kind: kind, image: image);
  bool? lookup(String image, String kind) =>
      image == 'missing' ? null : image == 'solid';
  test('scenes ignore null and solid, but count returns after other scenes',
      () {
    final shots = arrangeStoryArt([
      e(0, 'background', 'a'),
      e(1, 'background', 'solid'),
      e(2, 'background', 'a'),
      e(3, 'background'),
      e(4, 'background', 'a'),
      e(5, 'background', 'b'),
      e(6, 'background', 'a'),
    ], lookup,);
    expect(shots.map((s) => s.image), ['a', 'b', 'a']);
    expect(shots.map((s) => s.number), [1, 2, 3]);
    expect(shots.every((s) => s.total == 3), isTrue);
  });
  test('background changes behind CG appear after it is removed', () {
    final shots = arrangeStoryArt([
      e(0, 'background', 'a'),
      e(1, 'cg', 'x'),
      e(2, 'background', 'b'),
      e(3, 'cg_off'),
    ], lookup,);
    expect(shots.map((s) => s.kind), ['scene', 'cg', 'scene']);
    expect(shots.last.at, 3);
    expect(shots[1].until, 3);
  });
  test('CG numbering repeats and segments retain end or extend to end', () {
    final shots = arrangeStoryArt([
      e(0, 'cg', 'x'),
      e(1, 'cg', 'y'),
      e(2, 'cg_off'),
      e(3, 'cg', 'x'),
      e(4, 'cg', 'missing'),
    ], lookup,);
    expect(shots.map((s) => s.number), [1, 2, 1, 3]);
    expect(shots.map((s) => s.total), [3, 3, 3, 3]);
    expect(shots.map((s) => s.until), [2, 2, null, null]);
    expect(shots.last.missing, isTrue);
  });
  test('layers over missing backgrounds retain scene numbering', () {
    final shots = arrangeStoryArt(
        [e(0, 'background', 'missing'), e(1, 'item', 'item')], lookup,);
    expect(shots.first.kind, 'scene');
    expect(shots.first.missing, isTrue);
    expect(shots.last.kind, 'scene');
    expect(shots.last.number, 1);
    expect(shots.last.total, 1);
    expect(shots.last.layers.single.image, 'item');
  });
  test(
      'removing a CG over an unchanged background adds no scene; solid layers darken the CG',
      () {
    final shots = arrangeStoryArt([
      e(0, 'background', 'a'),
      e(1, 'cg', 'x'),
      e(2, 'item', 'solid'),
      e(3, 'cg_off'),
    ], lookup,);
    expect(shots.map((s) => s.kind), ['scene', 'cg', 'cg']);
    expect(shots.last.layers.single.image, 'solid');
    expect(shots.last.number, 1);
  });

  test('all commands on one line produce the final scene', () {
    final shots = arrangeStoryArt(
      [
        e(0, 'background', 'a'),
        e(5, 'background', 'b'),
        e(5, 'background', 'c'),
        e(5, 'cg', 'x'),
        e(5, 'cg_off'),
        e(5, 'background', 'd'),
        e(9, 'background', 'e'),
      ],
      lookup,
    );
    expect(
      shots.map((s) => (s.image, s.number, s.total)),
      [('a', 1, 3), ('d', 2, 3), ('e', 3, 3)],
    );
  });
  test('layers and CG on one line emit one CG, persist across changes', () {
    final shots = arrangeStoryArt(
      [
        e(3, 'item', 'i1'),
        e(3, 'item', 'i2'),
        e(3, 'cg', 'x'),
        e(6, 'cg', 'y'),
        e(8, 'item', 'i3'),
        e(9, 'item_off', 'i1'),
      ],
      lookup,
    );
    expect(shots.map((s) => (s.image, s.number)),
        [('x', 1), ('y', 2), ('y', 2), ('y', 2)],);
    expect(shots.first.layers.map((l) => l.image), ['i1', 'i2']);
    expect(shots[1].layers.map((l) => l.image), ['i1', 'i2']);
    expect(shots.last.layers.map((l) => l.image), ['i2', 'i3']);
  });
  test('layers leaving a real scene show it bare; a cleared stage shows nothing',
      () {
    final shots = arrangeStoryArt(
      [
        e(0, 'background', 'a'),
        e(1, 'item', 'i1'),
        e(2, 'item_off', 'i1'),
        e(3, 'background'),
        e(3, 'item', 'i2'),
        e(5, 'item_off', 'i2'),
        e(6, 'background', 'solid'),
        e(6, 'item', 'i3'),
        e(8, 'item_off'),
      ],
      lookup,
    );
    expect(shots.map((s) => (s.image, s.layers.length)),
        [('a', 0), ('a', 1), ('a', 0), ('', 1), ('solid', 1)],);
  });
  test('layers sort by depth then appearance; updates retain appearance', () {
    StoryArtEvent layer(String id, int depth, double x) => StoryArtEvent(
          storyId: 's',
          seq: 0,
          at: 1,
          kind: 'item',
          image: id,
          layer: depth,
          x: x,
        );
    final shots = arrangeStoryArt(
      [
        e(0, 'background', 'a'),
        layer('first', 2, 0),
        layer('second', 1, 0),
        layer('third', 2, 0),
        layer('first', 2, 50),
      ],
      lookup,
    );
    expect(shots.last.layers.map((l) => l.image), ['second', 'first', 'third']);
    expect(shots.last.layers[1].x, 50);
    expect(shots.last.number, 1);
    expect(shots.last.total, 1);
  });
}
