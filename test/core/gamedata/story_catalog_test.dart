import 'dart:io';

import 'package:arklores/core/gamedata/build/story_catalog_importer.dart';
import 'package:arklores/core/gamedata/gamedata_knowledge_store.dart';
import 'package:arklores/core/gamedata/story_catalog.dart';
import 'package:arklores/core/gamedata/story_line_search.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/gamedata_fixture.dart';
import '../../support/sqlite.dart';
import '../../support/temp_dir.dart';
import '../../support/two_activities_fixture.dart';

/// R14/R15: the story catalog (names, order, official synopses, release
/// months) and what it changes in FIND and in collection lookups. Fixture
/// names are fictional; assertions check generic behaviour only.
void main() {
  setUpAll(useSqfliteFfi);

  group('story catalog parsing', () {
    test('maps storyTxt to story ids and builds labels', () {
      final entries = parseStoryReviewTable(_reviewTable, (info) {
        return info.endsWith('_02_beg') ? '  第二章的\n官方简介。 ' : null;
      });
      expect(entries.map((e) => e.storyId), [
        'activities/act_fx/level_act_fx_01_beg.txt',
        'activities/act_fx/level_act_fx_02_beg.txt',
        'obt/main/level_main_fx-01.txt',
        'obt/memory/story_fx_1_1.txt',
      ]);
      final second = entries[1];
      expect(second.label, '虚构活动 FX-2 行动前《转折》');
      expect(second.synopsis, '第二章的 官方简介。');
      expect(second.synopsisPath,
          'zh_CN/gamedata/story/[uc]info/activities/act_fx/level_act_fx_02_beg.txt',);
      expect(entries[2].label, '主线·虚构主线 0-1 幕间《开端》');
      // Operator records: the record name is the collection name.
      expect(entries[3].label, '干员密录·某段往事');
    });

    test('fallback labels come from the path only', () {
      expect(fallbackStoryLabel('activities/act_fx/level/fx_09_a1.txt'),
          '活动 act_fx · fx_09_a1',);
      expect(fallbackStoryLabel('obt/main/level_x.txt'), '主线 · level_x');
    });
  });

  group('catalog in a DB', () {
    late Directory dir;
    late String dbPath;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('arklores_catalog_test');
      dbPath = p.join(dir.path, 'catalog.db');
      final source = Directory(p.join(dir.path, 'src'));
      final table = File(p.join(source.path, storyReviewTablePath));
      await table.parent.create(recursive: true);
      await table.writeAsString(_reviewTableJson);
      for (final (rel, text) in [
        ('activities/act_fx/level_act_fx_01_beg.txt', '甲在城门埋下了伏笔。'),
        ('activities/act_fx/level_act_fx_02_beg.txt', '乙与丙秘密会面，达成交易。'),
      ]) {
        final f = File(p.joinAll([source.path, ...synopsisPathFor('info/$rel'.replaceAll('.txt', '')).split('/')]));
        await f.parent.create(recursive: true);
        await f.writeAsString(text);
      }
      final db = await _createStoryTables(dbPath);
      final result = await importStoryCatalog(db, source);
      expect(result!.entries, 4);
      expect(result.withSynopsis, 2);
      expect(result.matchedStories, 2);
      await db.close();
    });

    tearDown(() => deleteTempDir(dir));

    test('relabels chapter profiles and records the manifest count', () async {
      final db = await databaseFactoryFfi.openDatabase(dbPath);
      final profile = (await db.query('story_chapter_profiles',
              where: 'story_id = ?',
              whereArgs: ['activities/act_fx/level_act_fx_02_beg.txt'],))
          .single;
      expect(profile['title'], '虚构活动 FX-2 行动前《转折》');
      expect(profile['summary'], '乙与丙秘密会面，达成交易。');
      final count = await db.query('gamedata_manifest',
          where: 'key = ?', whereArgs: [manifestStoryCatalogCount],);
      expect(count.single['value'], '4');
      await db.close();
    });

    test('resolves a collection by name, scope key or story id', () async {
      final store = GameDataKnowledgeStore(dbPath: dbPath);
      for (final query in [
        '虚构活动',
        'activity:act_fx',
        'activities/act_fx/level_act_fx_02_beg.txt',
      ]) {
        final c = await store.storyCollection(query);
        expect(c, isNotNull, reason: query);
        expect(c!.collectionId, 'act_fx');
        expect(c.entries.map((e) => e.storyCode), ['FX-1', 'FX-2']);
      }
      final focused =
          await store.storyCollection('activities/act_fx/level_act_fx_02_beg.txt');
      expect(focused!.focusStoryId, 'activities/act_fx/level_act_fx_02_beg.txt');
      expect(await store.storyCollection('不存在的故事'), isNull);
      // Path-style and @-prefixed spellings seen in live planner output.
      for (final query in ['activities/act_fx', 'activities/act_fx/', '@activity:act_fx']) {
        expect((await store.storyCollection(query))?.collectionId, 'act_fx',
            reason: query,);
      }
      await store.close();
    });

    test('in-level files without a catalog row take their activity name',
        () async {
      final store = GameDataKnowledgeStore(dbPath: dbPath);
      const inLevel = 'activities/act_fx/level/fx_09_a1.txt';
      final entries = await store.storyCatalogEntries([inLevel, 'obt/x/y.txt']);
      expect(entries[inLevel]!.label, '虚构活动 fx_09_a1 关卡内对话');
      expect(entries.containsKey('obt/x/y.txt'), isFalse);
      await store.close();
    });

    test('keyword leg ORs terms and ranks lines with more terms first',
        () async {
      final db = await databaseFactoryFfi.openDatabase(dbPath);
      // "凶手" never occurs: it must not hide the other terms (pre-R14 this
      // query returned nothing).
      final hits = await queryStoryLinesLike(db, ['会面', '交易', '凶手']);
      expect(hits, isNotEmpty);
      expect(hits.first.storyId, 'activities/act_fx/level_act_fx_02_beg.txt');
      expect(hits.first.bestTermCount, 2);
      expect(hits.first.termCount, 3);
      expect(hits.first.lines.first.content, contains('会面'));
      expect(await queryStoryLinesLike(db, ['凶手']), isEmpty);
      await db.close();
    });
  });

  group('release months', () {
    test('review-table startTime becomes the release month', () {
      final entries = parseStoryReviewTable(
        decodeStoryReviewTable(twoActivitiesReviewTable),
        (_) => null,
      );
      final byCollection = {for (final e in entries) e.collectionId: e};
      expect(byCollection['act_old']!.releaseMonth, '2022-05');
      expect(byCollection['act_new']!.releaseMonth, '2024-06');
      expect(byCollection['main_fx']!.startTime, isNull);
      expect(releaseMonthOf(-1), isNull);
    });

    test('an R14 catalog row without start_time still parses', () {
      final entry = StoryCatalogEntry.fromRow(const {
        'story_id': 'a.txt',
        'collection_id': 'c',
        'collection_name': '名',
        'collection_type': 'ACTIVITY',
        'story_sort': 1,
      });
      expect(entry.startTime, isNull);
      expect(entry.releaseMonth, isNull);
    });

    test('release order: dated, then main story by number, then the rest', () {
      final keys = [
        collectionReleaseKey(collectionId: 'story_x', collectionType: 'NONE'),
        collectionReleaseKey(collectionId: 'main_10', collectionType: 'MAINLINE'),
        collectionReleaseKey(
            collectionId: 'act_new', collectionType: 'ACTIVITY', startTime: 1717560000,),
        collectionReleaseKey(collectionId: 'main_2', collectionType: 'MAINLINE'),
        collectionReleaseKey(
            collectionId: 'act_old', collectionType: 'ACTIVITY', startTime: 1651388400,),
      ]..sort(compareReleaseKeys);
      expect(keys.map((k) => k.$3),
          ['act_old', 'act_new', 'main_2', 'main_10', 'story_x'],);
    });
  });
}

