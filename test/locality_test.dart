import 'dart:io';

import 'package:arklores/core/agent/tools/agent_tool.dart';
import 'package:arklores/core/agent/tools/search_story_lines.dart';
import 'package:arklores/core/gamedata/gamedata_knowledge_store.dart';
import 'package:arklores/core/gamedata/name_similarity.dart';
import 'package:arklores/core/gamedata/story_catalog.dart';
import 'package:arklores/features/ai/investigation_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/temp_dir.dart';

/// R15: reaching beyond the previous answer's story — near names for a
/// misspelt name, hits outside a FIND scope, an overview of every collection
/// in COVER, release months, collections named in the question, no
/// inheritance on a topic change, and grouped citations. All names are
/// fictional; assertions check generic behaviour only.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    sqflite.databaseFactory = databaseFactoryFfi;
  });

  group('near names', () {
    const inventory = [
      NameOccurrence('洛蕾西娅', 600, '剧情提及'),
      NameOccurrence('洛雷西斯', 900, '剧情提及'),
      NameOccurrence('谬安', 2, '干员'),
      NameOccurrence('凯伦', 50, '说话人'),
    ];

    test('a homophone spelling ranks above a one-character neighbour', () {
      // `洛雷西亚` differs from `洛雷西斯` by one character but sounds like
      // `洛蕾西娅` (two homophone substitutions): reading wins.
      final ranked = rankSimilarNames('洛雷西亚', inventory);
      expect(ranked.map((s) => s.name), ['洛蕾西娅', '洛雷西斯']);
      expect(ranked.first.cost, closeTo(2 * homophoneCost, 1e-9));
      expect(rankSimilarNames('缪安', inventory).first.name, '谬安');
    });

    test('nothing for names without a shared character or too far away', () {
      expect(rankSimilarNames('完全无关', inventory), isEmpty);
      expect(
        rankSimilarNames('洛蕾西娅', inventory).map((s) => s.name),
        isNot(contains('洛蕾西娅')),
      );
    });

    test('the hint states string similarity only', () {
      final hint = describeSimilarNames(
        '缪安',
        rankSimilarNames('缪安', inventory),
      )!;
      expect(hint, contains('谬安（干员，2 次）'));
      expect(hint, contains('只是字符串相近'));
    });

    test('names in a question: longer known strings block their parts', () {
      const known = [
        NameOccurrence('伊塔利亚', 300, '剧情提及'),
        NameOccurrence('塔利', 40, '说话人'),
        NameOccurrence('凯伦', 50, '说话人'),
        NameOccurrence('路人', 2, '说话人'),
      ];
      expect(namesMentionedIn('伊塔利亚的凯伦和路人', known), ['凯伦']);
      expect(namesMentionedIn('塔利去哪了', known), ['塔利']);
    });
  });

  group('release months', () {
    test('review-table startTime becomes the release month', () {
      final entries = parseStoryReviewTable(
        decodeStoryReviewTable(_reviewTableJson),
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
        collectionReleaseKey(
          collectionId: 'story_x',
          collectionType: 'NONE',
        ),
        collectionReleaseKey(
          collectionId: 'main_10',
          collectionType: 'MAINLINE',
        ),
        collectionReleaseKey(
          collectionId: 'act_new',
          collectionType: 'ACTIVITY',
          startTime: 1717560000,
        ),
        collectionReleaseKey(
          collectionId: 'main_2',
          collectionType: 'MAINLINE',
        ),
        collectionReleaseKey(
          collectionId: 'act_old',
          collectionType: 'ACTIVITY',
          startTime: 1651388400,
        ),
      ]..sort(compareReleaseKeys);
      expect(
        keys.map((k) => k.$3),
        ['act_old', 'act_new', 'main_2', 'main_10', 'story_x'],
      );
    });
  });

  group('tools on a fixture DB', () {
    late Directory dir;
    late String dbPath;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('arklores_locality_test');
      dbPath = p.join(dir.path, 'locality.db');
      final db = await databaseFactoryFfi.openDatabase(dbPath);
      await _createFixture(db);
      await db.close();
    });

    tearDown(() => deleteTempDir(dir));

    test('FIND reports hits outside its scope and near names', () async {
      final tool = SearchStoryLinesTool(
        gameDataStore: GameDataKnowledgeStore(dbPath: dbPath),
      );
      final scoped = (await tool.execute({
        'query': '灯塔',
        'scope_id': 'activity:act_old',
      }) as ToolExecutionResult)
          .observation;
      expect(scoped, contains('范围外命中：“灯塔”在 activity:act_old 内 0 行'));
      expect(scoped, contains('activities/act_new/'));
      expect(scoped, isNot(contains('资料未覆盖')));

      final misspelt =
          (await tool.execute({'query': '凯仑'}) as ToolExecutionResult)
              .observation;
      expect(misspelt, contains('相近的名字：凯伦'));

      // A story-path scope names the activity; a chapter file is not a
      // scope and is redirected to READ.
      expect(normalizeScopeId('activities/act_new'), 'activity:act_new');
      expect(normalizeScopeId('@activities/act_new/'), 'activity:act_new');
      for (final file in [
        '@activities/act_new/level_act_new_01.txt',
        'obt/memory/story_x_1_1',
      ]) {
        final text = (await tool.execute({'query': '灯塔', 'scope_id': file})
                as ToolExecutionResult)
            .observation;
        expect(text, contains('是单个章节文件，不是检索范围'), reason: file);
        expect(text, contains('READ '), reason: file);
      }
    });

    test('collections named in a question are found verbatim', () async {
      final store = GameDataKnowledgeStore(dbPath: dbPath);
      final targets = await store.namedStoryTargets('凯伦在远方之路里做了什么');
      expect(targets.single.collectionId, 'act_new');
      expect(targets.single.releaseMonth, '2024-06');
      // Chapter names shorter than 3 characters only count inside 《》.
      expect(await store.namedStoryTargets('关于启程的问题'), isEmpty);
      expect(
        (await store.namedStoryTargets('《启程》讲了什么')).single.storyId,
        'activities/act_new/level_act_new_01.txt',
      );
      await store.close();
    });
  });

  group('grouped citations', () {
    test('collection → chapter → merged line ranges', () {
      const a1 = 'activities/act_x/level_x_01.txt';
      const a2 = 'activities/act_x/level_x_02.txt';
      const b = 'obt/main/level_main_01.txt';
      final entries = {
        a1: const StoryCatalogEntry(
          storyId: a1,
          collectionId: 'act_x',
          collectionName: '甲活动',
          collectionType: 'ACTIVITY',
          storySort: 1,
          storyCode: 'X-1',
          avgTag: '行动前',
        ),
        a2: const StoryCatalogEntry(
          storyId: a2,
          collectionId: 'act_x',
          collectionName: '甲活动',
          collectionType: 'ACTIVITY',
          storySort: 2,
          storyCode: 'X-2',
          avgTag: '行动后',
        ),
      };
      final groups = groupCitations(
        '见 $a2:5、$a1:3-4、$a1:5 与 `$b:0`；又见 $a1:9。',
        entries,
      );
      expect(groups.map((g) => g.label), ['甲活动', '主线']);
      final x = groups.first;
      expect(x.chapters.map((c) => c.label), ['X-1 行动前', 'X-2 行动后']);
      // 3-4 and 5 are adjacent: one range; 9 stays separate.
      expect(
        x.chapters.first.ranges.map((r) => r.rawRef(a1)),
        ['$a1:3-5', '$a1:9'],
      );
      expect(x.citationCount, 3);
      expect(groups.last.chapters.single.label, 'level_main_01');
      expect(
        citedRangeText(x.chapters.first.ranges.first, (s, e) => '$s-$e'),
        '4-6',
      );
    });
  });
}

