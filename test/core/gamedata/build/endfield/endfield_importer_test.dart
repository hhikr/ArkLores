// 0.12: the Endfield knowledge base from a small set of game tables (the
// same shapes as the client's: rows keyed by id, text as {id, text} objects
// resolved through I18nTextTable_CN). Names are made up.
import 'dart:convert';
import 'dart:io';

import 'package:arklores/core/gamedata/build/endfield/endfield_importer.dart';
import 'package:arklores/core/gamedata/build/endfield/endfield_stories.dart';
import 'package:arklores/core/gamedata/build/endfield/endfield_tables.dart';
import 'package:arklores/core/gamedata/build/endfield/endfield_writer.dart';
import 'package:arklores/core/gamedata/build/gamedata_db_validator.dart';
import 'package:arklores/core/gamedata/game.dart';
import 'package:arklores/core/library/library_queries.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../../support/sqlite.dart';
import '../../../../support/temp_dir.dart';

/// Localized text field: the string goes to the i18n table under [id].
Map<String, Object> tx(Map<String, String> i18n, int id, String text) {
  i18n['$id'] = text;
  return {'id': id, 'text': ''};
}

void writeTables(Directory dir) {
  final i18n = <String, String>{};
  void table(String name, Object rows) =>
      File('${dir.path}/$name.json').writeAsStringSync(jsonEncode(rows));
  table('CharacterTable', {
    'chr_0001_a': {
      'charId': 'chr_0001_a',
      'name': tx(i18n, 1, '甲'),
      'engName': 'Alpha',
      'department': 'TEST DEPT',
      'profileRecord': [
        {
          'recordTitle': tx(i18n, 2, '基础档案'),
          'recordDesc': tx(i18n, 3, '<@profile.key>【代号】甲</>\n来自谷地。'),
        },
      ],
      'profileVoice': [
        {'voiceTitle': tx(i18n, 4, '问候'), 'voiceDesc': tx(i18n, 5, '你好，管理员。')},
      ],
    },
    // A stand-in row with nothing to read is not listed.
    'chr_9000_x': {
      'charId': 'chr_9000_x',
      'name': tx(i18n, 6, '替身'),
      'profileRecord': <Object>[],
      'profileVoice': <Object>[],
    },
  });
  table('ItemTable', {
    'item_a': {
      'id': 'item_a',
      'name': tx(i18n, 10, '石头'),
      'decoDesc': tx(i18n, 11, '谷地里随处可见的石头，据说能辟邪。'),
      'type': 8,
    },
    // Three blueprints share one template line: dropped.
    for (final n in ['b', 'c', 'd'])
      'item_$n': {
        'id': 'item_$n',
        'name': tx(i18n, 20 + n.codeUnitAt(0), '图纸$n'),
        'decoDesc': tx(i18n, 30 + n.codeUnitAt(0), '记录着“图纸$n”生产工艺的档案文件。'),
        'type': 47,
      },
    // Mechanics: dropped.
    'item_e': {
      'id': 'item_e',
      'name': tx(i18n, 40, '药剂'),
      'decoDesc': tx(i18n, 41, '使用后恢复50%生命值。'),
      'type': 52,
    },
  });
  table('ItemTypeTable', {
    '8': {'name': tx(i18n, 50, '材料')},
  });
  table('PrtsCategory', {
    'paper': {'categoryId': 'paper', 'name': tx(i18n, 60, '纸张'), 'order': 1},
  });
  table('PrtsFirstLv', {
    'paper_1': {
      'categoryId': 'paper',
      'name': tx(i18n, 61, '一封信'),
      'itemIds': ['nar_1'],
      'order': 1,
    },
  });
  table('PrtsAllItem', {
    'nar_1': {'contentId': 'text_1', 'name': tx(i18n, 62, '一封信'), 'order': 1},
  });
  table('RichContentTable', {
    'text_1': {
      'title': tx(i18n, 63, '一封信'),
      'contentList': [
        {'content': tx(i18n, 64, 'Reading/x_photo\n亲爱的朋友：')},
        {'content': tx(i18n, 65, '谷地的春天来了。')},
      ],
    },
  });
  table('DialogTextTable', {
    'dlg_e1m1_1_001': {
      'actorName': tx(i18n, 70, '甲'),
      'dialogText': tx(i18n, 71, '{F}她来了。{M}他来了。'),
    },
    'dlg_e1m1_1_002': {
      'actorName': tx(i18n, 72, '乙'),
      'dialogText': tx(i18n, 73, '欢迎，{player}。'),
    },
    'dlg_e1m1_1_010': {
      'actorName': tx(i18n, 74, ''),
      'dialogText': tx(i18n, 75, '风停了。'),
    },
  });
  table('DialogSummaryMapTable', {'dlg_e1m1_1': 'summary_e1m1_1_001'});
  table(
      'DialogSummaryTable', {'summary_e1m1_1_001': tx(i18n, 80, '甲与乙在谷地相遇。')},);
  table('RadioTable', {
    'radio_sm1m2_1': {
      'radioSingleDataList': [
        {'index': 2, 'actorName': '乙', 'radioText': '收到。'},
        {'index': 1, 'actorName': '甲', 'radioText': '这里是甲。'},
      ],
    },
  });
  table('I18nTextTable_CN', i18n);
}

