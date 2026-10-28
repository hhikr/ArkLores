import 'dart:io';

import 'package:arklores/core/gamedata/build/portrait_index.dart';
import 'package:arklores/core/gamedata/build/story_art_index.dart';
import 'package:arklores/core/gamedata/story_art_pack.dart';
import 'package:arklores/core/gamedata/story_catalog.dart';
import 'package:arklores/core/library/story_art_gallery.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/gamedata_fixture.dart';
import '../../support/sqlite.dart';
import '../../support/story_art_pack_fixture.dart';
import '../../support/temp_dir.dart';

class _TimedDatabase implements DatabaseExecutor {
  _TimedDatabase(this.db);
  final Database db;
  final times = <String, int>{};
  @override
  Future<List<Map<String, Object?>>> rawQuery(String sql,
      [List<Object?>? args,]) async {
    final timer = Stopwatch()..start();
    final rows = await db.rawQuery(sql, args);
    if (sql.trimLeft().startsWith('WITH')) {
      times['art_sql'] = timer.elapsedMicroseconds;
    }
    if (sql.contains('FROM portrait_groups g')) {
      times['portrait_sql'] = timer.elapsedMicroseconds;
    }
    return rows;
  }

  @override
  Future<List<Map<String, Object?>>> query(
    String table, {
    bool? distinct,
    List<String>? columns,
    String? where,
    List<Object?>? whereArgs,
    String? groupBy,
    String? having,
    String? orderBy,
    int? limit,
    int? offset,
  }) async {
    final timer = Stopwatch()..start();
    final rows = await db.query(table,
        distinct: distinct,
        columns: columns,
        where: where,
        whereArgs: whereArgs,
        groupBy: groupBy,
        having: having,
        orderBy: orderBy,
        limit: limit,
        offset: offset,);
    times[table] = timer.elapsedMicroseconds;
    return rows;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TimedPack extends StoryArtPack {
  _TimedPack(super.path);
  int infoMicros = 0;
  @override
  Future<Map<(String, String), StoryArtInfo>> artInfo(
      Iterable<(String, String)> keys,) async {
    final timer = Stopwatch()..start();
    final info = await super.artInfo(keys);
    infoMicros = timer.elapsedMicroseconds;
    return info;
  }
}

void main() {
  setUpAll(useSqfliteFfi);
  test('release order, first occurrence, base images and portrait names',
      () async {
    final dir = await Directory.systemTemp.createTemp('gallery');
    final db = await createGameDataDb(inMemoryDatabasePath, catalog: true);
    final file = await createStoryArtPack(dir);
    final packDb = await databaseFactoryFfi.openDatabase(file.path);
    await packDb
        .rawUpdate("UPDATE art_images SET solid = 1 WHERE image_id = 'tall'");
    await packDb.execute("INSERT INTO art_images SELECT category, 'scene/cg', "
        "width, height, solid, webp FROM art_images WHERE image_id = 'cg'");
    await packDb.close();
    final pack = StoryArtPack(file.path);
    try {
      await db.execute(portraitGroupsDdl);
      await db.execute(speakerPortraitsDdl);
      await ensureStoryArtTable(db);
      for (final (id, time) in [('z', 100), ('a', 200)]) {
        await db.insert(
          'story_catalog',
          StoryCatalogEntry(
            storyId: id,
            collectionId: id,
            collectionName: id,
            collectionType: 'ACTIVITY',
            storySort: 0,
            startTime: time,
          ).toRow(),
        );
      }
      for (final (story, images) in [
        ('a', ['cg', 'item']),
        ('z', ['cg', 'cg', 'tall', 'absent', 'scene', 'scene/cg']),
      ]) {
        for (final (i, image) in images.indexed) {
          await db.insert('story_art_events', {
            'story_id': story,
            'seq': i,
            'at_line': i + 2,
            'kind': image == 'scene' ? 'background' : 'cg',
            'image': image,
            if (image == 'scene/cg') 'layout': 'row',
          });
        }
      }
      for (final (id, lines) in [('g', 20), ('h', 10)]) {
        await db.insert('portrait_groups', {
          'group_id': id,
          'lines': lines,
          'speakers': 2,
          'sprites': 1,
          'top_sprite': 'same',
        });
        for (final (name, count) in [('Beta', 2), ('Alpha', 8)]) {
          await db.insert('speaker_portraits', {
            'group_id': id,
            'speaker': name,
            'lines': count,
            'stories': 1,
            'top_sprite': 'patch',
          });
        }
      }
      final result = await readStoryArtGallery(db, pack);
      expect(result.groups.map((g) => g.id), ['z', 'a']);
      expect(result.shots('cg').map((a) => a.shot.image),
          ['cg', 'scene/cg', 'item'],);
      expect(result.shots('cg')[1].shot.layout, 'row');
      expect(result.shots('cg').first.storyId, 'z');
      expect(result.shots('cg').first.shot.at, 2);
      expect(result.shots('scene').single.shot.image, 'scene');
      expect(result.shots('cg').every((a) => a.shot.layers.isEmpty), isTrue);
      expect(result.portraits.map((p) => p.id), ['g', 'h']);
      expect(result.portraits.first.names, ['Alpha', 'Beta']);
      expect(result.portraits.first.sprite, 'same');
      await db.execute('DROP TABLE story_catalog');
      final withoutCatalog = await readStoryArtGallery(db, pack);
      expect(withoutCatalog.groups.map((g) => g.id), ['a', 'z']);
      expect(
        (await readStoryArtGallery(db, StoryArtPack('${dir.path}/missing')))
            .available,
        isFalse,
      );
      await db.execute('DROP TABLE speaker_portraits');
      expect(await galleryPortraits(db), isEmpty);
      await db.execute('DROP TABLE portrait_groups');
      expect((await readStoryArtGallery(db, pack)).available, isFalse);
    } finally {
      await pack.close();
      await db.close();
      await deleteTempDir(dir);
    }
  });

  test('old schema is empty', () async {
    final db = await createGameDataDb(inMemoryDatabasePath);
    final dir = await Directory.systemTemp.createTemp('gallery-old');
    final pack = StoryArtPack((await createStoryArtPack(dir)).path);
    try {
      expect(await galleryPortraits(db), isEmpty);
      expect((await readStoryArtGallery(db, pack)).groups, isEmpty);
    } finally {
      await db.close();
      await pack.close();
      await deleteTempDir(dir);
    }
  });

  test(
    'real database query timings',
    () async {
      final db = await databaseFactoryFfi.openDatabase(
        File('build/gamedata_portraits/arklores_gamedata_zh.db').absolute.path,
        options: OpenDatabaseOptions(readOnly: true),
      );
      final pack = _TimedPack(
        File('build/story_art/arklores_story_art_zh.db').absolute.path,
      );
      try {
        final timer = Stopwatch()..start();
        final timedDb = _TimedDatabase(db);
        final result = await readStoryArtGallery(timedDb, pack);
        debugPrint('GALLERY ${timer.elapsedMilliseconds} ms; '
            '${result.portraits.length} portraits; ${result.shots('scene').length} backgrounds; '
            '${result.shots('cg').length} CGs');
        debugPrint(
            'QUERY MICROSECONDS ${timedDb.times}; pack_art_info ${pack.infoMicros}',);
        timer.reset();
        await galleryPortraits(db);
        debugPrint('PORTRAITS ${timer.elapsedMilliseconds} ms');
        timer.reset();
        await readStoryArtGallery(db, pack);
        debugPrint('GALLERY WARM ${timer.elapsedMilliseconds} ms');
        expect(result.available, isTrue);
        expect(result.shots('cg'), isNotEmpty);
      } finally {
        await db.close();
        await pack.close();
      }
    },
    skip: Platform.environment['T7_REAL_DATA'] != 'true',
  );
}
