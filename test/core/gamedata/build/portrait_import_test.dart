import 'dart:io';
import 'dart:typed_data';

import 'package:arklores/core/gamedata/build/arknights_importer.dart';
import 'package:arklores/core/gamedata/build/portrait_index.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../../tools/build_portrait_index.dart' as tool;
import '../../../support/gamedata_fixture.dart';

void main() {
  sqfliteFfiInit();
  late Directory dir;
  late Database db;
  late String dbPath;
  late ArknightsImporter importer;
  const relative = 'zh_CN/gamedata/story/s.txt';
  Future<void> write(String path, String text) async {
    final f = File(p.join(dir.path, path));
    await f.parent.create(recursive: true);
    await f.writeAsString(text);
  }

  Future<void> addVector() => db.insert('story_chunk_vectors', {
        'chunk_id': 's.txt#0-0',
        'story_id': 's.txt',
        'line_start': 0,
        'line_end': 0,
        'scale': 0.5,
        'vec': Uint8List.fromList([1, 2, 3]),
      });

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('portrait_import_');
    dbPath = p.join(dir.path, 'test.db');
    db = await createGameDataDb(dbPath, vectors: true);
    importer = ArknightsImporter(
        sourceDir: dir, db: db, stats: BuildStats(), storyLimit: 0,);
  });
  tearDown(() async {
    if (db.isOpen) await db.close();
    await dir.delete(recursive: true);
  });

  test('story imports align line indices, replace portraits and delete them',
      () async {
    await write(relative,
        '[Character(name="char_test#2")]\n[name="Name"]text\nnarration',);
    await importer.importStoryFile(relative);
    await addVector();
    expect((await db.query(storyLinePortraitsTable)).single, {
      'story_id': 's.txt',
      'line_index': 0,
      'sprite': r'char_test#2$1',
    });
    await write(relative, '[name="Name"]text\nnarration');
    // The comparison intentionally excludes portraits so vectors survive.
    final result = await importer.reimportChangedStories();
    expect(result, isEmpty);
    expect((await db.query('story_chunk_vectors')).single['vec'], [1, 2, 3]);
    await importer.importStoryFile(relative);
    expect(await db.query(storyLinePortraitsTable), isEmpty);
    await write(relative, '[Character(name="char_test#2")]\n[name="Name"]text');
    await importer.importStoryFile(relative);
    await deleteStoryRows(db, relative);
    expect(await db.query(storyLinePortraitsTable), isEmpty);
    expect(await db.query('story_lines'), isEmpty);
    expect(await db.query('story_chunk_vectors'), isEmpty);
  });

  test('art events follow changed story text without changing the signature', () async {
    const other = 'zh_CN/gamedata/story/other.txt';
    await write(relative, '[Background(image="first")]\nOne');
    await write(other, '[Image(image="cg")]\nOther');
    await importer.importStoryFile(relative);
    await importer.importStoryFile(other);
    await addVector();
    final original = await db.query('story_art_events', orderBy: 'story_id, seq');
    expect(original.map((row) => row['image']), ['cg', 'first']);
    await write(relative, '[Background(image="new")]\nOne');
    expect(await importer.reimportChangedStories(), isEmpty);
    expect(await db.query('story_art_events', orderBy: 'story_id, seq'), original);
    expect(await db.query('story_chunk_vectors'), hasLength(1));
    await write(relative, '[Background(image="new")]\nChanged');
    expect(await importer.reimportChangedStories(), [relative]);
    final rows = await db.query('story_art_events', orderBy: 'story_id, seq');
    expect(rows.map((row) => row['image']), ['cg', 'new']);
    expect(await db.query('story_chunk_vectors'), isEmpty);
  });

  test(
      'backfill preserves unrelated tables, skips mismatches and is repeatable',
      () async {
    await write(relative, '[Background(image="art")][Character(name="char_test#2")]\n[name="Name"]text');
    await importer.importStoryFile(relative);
    await db.delete('story_art_events');
    await addVector();
    await write('zh_CN/gamedata/story/mismatch.txt', '[name="Other"]before');
    await importer.importStoryFile('zh_CN/gamedata/story/mismatch.txt');
    await write('zh_CN/gamedata/story/mismatch.txt', '[name="Other"]after');
    await write('zh_CN/gamedata/story/absent.txt', '[name="Other"]new');
    await write('zh_CN/gamedata/story/[uc]info/stub.txt', '[name="Other"]stub');
    await db.insert(storyLinePortraitsTable, {
      'story_id': 'mismatch.txt',
      'line_index': 0,
      'sprite': r'avg_old#1$1',
    });
    await db.delete(storyLinePortraitsTable,
        where: 'story_id=?', whereArgs: ['s.txt'],);
    final before = await db.query('story_lines');
    final vectors = await db.query('story_chunk_vectors');
    final manifest = await db.query('gamedata_manifest');
    await db.close();
    final args = ['--db=$dbPath', '--source=${dir.path}'];
    await tool.main(args);
    db = await databaseFactoryFfi.openDatabase(dbPath);
    final portraits = await db.query(storyLinePortraitsTable);
    expect((await db.query('story_art_events')).single['image'], 'art');
    expect(portraits.length, 2);
    expect(portraits.firstWhere((p) => p['story_id'] == 's.txt')['sprite'],
        r'char_test#2$1',);
    expect(
        portraits.firstWhere((p) => p['story_id'] == 'mismatch.txt')['sprite'],
        r'avg_old#1$1',);
    expect(await db.query('story_lines'), before);
    expect(await db.query('story_chunk_vectors'), vectors);
    expect(
        await db.rawQuery(
            "SELECT * FROM gamedata_manifest WHERE substr(key,1,9) <> 'portrait_' AND substr(key,1,10) <> 'story_art_'",),
        manifest,);
    final first = await db.query(speakerNamesTable);
    await db.close();
    await tool.main(args);
    db = await databaseFactoryFfi.openDatabase(dbPath);
    expect(await db.query(storyLinePortraitsTable), portraits);
    expect(await db.query(speakerNamesTable), first);
  });
}
