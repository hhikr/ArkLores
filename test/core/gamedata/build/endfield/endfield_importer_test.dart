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
  table('CharacterTagTable', {
    'chr_0001_a': {
      'blocTagId': 'tag_power_x',
      'raceTagId': 'tag_race_x',
      'dispositionTagIds': ['tag_sys'],
      'hobbyTagIds': ['tag_hidden'],
    },
  });
  table('TagDataTable', {
    'tag_power_x': {'tagName': tx(i18n, 110, '某工业'), 'tagGroupId': 'tag_group_power'},
    'tag_race_x': {'tagName': tx(i18n, 111, '某族'), 'tagGroupId': 'tag_group_race'},
    'tag_sys': {'tagName': tx(i18n, 112, '内部'), 'tagGroupId': 'tag_group_disposition'},
    'tag_hidden': {'tagName': tx(i18n, 113, '隐藏'), 'tagGroupId': 'tag_group_hobby', 'hideTag': true},
  });
  table('TagGroupDataTable', {
    'tag_group_power': {'tagGroupName': tx(i18n, 114, '阵营')},
    'tag_group_race': {'tagGroupName': tx(i18n, 115, '种族')},
    'tag_group_hobby': {'tagGroupName': tx(i18n, 116, '爱好')},
  });
  table('DungeonTable', {
    'dung_1': {
      'dungeonId': 'dung_1',
      'dungeonName': tx(i18n, 600, '兽穴'),
      'dungeonDesc': tx(i18n, 601, '野兽聚集的洞穴。'),
      'domainId': 'domain_1',
      'enemyIds': ['eny_0001_a', 'eny_9999_none'],
    },
  });
  table('MailTemplateTable', {
    'mail_1': {'templateId': 'mail_1', 'senderId': 'a', 'title': tx(i18n, 610, '来信'), 'mailContent': tx(i18n, 611, '一切安好。')},
    'mail_2': {'templateId': 'mail_2', 'senderId': 'system', 'title': tx(i18n, 612, '补发'), 'mailContent': tx(i18n, 613, '请领取。')},
  });
  table('RemoteCommonTable', {
    'remotecomm_e1m1_2': {
      'remoteCommSingleDataList': [
        {'index': 1, 'actorName': '乙', 'remoteCommText': '听得到吗？'},
      ],
    },
  });
  table('EnvTalkTable', {
    'envTalk_e1m1_1': {
      'envTalkDataList': [
        {'index': 1, 'actorId': '', 'text': '今天风好大。'},
      ],
    },
    'envTalk_Someone_1': {
      'envTalkDataList': [
        {'index': 1, 'actorId': '', 'text': '路过。'},
      ],
    },
  });
  table('DomainDataTable', {
    'domain_1': {'domainName': tx(i18n, 100, '谷地'), 'levelGroup': ['map01_lv001']},
  });
  table('DistributionInfoTable', {
    'distribution_map01_lv001': {'areaName': tx(i18n, 101, '枢纽区')},
  });
  table('EnemyTemplateDisplayInfoTable', {
    'eny_0001_a': {
      'templateId': 'eny_0001_a',
      'name': tx(i18n, 102, '某种野兽'),
      'description': tx(i18n, 103, '潜伏在地下的野兽。'),
      'distributionIds': ['distribution_map01_lv001'],
      'displayType': 0,
    },
  });
  table('PrtsFirstLv', {
    'paper_map01_1': {'categoryId': 'paper', 'name': tx(i18n, 104, '一封信'), 'itemIds': ['nar_1'], 'order': 1},
  });
  table('ItemTypeTable', {
    '8': {'name': tx(i18n, 50, '材料')},
  });
  table('PrtsCategory', {
    'paper': {'categoryId': 'paper', 'name': tx(i18n, 60, '纸张'), 'order': 1},
  });
  table('PrtsAllItem', {
    'nar_1': {'contentId': 'text_1', 'name': tx(i18n, 62, '一封信'), 'order': 1},
  });
  table('RichContentTable', {
    'text_e1m1_1': {
      'title': tx(i18n, 500, '留言'),
      'contentList': [
        {'content': tx(i18n, 501, '我先走了。')},
      ],
    },
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
    'dlg_c1m1_1_001': {
      'actorName': tx(i18n, 76, '路人{c1-内部名}'),
      'dialogText': tx(i18n, 77, '甲的故事开始了。'),
    },
    'dlg_e1m1_1_010': {
      'actorName': tx(i18n, 74, ''),
      'dialogText': tx(i18n, 75, '风停了。'),
    },
  });
  table('DialogOptionTable', {
    'option_dlg_e1m1_1_3_001': {'optionText': tx(i18n, 90, '跟上去')},
    'option_dlg_e1m1_1_3_002': {'optionText': tx(i18n, 91, '留下来')},
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
    await EndfieldStoryImporter(
      tables,
      writer,
      importer,
      missions: {
        'e1m1': (
          name: '启程',
          description: '出发前往谷地。',
          type: 0,
          charId: null,
          sortId: 0,
          levelId: 'map01_lv001',
        ),
      },
    ).importDialogTables();
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

  test('a mission is one story: its conversations in the game numbering, each under a section line',
      () async {
    final lines = await q(
      "SELECT speaker, content, kind FROM story_lines WHERE story_id = 'ef/e1m1.txt' ORDER BY line_index",
    );
    expect(
      lines.map((l) => l['content']),
      [
        '对话', '她来了。', '欢迎，管理员。', '跟上去／留下来', '风停了。',
        '远程通话', '听得到吗？',
        '闲话', '今天风好大。',
      ],
    );
    expect(
      [for (final l in lines) if (l['kind'] == 'section') l['content']],
      ['对话', '远程通话', '闲话'],
    );
    expect(lines[3]['kind'], 'choice');
    expect(lines[4]['kind'], 'narration');
    final catalog = await q(
      "SELECT story_name, collection_name, collection_type, synopsis FROM story_catalog WHERE story_id = 'ef/e1m1.txt'",
    );
    expect(catalog.single['story_name'], '启程');
    expect(catalog.single['collection_type'], 'EF_MAIN');
    expect(catalog.single['synopsis'], '甲与乙在谷地相遇。');
    final radio = await q(
      "SELECT content FROM story_lines WHERE story_id = 'ef/sm1m2.txt' ORDER BY line_index",
    );
    expect(radio.map((l) => l['content']), ['通讯', '这里是甲。', '收到。']);
    // The section lines are not part of the retrieval text.
    final text = await q(
      "SELECT content FROM normalized_records WHERE parent_id = 'ef/e1m1.txt'",
    );
    expect(text.map((r) => r['content']).join(), isNot(contains('远程通话')));
  });

  test('a mission carries its description and the region it is played in', () async {
    final intro = await q(
      'SELECT e.group_name, r.content FROM entries e '
      'JOIN normalized_records r ON r.entry_id = e.id '
      "WHERE e.type = 'mission_intro' AND e.collection_id = 'ef/mission_e1m1'",
    );
    expect(intro.single['content'], '出发前往谷地。');
    expect(intro.single['group_name'], '谷地');
    expect(await collectionIntro(db, 'ef/mission_e1m1'), '出发前往谷地。');
    final shelf = await collectionsOfKind(db, 'ef/main');
    final mission = shelf.singleWhere((c) => c.id == 'ef/mission_e1m1');
    expect(mission.name, '启程');
    expect(mission.intro, '出发前往谷地。');
    expect(mission.group, '谷地');
    expect(mission.stories, 1);
  });

  test('operators carry their archive and voices; stand-ins are left out',
      () async {
    final ops = await q("SELECT id, name FROM entries WHERE type = 'operator'");
    expect(ops.map((o) => o['name']), ['甲']);
    final texts = await q(
      "SELECT section, content FROM normalized_records WHERE entry_id = 'operator:ef/chr_0001_a'",
    );
    expect(texts.map((t) => t['section']), containsAll(['标签', '基础档案', '语音']));
    final tags = texts.firstWhere((t) => t['section'] == '标签')['content'];
    expect(tags, '阵营：某工业\n种族：某族');
    final faction = await q("SELECT name FROM entities WHERE entity_type = 'power'");
    expect(faction.single['name'], '某工业');
    expect(texts.first['content'], isNot(contains('<@')));
    final shelf =
        await q(
      "SELECT parent_id FROM collections WHERE id = 'ef/operator_chr_0001_a'",
    );
    expect(shelf.single['parent_id'], 'operator:ef/chr_0001_a');
  });

  test('items keep flavour text only; archive pages lose asset paths',
      () async {
    final items =
        await q("SELECT name, group_name FROM entries WHERE type = 'item'");
    expect(items.map((i) => i['name']), ['石头']);
    expect(items.single['group_name'], '材料');
    final doc = await q(
      "SELECT r.content FROM entries e JOIN normalized_records r ON r.entry_id = e.id WHERE e.raw_id = 'ef/paper_map01_1'",
    );
    expect(doc.single['content'], '亲爱的朋友：\n谷地的春天来了。');
  });

  test('a character mission hangs below its operator; speakers lose internal notes', () async {
    final owner = await q(
      "SELECT kind, parent_id FROM collections WHERE id = 'ef/mission_c1m1'",
    );
    expect(owner.single['kind'], 'ef/memory');
    expect(owner.single['parent_id'], 'operator:ef/chr_0001_a');
    final line = await q(
      "SELECT speaker FROM story_lines WHERE story_id = 'ef/c1m1.txt' AND kind <> 'section'",
    );
    expect(line.single['speaker'], '路人');
  });

  test('a mission reads kind by kind, each kind in its own numbering', () {
    int compare(String a, String b) {
      final byKind = conversationKindRank(a).compareTo(conversationKindRank(b));
      return byKind != 0 ? byKind : conversationOrder(a)!.compareTo(conversationOrder(b)!);
    }

    final ids = [
      'sns_e1m1_2', 'dlg_e1m1_10', 'radio_e1m1_0d5', 'dlg_e1m1_2', 'radio_e1m1_1d5',
      'remotecomm_e1m1_1', 'dlg_e1m1_2d5',
    ]..sort(compare);
    expect(ids, [
      'dlg_e1m1_2', 'dlg_e1m1_2d5', 'dlg_e1m1_10',
      'radio_e1m1_0d5', 'radio_e1m1_1d5',
      'remotecomm_e1m1_1',
      'sns_e1m1_2',
    ]);
    expect(conversationOrder('dlg_x'), isNull);
  });

  test('enemies say where they are found; documents and places carry their region', () async {
    final where = await q(
      "SELECT r.content FROM normalized_records r WHERE r.entry_id = 'enemy:ef/eny_0001_a' AND r.section = '分布'",
    );
    expect(where.single['content'], '枢纽区');
    final doc = await q("SELECT group_name FROM entries WHERE raw_id = 'ef/paper_map01_1'");
    expect(doc.single['group_name'], '谷地');
  });

  test('texts read in a mission outside the archive are documents of that mission', () async {
    final rows = await q(
      "SELECT name, collection_id FROM entries WHERE raw_id = 'ef/text_e1m1_1'",
    );
    expect(rows.single['name'], '留言');
    expect(rows.single['collection_id'], 'ef/mission_e1m1');
  });

  test('dungeons bind their enemies; character mails are kept, system ones not', () async {
    final links = await q("SELECT src, dst FROM entry_links WHERE relation = 'appears_in'");
    expect(links.single['src'], 'enemy:ef/eny_0001_a');
    expect(links.single['dst'], 'stage:ef/dung_1');
    final mails = await q("SELECT name FROM entries WHERE type = 'mail'");
    expect(mails.single['name'], '来信 · 甲');
  });

  test('remote calls and ambient talk join their mission; stray talk is left out', () async {
    final stories = await q(
      "SELECT raw_id FROM entries WHERE type = 'story' AND collection_id = 'ef/mission_e1m1'",
    );
    expect(stories.single['raw_id'], 'ef/e1m1.txt');
    final stray = await q("SELECT COUNT(*) AS n FROM story_lines WHERE content = '路过。'");
    expect(stray.single['n'], 0);
  });

  test('the kinds a section line names come from the table a conversation is in', () {
    expect(
      [
        for (final id in ['dlg_a1m1_1', 'radio_a1m1_2', 'remotecomm_a1m1_3', 'envTalk_a1m1_4', 'sns_a1m1_5'])
          conversationKind(id),
      ],
      ['对话', '通讯', '远程通话', '闲话', '短信'],
    );
  });

  test('missions order by the numbers of their ids', () {
    final ids = ['e10m1', 'e1m2', 'e1m10', 'e1m2d5', 'e0m0']
      ..sort((a, b) => missionOrder(a)!.compareTo(missionOrder(b)!));
    expect(ids, ['e0m0', 'e1m2', 'e1m2d5', 'e1m10', 'e10m1']);
  });

  test("the build's shelf list is the library's", () {
    expect(endfieldShelfKinds, endfieldShelfOrder);
  });
}
