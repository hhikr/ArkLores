import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_common/sqlite_api.dart';

import '../agent/agent_provider.dart' show gameStoreProvider;
import '../gamedata/game.dart';
import '../gamedata/gamedata_provider.dart';
import '../gamedata/story_art_pack.dart';
import '../gamedata/story_art_pack_provider.dart';
import '../gamedata/story_catalog.dart';
import 'collection_story_art.dart';
import 'story_art.dart';

class GalleryArtGroup {
  const GalleryArtGroup(this.id, this.title, this.shots);
  final String id, title;
  final List<CollectionArtShot> shots;
}

class GalleryPortrait {
  const GalleryPortrait(this.id, this.sprite, this.names, this.lines);
  final String id, sprite;
  final List<String> names;
  final int lines;
}

class StoryArtGallery {
  const StoryArtGallery({
    this.available = false,
    this.groups = const [],
    this.portraits = const [],
  });
  final bool available;
  final List<GalleryArtGroup> groups;
  final List<GalleryPortrait> portraits;
  List<CollectionArtShot> shots(String kind) => [
        for (final group in groups)
          ...group.shots.where((a) => a.shot.kind == kind),
      ];
}

Future<bool> _hasTable(DatabaseExecutor db, String name) async =>
    (await db.rawQuery(
      "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?",
      [name],
    ))
        .isNotEmpty;

Future<List<GalleryPortrait>> galleryPortraits(DatabaseExecutor db) async {
  if (!await _hasTable(db, 'portrait_groups') ||
      !await _hasTable(db, 'speaker_portraits')) {
    return [];
  }
  final rows = await db.rawQuery('''
    SELECT g.group_id, g.top_sprite, g.lines, p.speaker
    FROM portrait_groups g JOIN speaker_portraits p ON p.group_id = g.group_id
    ORDER BY g.lines DESC, g.group_id, p.lines DESC, p.speaker
  ''');
  final groups = <String, List<Map<String, Object?>>>{};
  for (final row in rows) {
    (groups[row['group_id'] as String] ??= []).add(row);
  }
  return [
    for (final entry in groups.entries)
      GalleryPortrait(
        entry.key,
        entry.value.first['top_sprite'] as String,
        [for (final row in entry.value) row['speaker'] as String],
        entry.value.first['lines'] as int,
      ),
  ];
}

Future<StoryArtGallery> readStoryArtGallery(
  DatabaseExecutor db,
  StoryArtPack pack,
) async {
  if (!await pack.installed ||
      !await _hasTable(db, 'story_art_events') ||
      !await _hasTable(db, 'portrait_groups')) {
    return const StoryArtGallery();
  }
  final catalog = <StoryCatalogEntry>[];
  if (await _hasTable(db, 'story_catalog')) {
    // Synopses are long and irrelevant to the gallery's order and labels.
    final columns = (await db.rawQuery('PRAGMA table_info(story_catalog)'))
        .map((row) => row['name'] as String)
        .where((name) => name != 'synopsis' && name != 'synopsis_path')
        .toList();
    catalog.addAll((await db.query('story_catalog', columns: columns))
        .map(StoryCatalogEntry.fromRow),);
  }
  catalog.sort((a, b) {
    final order =
        compareStoryReleaseKeys(storyReleaseKey(a), storyReleaseKey(b));
    return order != 0 ? order : a.storyId.compareTo(b.storyId);
  });
  final byId = {for (final story in catalog) story.storyId: story};
  final orderRows = [
    for (final (i, story) in catalog.indexed)
      "('${story.storyId.replaceAll("'", "''")}', $i)",
  ].join(',');
  // Pass the shared Dart release order to SQLite rather than duplicating it.
  // SQLite takes bare columns from the single MIN's row. Its key is unique
  // per event, so this also works on Android SQLite without window/JSON support.
  final rows = await db.rawQuery('''
    WITH story_order(story_id, release_order) AS (
      ${orderRows.isEmpty ? 'SELECT NULL, 0 WHERE 0' : 'VALUES $orderRows'}
    ), ordered AS (
      SELECT e.*, o.release_order
      FROM story_order o CROSS JOIN story_art_events e
      WHERE e.story_id = o.story_id
      UNION ALL
      SELECT e.*, ? AS release_order FROM story_art_events e
      WHERE e.story_id NOT IN (SELECT story_id FROM story_order)
    ) SELECT e.*, MIN(printf('%010d/%s/%010d/%010d',
        release_order, story_id, at_line, seq)) AS first_occurrence
    FROM ordered e
    WHERE e.kind IN ('background', 'cg') AND e.image IS NOT NULL AND e.image != ''
    GROUP BY e.kind, e.image
    ORDER BY release_order, story_id, at_line, seq
  ''', [catalog.length],);
  final info = await pack.artInfo([
    for (final row in rows) (row['image'] as String, row['kind'] as String),
  ]);
  final groups = <String, List<CollectionArtShot>>{};
  final titles = <String, String>{};
  for (final row in rows) {
    final image = row['image'] as String;
    final kind = row['kind'] as String;
    final art = info[(image, kind)];
    if (art == null || art.solid) continue;
    final id = row['story_id'] as String;
    final story = byId[id];
    final groupId = story?.collectionId ?? id;
    titles[groupId] = story?.collectionLabel ?? id;
    (groups[groupId] ??= []).add(
      CollectionArtShot(
        id,
        story?.label ?? id,
        StoryArtShot(
          kind: kind == 'background' ? 'scene' : 'cg',
          image: image,
          at: row['at_line'] as int,
          layout: row['layout'] as String?,
        ),
      ),
    );
  }
  return StoryArtGallery(
    available: true,
    groups: [
      for (final entry in groups.entries)
        GalleryArtGroup(entry.key, titles[entry.key]!, entry.value),
    ],
    portraits: await galleryPortraits(db),
  );
}

final storyArtGalleryProvider =
    FutureProvider.autoDispose<StoryArtGallery>((ref) async {
  final pack = await ref.watch(storyArtPackProvider.future);
  await ref.watch(gameDataInstallStatusProvider.future);
  return await ref.watch(gameStoreProvider(Game.arknights)).withDatabase(
            (db) => readStoryArtGallery(db, pack),
          ) ??
      const StoryArtGallery();
});