const int _oldChapters = 40;

Future<void> _createFixture(Database db) async {
  await db.execute(
    'CREATE TABLE gamedata_manifest (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
  );
  await db.execute(
    'CREATE TABLE story_lines (story_id TEXT, line_index INTEGER, '
    'speaker TEXT, content TEXT)',
  );
  await db.execute(
    'CREATE TABLE story_scopes (story_id TEXT PRIMARY KEY, scope_type TEXT, '
    'scope_id TEXT, source_path TEXT)',
  );
  await db.execute(
    'CREATE TABLE story_chapter_profiles (story_id TEXT PRIMARY KEY, '
    'scope_id TEXT, title TEXT, line_start INTEGER, line_end INTEGER, '
    'speaker_set TEXT, entity_density TEXT, summary TEXT)',
  );
  await db.execute(
    'CREATE TABLE entities (id TEXT PRIMARY KEY, name TEXT NOT NULL, '
    'aliases TEXT, entity_type TEXT NOT NULL, source_type TEXT NOT NULL, '
    'game TEXT NOT NULL, source_path TEXT, game_version TEXT, updated_at INTEGER)',
  );
  await db.execute(
    'CREATE TABLE entity_aliases (alias TEXT NOT NULL, entity_id TEXT NOT NULL, '
    'alias_type TEXT NOT NULL, confidence REAL NOT NULL DEFAULT 1.0, '
    'source_path TEXT, PRIMARY KEY (alias, entity_id, alias_type))',
  );
  await db.execute(
    'CREATE TABLE entity_story_mentions (entity_id TEXT NOT NULL, '
    'story_id TEXT NOT NULL, scope_id TEXT NOT NULL, line_start INTEGER NOT NULL, '
    'line_end INTEGER NOT NULL, mention_count INTEGER NOT NULL, matched_alias TEXT)',
  );
  await db.insert('entities', {
    'id': 'char_fx_karen',
    'name': '凯伦',
    'aliases': '[]',
    'entity_type': 'operator',
    'source_type': 'operator_profile',
    'game': 'arknights',
  });
  await db.insert('entity_aliases', {
    'alias': '凯伦',
    'entity_id': 'char_fx_karen',
    'alias_type': 'canonical',
  });

  final stories = <String, (String, List<String>)>{
    for (var i = 1; i <= _oldChapters; i++)
      'activities/act_old/level_act_old_${i.toString().padLeft(2, '0')}.txt': (
        'act_old',
        ['凯伦：第 $i 段旧航线。', '海风很大。'],
      ),
    'activities/act_new/level_act_new_01.txt': (
      'act_new',
      ['凯伦：我们出发吧。', '远处有一座灯塔。'],
    ),
    'activities/act_new/level_act_new_02.txt': (
      'act_new',
      ['凯伦：灯塔熄灭了。'],
    ),
  };
  for (final story in stories.entries) {
    final (collection, lines) = story.value;
    await db.insert('story_scopes', {
      'story_id': story.key,
      'scope_type': 'activity',
      'scope_id': collection,
      'source_path': 'zh_CN/gamedata/story/${story.key}',
    });
    for (var i = 0; i < lines.length; i++) {
      final text = lines[i];
      final colon = text.indexOf('：');
      await db.insert('story_lines', {
        'story_id': story.key,
        'line_index': i,
        'speaker': colon > 0 ? text.substring(0, colon) : null,
        'content': colon > 0 ? text.substring(colon + 1) : text,
      });
      if (colon > 0) {
        await db.insert('entity_story_mentions', {
          'entity_id': 'char_fx_karen',
          'story_id': story.key,
          'scope_id': 'activity:$collection',
          'line_start': i,
          'line_end': i,
          'mention_count': 1,
          'matched_alias': '凯伦',
        });
      }
    }
  }
  final entries = parseStoryReviewTable(
    decodeStoryReviewTable(_reviewTableJson),
    (_) => null,
  );
  await writeStoryCatalog(db, entries);
}

