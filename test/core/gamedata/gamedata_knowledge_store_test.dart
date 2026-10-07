// The read side of the knowledge base: upgrading an old file on open, and
// finding the collections a question names. (The search paths are tested
// through the tools that use them.)
import 'dart:io';

import 'package:arklores/core/gamedata/build/gamedata_schema.dart';
import 'package:arklores/core/gamedata/gamedata_knowledge_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/sqlite.dart';
import '../../support/temp_dir.dart';
import '../../support/two_activities_fixture.dart';

void main() {
  late Directory dir;

  setUpAll(useSqfliteFfi);
  setUp(() => dir = Directory.systemTemp.createTempSync('knowledge_store'));
  tearDown(() => deleteTempDir(dir));

  // A knowledge base built before v0.10.7 has no index on
  // story_lines(story_id, line_index): every chapter read scanned all lines.
  // The store adds it the first time it opens such a file.
  group('a knowledge base without the story_lines index', () {
    /// The old layout on purpose: only the two tables a read needs, and the
    /// index only when [withIndex].
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
        await db.insert('story_lines',
            {'story_id': 's1', 'line_index': i, 'content': '第$i句'},);
      }
      if (withIndex) await db.execute(storyLinesIndexSql);
      await db.close();
      return path;
    }

    Future<String> plan(String path) async {
      final db = await databaseFactoryFfi.openDatabase(path,
          options: OpenDatabaseOptions(readOnly: true),);
      final rows = await db.rawQuery(
        'EXPLAIN QUERY PLAN SELECT line_index FROM story_lines '
        'WHERE story_id = ? AND line_index >= ?',
        ['s1', 3],
      );
      await db.close();
      return [for (final r in rows) '${r['detail']}'].join();
    }

    test('gets the index on open; reads still work', () async {
      final path = await makeDb();
      expect(await plan(path), contains('SCAN'));

      final store = GameDataKnowledgeStore(dbPath: path);
      addTearDown(store.close);
      final page = await store.readStoryLines(
          storyId: 's1', startLine: 5, endLine: 7, maxLines: 10,);
      expect(page.lines.map((l) => l.lineIndex), [5, 6, 7]);
      await store.close();
      expect(await plan(path), contains(storyLinesIndexName));

      // Reading again (the store reopens the file) works.
      final again =
          await store.readStoryLines(storyId: 's1', startLine: 0, endLine: 1);
      expect(again.lines, hasLength(2));
    });

    test('a file that already has it is left alone', () async {
      final path = await makeDb(withIndex: true);
      final before = File(path).lengthSync();
      final store = GameDataKnowledgeStore(dbPath: path);
      addTearDown(store.close);
      await store.readStoryLines(storyId: 's1', startLine: 0, endLine: 3);
      expect(File(path).lengthSync(), before);
    });
  });

  test('collections named in a question are found verbatim', () async {
    final path = '${dir.path}/two.db';
    await createTwoActivitiesDb(path);
    final store = GameDataKnowledgeStore(dbPath: path);
    addTearDown(store.close);
    final targets = await store.namedStoryTargets('凯伦在远方之路里做了什么');
    expect(targets.single.collectionId, 'act_new');
    expect(targets.single.releaseMonth, '2024-06');
    // Chapter names shorter than 3 characters only count inside 《》.
    expect(await store.namedStoryTargets('关于启程的问题'), isEmpty);
    expect(
      (await store.namedStoryTargets('《启程》讲了什么')).single.storyId,
      'activities/act_new/level_act_new_01.txt',
    );
  });
}
