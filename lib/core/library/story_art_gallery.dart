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

/// One speaker, whatever portraits they speak in: the list of everyone is
/// not the list of answers' names, so single-character names and blocked
/// names are here too.
class GalleryPortrait {
  const GalleryPortrait(this.speaker, this.sprite, this.lines);
  final String speaker, sprite;
  final int lines;
}

/// What the search looks in, beyond what the page shows. Every picture is
/// listed once, under the story it first appears in, and is found by all the
/// stories it appears in.
class GallerySearchIndex {
  const GallerySearchIndex({
    this.storyLabels = const {},
    this.storySpeakers = const {},
    this.artStories = const {},
    this.artTitles = const {},
  });

  /// A story's own name and its collection's.
  final Map<String, String> storyLabels;
  final Map<String, Set<String>> storySpeakers;

  /// By (kind as the gallery has it: scene or cg, image).
  final Map<(String, String), List<String>> artStories;
  final Map<String, String> artTitles;
}

class StoryArtGallery {
  const StoryArtGallery({
    this.available = false,
    this.groups = const [],
    this.portraits = const [],
    this.search = const GallerySearchIndex(),
  });
  final bool available;
  final List<GalleryArtGroup> groups;
  final List<GalleryPortrait> portraits;
  final GallerySearchIndex search;
  List<CollectionArtShot> shots(String kind) => [
        for (final group in groups)
          ...group.shots.where((a) => a.shot.kind == kind),
      ];

  /// What [query] finds; the same words work on all three kinds of picture.
  GalleryMatches matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return GalleryMatches._(this, '', const {}, const {});
    bool has(String text) => text.toLowerCase().contains(q);
    final byLabel = <String>{
      for (final entry in search.storyLabels.entries)
        if (has(entry.value)) entry.key,
    };
    final bySpeaker = <String>{
      for (final entry in search.storySpeakers.entries)
        if (entry.value.any(has)) entry.key,
    };
    return GalleryMatches._(this, q, byLabel, bySpeaker);
  }
}

class GalleryMatches {
  GalleryMatches._(this._gallery, this._query, this._byLabel, this._bySpeaker);
  final StoryArtGallery _gallery;
  final String _query;

  /// The stories whose name or collection has the words, and those with a
  /// speaker who does.
  final Set<String> _byLabel, _bySpeaker;

  bool _has(String text) => text.toLowerCase().contains(_query);

  /// A name that has the words comes before one found through its stories,
  /// the exact name first.
  List<GalleryPortrait> portraits() {
    final all = _gallery.portraits;
    if (_query.isEmpty) return all;
    final exact = <GalleryPortrait>[], named = <GalleryPortrait>[];
    for (final portrait in all) {
      if (portrait.speaker.toLowerCase() == _query) {
        exact.add(portrait);
      } else if (_has(portrait.speaker)) {
        named.add(portrait);
      }
    }
    final speakers = <String>{
      for (final id in _byLabel) ...?_gallery.search.storySpeakers[id],
    };
    return [
      ...exact,
      ...named,
      for (final portrait in all)
        if (!_has(portrait.speaker) && speakers.contains(portrait.speaker))
          portrait,
    ];
  }

  bool art(CollectionArtShot art) {
    if (_query.isEmpty) return true;
    final image = art.shot.image;
    if (_has(image) || _has(_gallery.search.artTitles[image] ?? '')) {
      return true;
    }
    final stories =
        _gallery.search.artStories[(art.shot.kind, image)] ?? [art.storyId];
    return stories
        .any((id) => _byLabel.contains(id) || _bySpeaker.contains(id));
  }

  /// [kind]'s groups, holding only what was found.
  List<GalleryArtGroup> groups(String kind) => [
        for (final group in _gallery.groups)
          if ([
            for (final a in group.shots)
              if (a.shot.kind == kind && art(a)) a,
          ]
              case final shots when shots.isNotEmpty)
            GalleryArtGroup(group.id, group.title, shots),
      ];
}

Future<bool> _hasTable(DatabaseExecutor db, String name) async =>
    (await db.rawQuery(
      "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?",
      [name],
    ))
        .isNotEmpty;

Future<List<GalleryPortrait>> galleryPortraits(DatabaseExecutor db) async {
  if (!await _hasTable(db, 'speaker_names')) return [];
  return [
    for (final row in await db.query(
      'speaker_names',
      columns: ['speaker', 'top_sprite', 'lines'],
      orderBy: 'lines DESC, speaker ASC',
    ))
      GalleryPortrait(
        row['speaker'] as String,
        row['top_sprite'] as String,
        row['lines'] as int,
      ),
  ];
}

Future<GallerySearchIndex> _searchIndex(
  DatabaseExecutor db,
  StoryArtPack pack,
  List<StoryCatalogEntry> catalog,
) async {
  final artStories = <(String, String), List<String>>{};
  for (final row in await db.rawQuery(
    '''
    SELECT DISTINCT kind, image, story_id FROM story_art_events
    WHERE kind IN ('background', 'cg') AND image IS NOT NULL AND image != ''
    ''',
  )) {
    final kind = row['kind'] == 'background' ? 'scene' : 'cg';
    (artStories[(kind, row['image'] as String)] ??= [])
        .add(row['story_id'] as String);
  }
  final storySpeakers = <String, Set<String>>{};
  if (await _hasTable(db, 'story_lines')) {
    for (final row in await db.rawQuery(
      '''
      SELECT DISTINCT story_id, TRIM(speaker) AS speaker FROM story_lines
      WHERE speaker IS NOT NULL AND TRIM(speaker) != ''
      ''',
    )) {
      (storySpeakers[row['story_id'] as String] ??= <String>{})
          .add(row['speaker'] as String);
    }
  }
  return GallerySearchIndex(
    storyLabels: {
      for (final story in catalog)
        story.storyId: '${story.collectionLabel} ${story.label}',
    },
    storySpeakers: storySpeakers,
    artStories: artStories,
    artTitles: await pack.artTitles(),
  );
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
    search: await _searchIndex(db, pack, catalog),
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