String get _reviewTableJson {
  final oldChapters = [
    for (var i = 1; i <= _oldChapters; i++)
      '{"storyCode": "OL-$i", "storyName": "航线第$i段", "avgTag": "行动前", '
          '"storySort": $i, "storyInfo": "", '
          '"storyTxt": "activities/act_old/level_act_old_${i.toString().padLeft(2, '0')}"}',
  ].join(',\n');
  return '''
{
  "act_old": {
    "id": "act_old", "name": "旧日航线", "entryType": "ACTIVITY",
    "startTime": 1651388400,
    "infoUnlockDatas": [$oldChapters]
  },
  "act_new": {
    "id": "act_new", "name": "远方之路", "entryType": "ACTIVITY",
    "startTime": 1717560000,
    "infoUnlockDatas": [
      {"storyCode": "FR-1", "storyName": "启程", "avgTag": "行动前", "storySort": 1,
       "storyInfo": "", "storyTxt": "activities/act_new/level_act_new_01"},
      {"storyCode": "FR-2", "storyName": "灯塔熄灭", "avgTag": "行动后", "storySort": 2,
       "storyInfo": "", "storyTxt": "activities/act_new/level_act_new_02"}
    ]
  },
  "main_fx": {
    "id": "main_fx", "name": "虚构主线", "entryType": "MAINLINE", "startTime": -1,
    "infoUnlockDatas": [
      {"storyCode": "0-1", "storyName": "开端", "avgTag": "幕间", "storySort": 1,
       "storyInfo": "", "storyTxt": "obt/main/level_main_fx-01"}
    ]
  }
}
''';
}

