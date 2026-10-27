import 'package:arklores/core/gamedata/build/gamedata_db_validator.dart';
import 'package:arklores/core/gamedata/build/portrait_index.dart';
import 'package:arklores/core/gamedata/build/story_script.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../support/gamedata_fixture.dart';

void main() {
  sqfliteFfiInit();
  late Database db;
  var index = 0;
  Future<void> add(String speaker, String? sprite, {String story = 's'}) async {
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
    if (sprite != null) {
      await db.insert(
        storyLinePortraitsTable,
        {'story_id': story, 'line_index': i, 'sprite': sprite},
      );
    }
  }

  setUp(() async {
    index = 0;
    db = await createGameDataDb(inMemoryDatabasePath);
    await ensurePortraitTables(db);
  });
  tearDown(() => db.close());

  test('CG dialogue does not enter portrait aggregates', () async {
    final lines = parseStoryScript('''
[Character(name="char_002_amiya_1#5")]
[name="Alpha"]before
[Image(image="avg_1_1")]
[name="Beta"]covered
[Image]
[name="Alpha"]after
''');
    for (final line in lines) {
      await add(line.speaker!, line.portrait);
    }
    await rebuildPortraitIndex(db);
    expect((await db.query(storyLinePortraitsTable)).length, 2);
    expect((await db.query('story_lines')).length, 3);
    expect((await db.query(portraitGroupsTable)).single['lines'], 2);
    expect((await db.query(speakerNamesTable)).single['speaker'], 'Alpha');
    expect(
      await db.query(
        speakerPortraitsTable,
        where: 'speaker=?',
        whereArgs: ['Beta'],
      ),
      isEmpty,
    );
  });

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
      'mentions': 0,
    });
    // Few lines no longer matter; one letter and no letters still do.
    expect(names.firstWhere((n) => n['speaker'] == 'Short')['highlight'], 1);
    for (final name in ['W', '12']) {
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
      '6',
    );
    await validateGameDataDatabase(db);
  });
  test('every speaker with a portrait counts but unknown, joint and one-letter',
      () async {
    Future<void> lines(String name, String sprite, int count) async {
      for (var i = 0; i < count; i++) {
        await add(name, sprite);
      }
    }

    await lines('洛青', r'avg_alias#1$1', 3);
    await lines('青石', r'avg_alias#1$1', 12);
    await lines('林舟', r'avg_unknown#1$1', 3);
    await lines('？？？', r'avg_unknown#1$1', 30);
    await lines('林舟？', r'avg_unknown#1$1', 8);
    await lines('洛青＆青石', r'avg_alias#1$1', 3);
    // Four named speakers; only the one with a quarter share qualifies.
    await lines('星弦', r'avg_share#1$1', 6);
    for (final name in ['甲客', '乙客', '丙客']) {
      await lines(name, r'avg_share#1$1', 3);
    }
    for (var i = 0; i < 12; i++) {
      await lines('行人$i', r'avg_crowd#1$1', 3);
    }
    await lines('访客', r'avg_visitor#1$1', 9);
    for (final name in ['年轻访客', '年长访客', '访客甲']) {
      await add(name, null);
    }
    await lines('女卫兵', r'avg_soldier#1$1', 3);
    await lines('石河', r'avg_soldier#1$1', 12);
    for (var i = 0; i < 30; i++) {
      await add('第$i卫兵', null);
    }
    await lines('叶澜', r'avg_leaf#1$1', 3);
    for (final name in ['叶澜？', '叶澜！', '叶澜＆甲', '叶澜/乙', '叶澜&丙']) {
      await add(name, null);
    }
    // Titles, extras told apart by a letter and titles said of a crowd
    // are highlighted when they have a portrait of their own.
    await lines('巡卫B', r'avg_patrol#1$1', 6);
    await lines('渡鸦', r'avg_raven#1$1', 9);
    await add('渡鸦们', null);
    // One character is not linked.
    await lines('岚', r'avg_one#1$1', 9);
    await rebuildPortraitIndex(db);
    final rows = {
      for (final r in await db.query(speakerNamesTable)) r['speaker']: r,
    };
    for (final name in [
      '洛青',
      '青石',
      '林舟',
      '星弦',
      '石河',
      '叶澜',
      '访客',
      '女卫兵',
      '巡卫B',
      '渡鸦',
      '行人0',
      '甲客',
    ]) {
      expect(rows[name]!['highlight'], 1, reason: name);
    }
    for (final name in ['？？？', '林舟？', '洛青＆青石', '岚']) {
      expect(rows[name]!['highlight'], 0, reason: name);
    }
    expect(rows['洛青']!['owns_group'], 0);
    expect(rows['林舟']!['owns_group'], 0);
  });

  test('a name the text uses far more than it speaks is not highlighted',
      () async {
    for (var i = 0; i < 3; i++) {
      await add('Gamma', r'avg_gamma#1$1');
      await add('Delta', r'avg_delta#1$1');
    }
    // Gamma: 10 mentions for 3 lines (> 3 per line); Delta: 9, exactly 3 per line.
    for (var i = 0; i < 5; i++) {
      await db.insert('story_lines', {
        'id': 'n$i',
        'game': 'arknights',
        'story_id': 'n',
        'line_index': i,
        'content': 'xGammay Gamma${i < 4 ? ' Delta Delta' : ' Delta'}',
        'language': 'zh_CN',
        'source_path': 'test',
        'kind': 'narration',
      });
    }
    await rebuildPortraitIndex(db);
    final names = {
      for (final n in await db.query(speakerNamesTable)) n['speaker']: n,
    };
    expect(names['Gamma']!['mentions'], 10);
    expect(names['Gamma']!['highlight'], 0);
    expect(names['Delta']!['mentions'], 9);
    expect(names['Delta']!['highlight'], 1);
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