/// Two chapters of a fictional activity with chapter profiles (the catalog
/// import relabels them).
Future<Database> _createStoryTables(String path) async {
  final db = await createGameDataDb(path);
  const stories = {
    'activities/act_fx/level_act_fx_01_beg.txt': ['城门外很安静。', '甲：我会等。'],
    'activities/act_fx/level_act_fx_02_beg.txt': [
      '乙：今晚的会面不能让人知道。',
      '丙：这笔交易，我答应了。会面结束。',
      '交易的代价很高。',
    ],
  };
  for (final MapEntry(key: id, value: lines) in stories.entries) {
    await insertStory(db, id, lines, scopeId: 'act_fx');
    await db.insert('story_chapter_profiles', {
      'story_id': id,
      'scope_id': 'activity:act_fx',
      'title': p.basename(id),
      'line_start': 0,
      'line_end': lines.length - 1,
      'speaker_set': '[]',
      'entity_density': '{}',
      'summary': lines.first,
    });
  }
  return db;
}

const String _reviewTableJson = '''
{
  "act_fx": {
    "id": "act_fx", "name": "虚构活动", "entryType": "ACTIVITY",
    "infoUnlockDatas": [
      {"storyCode": "FX-1", "storyName": "伏笔", "avgTag": "行动前", "storySort": 1,
       "storyInfo": "info/activities/act_fx/level_act_fx_01_beg",
       "storyTxt": "activities/act_fx/level_act_fx_01_beg"},
      {"storyCode": "FX-2", "storyName": "转折", "avgTag": "行动前", "storySort": 2,
       "storyInfo": "info/activities/act_fx/level_act_fx_02_beg",
       "storyTxt": "activities/act_fx/level_act_fx_02_beg"}
    ]
  },
  "main_fx": {
    "id": "main_fx", "name": "虚构主线", "entryType": "MAINLINE",
    "infoUnlockDatas": [
      {"storyCode": "0-1", "storyName": "开端", "avgTag": "幕间", "storySort": 1,
       "storyInfo": "info/obt/main/level_main_fx-01",
       "storyTxt": "obt/main/level_main_fx-01"},
      {"storyCode": "0-1", "storyName": "开端", "avgTag": "幕间", "storySort": 2,
       "storyInfo": "info/obt/main/level_main_fx-01",
       "storyTxt": "obt/main/level_main_fx-01"}
    ]
  },
  "story_fx_set_1": {
    "id": "story_fx_set_1", "name": "某段往事", "entryType": "NONE",
    "infoUnlockDatas": [
      {"storyCode": null, "storyName": "某段往事", "avgTag": "幕间", "storySort": 0,
       "storyInfo": "info/obt/memory/story_fx_1_1",
       "storyTxt": "obt/memory/story_fx_1_1"}
    ]
  }
}
''';

final Map<String, dynamic> _reviewTable = decodeStoryReviewTable(_reviewTableJson);
