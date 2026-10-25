import 'package:arklores/core/gamedata/build/gamedata_db_validator.dart';
import 'package:arklores/core/gamedata/build/portrait_index.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../support/gamedata_fixture.dart';

void main() {
  sqfliteFfiInit();
  late Database db;
  var index = 0;
  Future<void> add(String speaker, String sprite, {String story = 's'}) async {
    final i = index++;
    await db.insert('story_lines', {
      'id': '$i',
      'game': 'arknights',
      'story_id': story,
      'line_index': i,
      'speaker': speaker,
      'content': 'text',
      'language': 'zh_CN',
      'source_path': 'test',
      'kind': 'dialogue',
    });
    await db.insert(
      storyLinePortraitsTable,
      {'story_id': story, 'line_index': i, 'sprite': sprite},
    );
  }

  setUp(() async {
    index = 0;
    db = await createGameDataDb(inMemoryDatabasePath);
    await ensurePortraitTables(db);
  });
  tearDown(() => db.close());

  test(
      'all tables, lexical ties, ownership, highlight and deterministic rebuild',
      () async {
    const a = r'avg_4137_udflow_1#1$1';
    const b = r'avg_4137_udflow_1#2$1';
    const c = r'avg_npc_other#1$1';
    await db.insert('entries', {
      'id': 'operator:char_4137_udflow',
      'type': 'operator',
      'raw_id': 'char_4137_udflow',
      'name': 'test',
    });
    for (var i = 0; i < 2; i++) {
      await add(' Alpha ', a);
      await add('Alpha', b, story: 't');
      await add('Alpha', c);
    }
    for (var i = 0; i < 4; i++) {
      await add('Beta', a);
    }
    for (var i = 0; i < 3; i++) {
      await add('W', r'avg_single#1$1');
      await add('12', r'avg_number#1$1');
      await add('Minor', a);
      await add('𠀀甲', r'avg_unicode#1$1');
    }
    await add('Short', r'avg_short#1$1');
    await add('Short', r'avg_short#1$1');
    await add('   ', r'avg_blank#1$1');
    await rebuildPortraitIndex(db);
    final sprites =
        await db.query(portraitSpritesTable, where: 'sprite=?', whereArgs: [a]);
    expect(sprites.single, {
      'sprite': a,
      'group_id': 'avg_4137_udflow_1',
      'face': 1,
      'body': 1,
      'lines': 9,
    });
    final groups = await db.query(portraitGroupsTable, orderBy: 'group_id');
    final g = groups.firstWhere((g) => g['group_id'] == 'avg_4137_udflow_1');
    expect(g, {
      'group_id': 'avg_4137_udflow_1',
      'operator_entry_id': 'operator:char_4137_udflow',
      'lines': 11,
      'speakers': 3,
      'sprites': 2,
      'top_sprite': a,
    });
    expect(
      groups.firstWhere(
        (g) => g['group_id'] == 'avg_npc_other',
      )['operator_entry_id'],
      isNull,
    );
    final pair = (await db.query(
      speakerPortraitsTable,
      where: 'speaker=? AND group_id=?',
      whereArgs: ['Alpha', 'avg_4137_udflow_1'],
    ))
        .single;
    expect(pair, {
      'speaker': 'Alpha',
      'group_id': 'avg_4137_udflow_1',
      'lines': 4,
      'stories': 2,
      'top_sprite': a,
    });
    final names = await db.query(speakerNamesTable, orderBy: 'speaker');
    final alpha = names.firstWhere((n) => n['speaker'] == 'Alpha');
    expect(alpha, {
      'speaker': 'Alpha',
      'lines': 6,
      'groups': 2,
      'top_group': 'avg_4137_udflow_1',
      'top_sprite': a,
      'owns_group': 1,
      'highlight': 1,
    });
    for (final name in ['W', '12', 'Short', 'Minor', 'Beta']) {
      expect(
        names.firstWhere((n) => n['speaker'] == name)['highlight'],
        0,
        reason: name,
      );
    }
    expect(names.firstWhere((n) => n['speaker'] == '𠀀甲')['highlight'], 1);
    expect(names.any((n) => n['speaker'] == ''), isFalse);
    final tables = [
      portraitSpritesTable,
      portraitGroupsTable,
      speakerPortraitsTable,
      speakerNamesTable,
    ];
    final first = [for (final table in tables) await db.query(table)];
    await rebuildPortraitIndex(db);
    expect([for (final table in tables) await db.query(table)], first);
    expect(
      (await db.query(
        'gamedata_manifest',
        where: 'key=?',
        whereArgs: ['portrait_index_version'],
      ))
          .single['value'],
      '1',
    );
    await validateGameDataDatabase(db);
  });
  test('ties choose smallest speaker and group, exactly half owns group',
      () async {
    for (var i = 0; i < 3; i++) {
      await add('Aa', r'avg_b#1$1');
      await add('Bb', r'avg_b#1$1');
      await add('Aa', r'avg_a#1$1');
    }
    await rebuildPortraitIndex(db);
    final names = await db.query(speakerNamesTable, orderBy: 'speaker');
    expect(names.first['top_group'], 'avg_a');
    expect(names.first['top_sprite'], r'avg_a#1$1');
    expect(names.first['owns_group'], 1);
    expect(names.last['owns_group'], 0);
  });
  test(
      'empty and absent source remove derived tables and only portrait manifest',
      () async {
    await add('Name', r'avg_a#1$1');
    await rebuildPortraitIndex(db);
    await db.delete(storyLinePortraitsTable);
    for (var i = 0; i < 2; i++) {
      await rebuildPortraitIndex(db);
      expect(
        await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE name IN ('portrait_groups','portrait_sprites','speaker_portraits','speaker_names')",
        ),
        isEmpty,
      );
      expect(
        await db.rawQuery(
          "SELECT * FROM gamedata_manifest WHERE substr(key,1,9)='portrait_'",
        ),
        isEmpty,
      );
      expect(
        (await db.query('gamedata_manifest')).length,
        validManifest.length,
      );
      if (i == 0) await db.execute('DROP TABLE story_line_portraits');
    }
  });
  test('optional groups are validated when present', () async {
    await validateGameDataDatabase(db);
    await db.execute(portraitGroupsDdl);
    await expectLater(validateGameDataDatabase(db), throwsStateError);
  });
  test('delete is safe before tables exist and removes only selected story',
      () async {
    await add('Name', r'avg_a#1$1');
    await add('Name', r'avg_a#1$1', story: 't');
    await deletePortraitRows(db, 's');
    expect((await db.query(storyLinePortraitsTable)).single['story_id'], 't');
    await db.execute('DROP TABLE story_line_portraits');
    await deletePortraitRows(db, 's');
  });
}
