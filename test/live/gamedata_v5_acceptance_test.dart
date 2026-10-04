import 'dart:io';

import 'package:arklores/core/gamedata/gamedata_knowledge_store.dart';
import 'package:arklores/core/gamedata/story_vectors.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Opt-in acceptance check of a freshly built schema 5 knowledge base.
///
///   $env:ARKLORES_RUN_DB_CHECK='true'
///   $env:ARKLORES_GAMEDATA_DB="$PWD\build\gamedata_v5\arklores_gamedata_zh.db"
///   flutter test test/live/gamedata_v5_acceptance_test.dart
///
/// It checks structure only (no model calls): bindings point at rows,
/// owners exist, vectors have valid line ranges and load through the app's
/// own index loader, and the app reader returns line kinds.
void main() {
  final enabled = Platform.environment['ARKLORES_RUN_DB_CHECK'] == 'true';
  final dbPath = Platform.environment['ARKLORES_GAMEDATA_DB'] ?? '';

  setUpAll(() {
    sqfliteFfiInit();
    sqflite.databaseFactory = databaseFactoryFfi;
  });

  test('schema 5 knowledge base is consistent', () async {
    final db = await databaseFactoryFfi.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(readOnly: true),
    );
    addTearDown(db.close);

    Future<int> count(String sql) async =>
        (await db.rawQuery(sql)).single.values.first! as int;

    expect(
      (await db.rawQuery(
        "SELECT value FROM gamedata_manifest WHERE key = 'schema_version'",
      ))
          .single['value'],
      '5',
    );
    expect(
      await count(
        'SELECT COUNT(*) FROM entry_links l WHERE '
        'NOT EXISTS (SELECT 1 FROM entries e WHERE e.id = l.src) '
        'OR NOT EXISTS (SELECT 1 FROM entries e WHERE e.id = l.dst)',
      ),
      0,
      reason: 'every binding refers to two entries',
    );
    expect(
      await count(
        'SELECT COUNT(*) FROM entries e WHERE e.collection_id IS NOT NULL '
        'AND NOT EXISTS (SELECT 1 FROM collections c WHERE c.id = e.collection_id)',
      ),
      0,
      reason: 'every owner exists',
    );
    expect(
      await count(
        'SELECT COUNT(*) FROM normalized_records WHERE entry_id IS NULL',
      ),
      0,
      reason: 'every record belongs to an entry',
    );
    expect(
      await count(
        'SELECT COUNT(*) FROM story_lines s WHERE NOT EXISTS '
        '(SELECT 1 FROM entries e WHERE e.id = \'story:\' || s.story_id)',
      ),
      0,
      reason: 'every story has an entry',
    );
    expect(
      await count(
        'SELECT COUNT(*) FROM entries WHERE type = \'enemy\' AND '
        'NOT EXISTS (SELECT 1 FROM entry_links l WHERE l.src = entries.id)',
      ),
      lessThan(300),
      reason: 'most enemies are bound to a stage',
    );

    // Gameplay text stays out.
    expect(
      await count(
        "SELECT COUNT(*) FROM normalized_records WHERE content_type = 'enemy_profile' "
        "AND section <> '敌人'",
      ),
      0,
    );

    // Vectors.
    final index = await StoryVectorIndex.load(db);
    expect(index, isNotNull);
    expect(index!.dims, 512);
    expect(
      await count(
        'SELECT COUNT(*) FROM story_chunk_vectors v WHERE v.line_start > v.line_end '
        'OR v.line_end > (SELECT MAX(line_index) FROM story_lines l WHERE l.story_id = v.story_id)',
      ),
      0,
      reason: 'vector ranges lie inside their story',
    );

    // The app reader returns the line kinds.
    final sample = await db.rawQuery(
      "SELECT story_id FROM story_lines WHERE kind = 'subtitle' "
      'GROUP BY story_id ORDER BY COUNT(*) DESC LIMIT 1',
    );
    final store = GameDataKnowledgeStore(dbPath: dbPath);
    addTearDown(store.close);
    final page = await store.readStoryLines(
      storyId: '${sample.single['story_id']}',
      maxLines: 60,
    );
    expect(page.lines.map((l) => l.kind), contains('subtitle'));
  }, skip: enabled ? false : 'set ARKLORES_RUN_DB_CHECK=true',);
}
