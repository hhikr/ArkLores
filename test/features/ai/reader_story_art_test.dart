import 'package:arklores/core/gamedata/story_art_pack.dart';
import 'package:arklores/core/gamedata/story_art_pack_provider.dart';
import 'package:arklores/core/gamedata/story_coverage_models.dart';
import 'package:arklores/core/library/story_art.dart';
import 'package:arklores/features/ai/reader_story_art.dart';
import 'package:arklores/shared/providers/settings_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Pack extends StoryArtPack {
  _Pack({this.present = true}) : super('unused');
  final bool present;
  int infoQueries = 0;
  @override
  Future<bool> get installed async => present;
  @override
  Future<Map<(String, String), StoryArtInfo>> artInfo(
      Iterable<(String, String)> keys,) async {
    infoQueries++;
    return {
      for (final key in keys)
        key: const StoryArtInfo(100, 50, 'background', false),
    };
  }

  @override
  Future<StoryArtTitle?> artTitle(String id) async => null;
  @override
  Future<void> close() async {}
}

void main() {
  test('off reads neither the pack nor events', () async {
    final container = ProviderContainer(overrides: [
      initialStoryArtModeProvider.overrideWithValue(StoryArtMode.off),
      storyArtPackProvider.overrideWith((ref) => throw StateError('pack read')),
      storyArtEventsProvider
          .overrideWith((ref, id) => throw StateError('events read')),
    ],);
    addTearDown(container.dispose);
    expect(
        await container.read(readerStoryArtProvider((
          storyId: 'fixture.txt',
          lines: const [StoryLineEntry(lineIndex: 0, content: 'text')],
          sources: const {},
        ),).future,),
        isNull,);
  });
  test('attached stories reset stage and retain continuous numbering',
      () async {
    final pack = _Pack();
    StoryArtEvent event(String id, int at, String kind, [String? image]) =>
        StoryArtEvent(storyId: id, seq: at, at: at, kind: kind, image: image);
    final events = {
      'host': [
        event('host', 0, 'background', 'a'),
        event('host', 1, 'cg', 'cg'),
      ],
      'child': [
        event('child', 0, 'background', 'a'),
        event('child', 1, 'cg', 'cg'),
        event('child', 2, 'cg_off'),
      ],
    };
    final container = ProviderContainer(
      overrides: [
        storyArtPackProvider.overrideWith((ref) async => pack),
        storyArtEventsProvider
            .overrideWith((ref, id) async => events[id] ?? []),
      ],
    );
    addTearDown(container.dispose);
    final key = (
      storyId: 'host',
      lines: [
        const StoryLineEntry(lineIndex: 0, content: 'a'),
        const StoryLineEntry(lineIndex: 1, content: 'b'),
        const StoryLineEntry(lineIndex: 2, content: '', kind: 'divider'),
        const StoryLineEntry(lineIndex: 3, content: 'c'),
        const StoryLineEntry(lineIndex: 4, content: 'd'),
      ],
      sources: {
        3: (storyId: 'child', lineIndex: 0),
        4: (storyId: 'child', lineIndex: 1),
      },
    );
    final art = await container.read(readerStoryArtProvider(key).future);
    expect(art, isNotNull);
    expect(art!.shots.map((s) => (s.kind, s.at, s.number, s.until)).toList(), [
      ('scene', 0, 1, null),
      ('cg', 1, 1, 2),
      ('scene', 3, 2, null),
      ('cg', 4, 1, 5),
    ]);
    expect(pack.infoQueries, 1);
    expect(art.shots[1].segment, isNot(art.shots[3].segment));
  });

  test('no pack, no events or Endfield: no art', () async {
    const lines = [StoryLineEntry(lineIndex: 0, content: 'a')];
    Future<ReaderStoryArt?> art(
      String id,
      _Pack pack,
      List<StoryArtEvent> events,
    ) {
      final container = ProviderContainer(
        overrides: [
          storyArtPackProvider.overrideWith((ref) async => pack),
          storyArtEventsProvider.overrideWith((ref, id) async => events),
        ],
      );
      addTearDown(container.dispose);
      return container.read(
        readerStoryArtProvider(
          (storyId: id, lines: lines, sources: const {}),
        ).future,
      );
    }

    const background = StoryArtEvent(
      storyId: 'a',
      seq: 0,
      at: 0,
      kind: 'background',
      image: 'bg',
    );
    expect(await art('a.txt', _Pack(present: false), [background]), isNull);
    expect(await art('a.txt', _Pack(), []), isNull);
    expect(await art('ef/a', _Pack(), [background]), isNull);
    expect(await art('a.txt', _Pack(), [background]), isNotNull);
  });
}