void main() {
  useSqfliteFfi();
  late Directory dir;
  late Database db;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('arklores_endfield_build');
    final tablesDir = Directory('${dir.path}/tables')..createSync();
    writeTables(tablesDir);
    db = await databaseFactoryFfi.openDatabase('${dir.path}/ef.db');
    final writer = EndfieldWriter(db);
    await writer.createSchema(sourceVersion: 'test');
    final tables = EndfieldTables(tablesDir);
    final importer = EndfieldImporter(tables, writer);
    await importer.importTables();
    await EndfieldStoryImporter(tables, writer, importer).importDialogTables();
    await writer.finish();
  });

  tearDown(() async {
    await db.close();
    await deleteTempDir(dir);
  });

  Future<List<Map<String, Object?>>> q(String sql, [List<Object?>? args]) =>
      db.rawQuery(sql, args);

  test('the database passes the installer check; every id is in ef/', () async {
    await validateGameDataDatabase(db);
    for (final (table, column) in [
      ('story_lines', 'story_id'),
      ('collections', 'id'),
      ('collections', 'kind'),
      ('normalized_records', 'id'),
      ('entries', 'raw_id'),
    ]) {
      final rows = await q('SELECT $column AS v FROM $table');
      expect(rows, isNotEmpty, reason: table);
      for (final r in rows) {
        expect(gameOfId('${r['v']}'), Game.endfield,
            reason: '$table.$column ${r['v']}',);
      }
    }
    final games = await q('SELECT DISTINCT game FROM story_lines');
    expect(games.single['game'], endfieldGame);
  });

  test('a conversation reads in order, one gender form, the player as 管理员',
      () async {
    final lines = await q(
      "SELECT speaker, content, kind FROM story_lines WHERE story_id = 'ef/dlg_e1m1_1.txt' ORDER BY line_index",
    );
    expect(lines.map((l) => l['content']), ['她来了。', '欢迎，管理员。', '风停了。']);
    expect(lines.last['kind'], 'narration');
    final catalog = await q(
      "SELECT collection_type, synopsis FROM story_catalog WHERE story_id = 'ef/dlg_e1m1_1.txt'",
    );
    expect(catalog.single['collection_type'], 'EF_MAIN');
    expect(catalog.single['synopsis'], '甲与乙在谷地相遇。');
    final radio = await q(
      "SELECT content FROM story_lines WHERE story_id = 'ef/radio_sm1m2_1.txt' ORDER BY line_index",
    );
    expect(radio.map((l) => l['content']), ['这里是甲。', '收到。']);
  });

  test('operators carry their archive and voices; stand-ins are left out',
      () async {
    final ops = await q("SELECT id, name FROM entries WHERE type = 'operator'");
    expect(ops.map((o) => o['name']), ['甲']);
    final texts = await q(
      "SELECT section, content FROM normalized_records WHERE entry_id = 'operator:ef/chr_0001_a'",
    );
    expect(texts.map((t) => t['section']), containsAll(['基础档案', '语音']));
    expect(texts.first['content'], isNot(contains('<@')));
    final shelf =
        await q("SELECT parent_id FROM collections WHERE kind = 'ef/memory'");
    expect(shelf.single['parent_id'], 'operator:ef/chr_0001_a');
  });

  test('items keep flavour text only; archive pages lose asset paths',
      () async {
    final items =
        await q("SELECT name, group_name FROM entries WHERE type = 'item'");
    expect(items.map((i) => i['name']), ['石头']);
    expect(items.single['group_name'], '材料');
    final doc = await q(
      "SELECT r.content FROM entries e JOIN normalized_records r ON r.entry_id = e.id WHERE e.type = 'document'",
    );
    expect(doc.single['content'], '亲爱的朋友：\n谷地的春天来了。');
  });

  test("the build's shelf list is the library's", () {
    expect(endfieldShelfKinds, endfieldShelfOrder);
  });
}
