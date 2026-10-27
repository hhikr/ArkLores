import 'dart:io';

import 'package:arklores/core/agent/agent_provider.dart';
import 'package:arklores/core/gamedata/build/story_art_index.dart';
import 'package:arklores/core/gamedata/gamedata_installer.dart';
import 'package:arklores/core/gamedata/gamedata_knowledge_store.dart';
import 'package:arklores/core/gamedata/gamedata_provider.dart';
import 'package:arklores/core/gamedata/story_art_pack.dart';
import 'package:arklores/core/gamedata/story_art_pack_provider.dart';
import 'package:arklores/core/library/collection_story_art.dart';
import 'package:arklores/core/library/library_provider.dart';
import 'package:arklores/core/library/library_queries.dart';
import 'package:arklores/core/library/story_art.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/gamedata_fixture.dart';
import '../../support/sqlite.dart';
import '../../support/temp_dir.dart';

class _Absent extends StoryArtPack {
  _Absent() : super('absent');
  @override
  Future<bool> get installed async => false;
}

class _Present extends _Absent {
  @override
  Future<bool> get installed async => true;
  @override
  Future<Map<(String, String), StoryArtInfo>> artInfo(
          Iterable<(String, String)> keys,) async =>
      {
        for (final key in keys) key: StoryArtInfo(160, 90, 'background', false),
      };
}

void main() {
  setUpAll(useSqfliteFfi);
  test('provider reads production events across stories in collection order',
      () async {
    final dir = await Directory.systemTemp.createTemp('collection-art-data');
    final db = await createGameDataDb('${dir.path}/kb.db');
    await ensureStoryArtTable(db);
    for (final id in ['a', 'b']) {
      await db.insert('story_art_events', {
        'story_id': id,
        'seq': 0,
        'at_line': 4,
        'kind': 'background',
        'image': id,
      });
    }
    final store = GameDataKnowledgeStore(dbPath: db.path);
    final c = ProviderContainer(
      overrides: [
        sharedGameDataStoreProvider.overrideWithValue(store),
        gameDataInstallStatusProvider.overrideWith((ref) async =>
            GameDataInstallStatus(
                installed: true,
                dbPath: db.path,
                bytes: 1,
                manifest: const {},),),
        collectionStoriesProvider.overrideWith(
          (ref, _) async => const [
            LibraryEntry(id: 'story:b', rawId: 'b', type: 'story', name: 'B'),
            LibraryEntry(id: 'story:a', rawId: 'a', type: 'story', name: 'A'),
          ],
        ),
        storyArtPackProvider.overrideWith((ref) async => _Present()),
      ],
    );
    try {
      final result =
          await c.read(collectionStoryArtProvider('collection').future);
      expect(result.map((a) => a.storyId), ['b', 'a']);
      expect(result.every((a) => a.shot.at == 4 && !a.shot.missing), true);
      expect(await readStoryArtEvents(db, []), isEmpty);
    } finally {
      c.dispose();
      await store.close();
      await db.close();
      await deleteTempDir(dir);
    }
  });
  const stories = [
    LibraryEntry(id: 'story:b', rawId: 'b', type: 'story', name: 'Second'),
    LibraryEntry(id: 'story:a', rawId: 'a', type: 'story', name: 'First'),
  ];
  test(
      'collection order, cross-story deduplication and distinct layer transforms',
      () {
    final art = groupCollectionArt(
      stories,
      const [
        StoryArtEvent(
            storyId: 'a', seq: 0, at: 0, kind: 'background', image: 'shared',),
        StoryArtEvent(storyId: 'a', seq: 1, at: 1, kind: 'cg', image: 'unique'),
        StoryArtEvent(
            storyId: 'b', seq: 0, at: 0, kind: 'background', image: 'shared',),
        StoryArtEvent(
            storyId: 'b', seq: 1, at: 1, kind: 'item', image: 'layer',),
        StoryArtEvent(
            storyId: 'b', seq: 2, at: 2, kind: 'item', image: 'layer', x: 20,),
      ],
      (_, __) => false,
    );
    expect(art.map((a) => a.storyId), ['b', 'b', 'b', 'a']);
    expect(art.last.shot.image, 'unique');
    expect(art[1].shot.layers.single.x, 0);
    expect(art[2].shot.layers.single.x, 20);
  });
  test('missing pack and Endfield need no database', () async {
    final c = ProviderContainer(overrides: [
      storyArtPackProvider.overrideWith((ref) async => _Absent()),
    ],);
    addTearDown(c.dispose);
    expect(
        await c.read(collectionStoryArtProvider('collection').future), isEmpty,);
    expect(await c.read(collectionStoryArtProvider('ef/collection').future),
        isEmpty,);
  });
}
