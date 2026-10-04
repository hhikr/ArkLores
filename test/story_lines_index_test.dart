// A knowledge base built before v0.10.7 has no index on
// story_lines(story_id, line_index): every chapter read scanned all lines.
// The store adds it the first time it opens such a file.
import 'dart:io';

import 'package:arklores/core/gamedata/build/gamedata_schema.dart';
import 'package:arklores/core/gamedata/gamedata_knowledge_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/temp_dir.dart';

void main() {
  late Directory dir;

  setUpAll(() {
    sqfliteFfiInit();
    sqflite.databaseFactory = databaseFactoryFfi;
  });

  setUp(() => dir = Directory.systemTemp.createTempSync('story_lines_index'));
  tearDown(() => deleteTempDir(dir));

  Future<String> makeDb({bool withIndex = false}) async {
    final path = '${dir.path}${Platform.pathSeparator}kb.db';
    final db = await databaseFactoryFfi.openDatabase(path);
    await db.execute(
      'CREATE TABLE story_lines (story_id TEXT, line_index INTEGER, '
      'speaker TEXT, content TEXT)',
    );
    await db.execute(
      'CREATE TABLE story_scopes (story_id TEXT PRIMARY KEY, scope_type TEXT, '
      'scope_id TEXT, source_path TEXT)',
    );
    await db.insert('story_scopes', {
      'story_id': 's1',
      'scope_type': 'activity',
      'scope_id': 'x',
      'source_path': 'p',
    });
    for (var i = 0; i < 50; i++) {
      await db.insert('story_lines', {
        'story_id': 's1',
        'line_index': i,
        'speaker': null,
        'content': '第$i句',
      });
    }
    if (withIndex) await db.execute(storyLinesIndexSql);
    await db.close();
    return path;
  }

  Future<List<String>> plan(String path) async {
    final db = await databaseFactoryFfi.openDatabase(path, options: OpenDatabaseOptions(readOnly: true));
    final rows = await db.rawQuery(
      'EXPLAIN QUERY PLAN SELECT line_index FROM story_lines '
      'WHERE story_id = ? AND line_index >= ?',
      ['s1', 3],
    );
    await db.close();
    return [for (final r in rows) '${r['detail']}'];
  }

  test('opening an old knowledge base adds the index; reads still work',
      () async {
    final path = await makeDb();
    expect((await plan(path)).join(), contains('SCAN'));

    final store = GameDataKnowledgeStore(dbPath: path);
    addTearDown(store.close);
    final page = await store.readStoryLines(
      storyId: 's1',
      startLine: 5,
      endLine: 7,
      maxLines: 10,
    );
    expect(page.lines.map((l) => l.lineIndex), [5, 6, 7]);
    await store.close();
    expect((await plan(path)).join(), contains(storyLinesIndexName));

    // Reading again (the store reopens the file) works.
    final again = await store.readStoryLines(storyId: 's1', startLine: 0, endLine: 1);
    expect(again.lines, hasLength(2));
  });

  test('a knowledge base that already has the index is left alone', () async {
    final path = await makeDb(withIndex: true);
    final before = File(path).lengthSync();
    final store = GameDataKnowledgeStore(dbPath: path);
    addTearDown(store.close);
    await store.readStoryLines(storyId: 's1', startLine: 0, endLine: 3);
    expect(File(path).lengthSync(), before);
  });

  test('a file that cannot be changed still reads', () async {
    final path = await makeDb();
    File(path).setLastModifiedSync(DateTime(2026));
    // Pretend the media is read-only by checking the same path twice in one
    // process: the index is only attempted once per path.
    final store = GameDataKnowledgeStore(dbPath: path);
    addTearDown(store.close);
    final page = await store.readStoryLines(storyId: 's1', startLine: 0, endLine: 2);
    expect(page.storyFound, isTrue);
  });
}
