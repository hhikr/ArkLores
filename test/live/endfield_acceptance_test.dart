// 0.12: acceptance checks on a real Endfield knowledge base (opt-in: it
// needs the built database).
//
//   $env:ARKLORES_RUN_EF_CHECK='true'
//   $env:ARKLORES_ENDFIELD_DB="$PWD\build\endfield\arklores_endfield_zh.db"
//   flutter test test/live/endfield_acceptance_test.dart
import 'dart:io';

import 'package:arklores/core/gamedata/build/gamedata_db_validator.dart';
import 'package:arklores/core/gamedata/game.dart';
import 'package:arklores/core/library/library_queries.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  final run = Platform.environment['ARKLORES_RUN_EF_CHECK'] == 'true';
  final path = Platform.environment['ARKLORES_ENDFIELD_DB'] ??
      '${Directory.current.path}/build/endfield/arklores_endfield_zh.db';
  late Database db;

  setUpAll(() async {
    if (!run) return;
    sqfliteFfiInit();
    db = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(readOnly: true),
    );
  });
  tearDownAll(() async {
    if (run) await db.close();
  });

  Future<int> count(String sql) async =>
      ((await db.rawQuery(sql)).first.values.first! as num).toInt();

  test('the installer accepts it; it says it is Endfield', () async {
    await validateGameDataDatabase(db);
    final game = await db.rawQuery(
      "SELECT value FROM gamedata_manifest WHERE key = 'game'",
    );
    expect(game.single['value'], 'endfield');
  }, skip: !run,);

  test('every id is in the ef/ namespace', () async {
    for (final (table, column) in [
      ('story_lines', 'story_id'),
      ('collections', 'id'),
      ('collections', 'kind'),
      ('normalized_records', 'id'),
      ('entries', 'raw_id'),
      ('story_catalog', 'story_id'),
    ]) {
      final rows = await db.rawQuery('SELECT DISTINCT $column AS v FROM $table');
      for (final r in rows) {
        expect(gameOfId('${r['v']}'), Game.endfield, reason: '$table.$column ${r['v']}');
      }
    }
  }, skip: !run,);

  test('every story has an entry, a collection on a shelf and a catalog row', () async {
    expect(
      await count(
        'SELECT COUNT(DISTINCT story_id) FROM story_lines WHERE story_id NOT IN '
        "(SELECT raw_id FROM entries WHERE type = 'story')",
      ),
      0,
    );
    expect(
      await count(
        "SELECT COUNT(*) FROM entries e WHERE e.type = 'story' AND NOT EXISTS "
        '(SELECT 1 FROM collections c WHERE c.id = e.collection_id)',
      ),
      0,
    );
    expect(
      await count(
        "SELECT COUNT(*) FROM entries e WHERE e.type = 'story' AND e.raw_id NOT IN "
        '(SELECT story_id FROM story_catalog)',
      ),
      0,
    );
    final kinds = {
      for (final r in await db.rawQuery('SELECT DISTINCT kind FROM collections'))
        '${r['kind']}'.substring(endfieldIdPrefix.length),
    };
    expect(endfieldShelfOrder, containsAll(kinds));
  }, skip: !run,);

  test('no markup, placeholders or gender pairs are left in the text', () async {
    for (final table in ['story_lines', 'normalized_records']) {
      for (final pattern in ['%{F}%', '%{M}%', '%{player}%', '%<@%', '%</>%', r'%\n%']) {
        expect(
          await count("SELECT COUNT(*) FROM $table WHERE content LIKE '$pattern'"),
          0,
          reason: '$table $pattern',
        );
      }
    }
    expect(
      await count("SELECT COUNT(*) FROM story_lines WHERE speaker LIKE '%{%'"),
      0,
    );
  }, skip: !run,);

  test('names read as names: no collection or story named by a raw id', () async {
    expect(
      await count(
        "SELECT COUNT(*) FROM collections WHERE name GLOB '[a-z]*[0-9]*' "
        "AND name NOT GLOB '*[^ -~]*'",
      ),
      0,
    );
    expect(
      await count(
        "SELECT COUNT(*) FROM story_catalog WHERE story_name GLOB '[a-z]*_*'",
      ),
      0,
    );
  }, skip: !run,);

  test('the content is all there (counts of the 2026-10 client)', () async {
    expect(await count("SELECT COUNT(*) FROM entries WHERE type = 'operator'"), greaterThanOrEqualTo(30));
    expect(await count("SELECT COUNT(*) FROM entries WHERE type = 'document'"), greaterThanOrEqualTo(400));
    // One story per mission, place, enemy and message topic (520 in the
    // 2026-10 client), all ~8,400 conversations in them.
    expect(await count('SELECT COUNT(DISTINCT story_id) FROM story_lines'), greaterThanOrEqualTo(400));
    expect(await count("SELECT COUNT(*) FROM story_lines WHERE kind = 'section'"), greaterThanOrEqualTo(8000));
    expect(await count("SELECT COUNT(*) FROM story_lines WHERE kind <> 'section'"), greaterThanOrEqualTo(38000));
    expect(await count("SELECT COUNT(*) FROM collections WHERE kind = 'ef/main'"), greaterThanOrEqualTo(50));
  }, skip: !run,);

  test('a mission reads as one story that opens with a section line', () async {
    expect(
      await count(
        "SELECT COUNT(*) FROM (SELECT collection_id FROM entries WHERE type = 'story' "
        'GROUP BY collection_id HAVING COUNT(*) > 1)',
      ),
      0,
    );
    expect(
      await count(
        "SELECT COUNT(*) FROM story_lines WHERE line_index = 0 AND kind <> 'section'",
      ),
      0,
    );
    // Story ids are missions, places, enemies, topics: not conversations.
    expect(
      await count(
        "SELECT COUNT(DISTINCT story_id) FROM story_lines WHERE story_id GLOB 'ef/dlg_*' "
        "OR story_id GLOB 'ef/radio_*' OR story_id GLOB 'ef/sns_*'",
      ),
      0,
    );
    // Main missions say where they are played.
    expect(
      await count(
        'SELECT COUNT(*) FROM entries e JOIN collections c ON c.id = e.collection_id '
        "WHERE c.kind = 'ef/main' AND e.type = 'mission_intro' AND e.group_name IS NOT NULL",
      ),
      greaterThanOrEqualTo(50),
    );
  }, skip: !run,);

  test('story vectors, when present, cover every story inside its lines', () async {
    final hasVectors = await count(
      "SELECT COUNT(*) FROM sqlite_master WHERE name = 'story_chunk_vectors'",
    );
    if (hasVectors == 0) return;
    expect(
      await count(
        'SELECT COUNT(DISTINCT story_id) FROM story_lines WHERE story_id NOT IN '
        '(SELECT story_id FROM story_chunk_vectors)',
      ),
      0,
    );
    for (final r in await db.rawQuery(
      'SELECT DISTINCT story_id AS v FROM story_chunk_vectors',
    )) {
      expect(gameOfId('${r['v']}'), Game.endfield, reason: '${r['v']}');
    }
    expect(
      await count(
        'SELECT COUNT(*) FROM story_chunk_vectors v WHERE NOT EXISTS '
        '(SELECT 1 FROM story_lines l WHERE l.story_id = v.story_id '
        'AND l.line_index = v.line_start) OR NOT EXISTS '
        '(SELECT 1 FROM story_lines l WHERE l.story_id = v.story_id '
        'AND l.line_index = v.line_end)',
      ),
      0,
    );
  }, skip: !run,);
}
