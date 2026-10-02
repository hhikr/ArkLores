import 'dart:io';

import 'package:arklores/core/agent/chat_message.dart';
import 'package:arklores/core/agent/chat_notifier_base.dart';
import 'package:arklores/core/agent/investigation_state.dart';
import 'package:arklores/core/agent/planner_intent.dart';
import 'package:arklores/core/agent/planner_loop.dart';
import 'package:arklores/core/agent/react_loop.dart';
import 'package:arklores/core/agent/story_answer.dart';
import 'package:arklores/core/agent/tools/agent_tool.dart';
import 'package:arklores/core/agent/tools/get_story_outline.dart';
import 'package:arklores/core/agent/tools/observation_data.dart';
import 'package:arklores/core/agent/tools/search_story_lines.dart';
import 'package:arklores/core/gamedata/build/story_catalog_importer.dart';
import 'package:arklores/core/gamedata/gamedata_knowledge_store.dart';
import 'package:arklores/core/gamedata/story_catalog.dart';
import 'package:arklores/core/gamedata/story_line_search.dart';
import 'package:arklores/core/llm/llm_client.dart';
import 'package:arklores/features/ai/investigation_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/temp_dir.dart';

/// R14: story catalog (names, order, official synopses), OR-ranked FIND,
/// OUTLINE, labelled planner state, compact follow-up history and readable
/// citations. Fixture names are fictional; assertions check generic
/// behaviour only.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    sqflite.databaseFactory = databaseFactoryFfi;
  });

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
      final db = await databaseFactoryFfi.openDatabase(dbPath);
      await _createStoryTables(db);
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
      await store.close();
    });

    test('OUTLINE lists chapters in order with synopses', () async {
      final tool = GetStoryOutlineTool(
        gameDataStore: GameDataKnowledgeStore(dbPath: dbPath),
      );
      final result =
          await tool.execute({'target': '虚构活动'}) as ToolExecutionResult;
      final text = result.observation;
      expect(text, contains('Outline: 《虚构活动》'));
      expect(text.indexOf('FX-1'), lessThan(text.indexOf('FX-2')));
      expect(text, contains('梗概: 乙与丙秘密会面，达成交易。'));
      expect(text, contains('READ 原文'));
      final data = parseDataBlocks(text).single;
      expect(data['collection_id'], 'act_fx');

      // Compact form kept in state: one row per chapter + clipped synopsis.
      final compact = compactOutline(text);
      expect(compact, contains('FX-2 行动前《转折》 | activities/act_fx/level_act_fx_02_beg.txt'));
      expect(compact, contains('乙与丙秘密会面'));
      expect(compact, isNot(contains('DATA:')));
    });

    test('FIND lists synopsis hits and labels the stories', () async {
      final tool = SearchStoryLinesTool(
        gameDataStore: GameDataKnowledgeStore(dbPath: dbPath),
      );
      final result =
          await tool.execute({'query': '会面 交易'}) as ToolExecutionResult;
      final text = result.observation;
      expect(text, contains('官方章节梗概命中'));
      expect(text, contains('level_act_fx_02_beg.txt 《虚构活动 FX-2 行动前《转折》》'));
      expect(text, contains('| 《虚构活动 FX-2 行动前《转折》》'));
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

  group('planner state and history', () {
    test('OUTLINE intent keeps the whole target', () {
      final intent = parseIntent('OUTLINE 《虚构 活动》')!;
      expect(intent.action, 'OUTLINE');
      expect(intent.args['target'], '虚构 活动');
      expect(parseIntent('OUTLINE'), isNull);
    });

    test('FIND scope spellings normalize to the canonical key', () {
      final intent = parseIntent('FIND 会面 交易 @activity:act_fx')!;
      expect(intent.args['query'], '会面 交易');
      expect(intent.args['scope_id'], 'activity:act_fx');
      expect(normalizeScopeId('act_fx'), 'activity:act_fx');
      expect(normalizeScopeId('activities:act_fx'), 'activity:act_fx');
      expect(normalizeScopeId('@obt:main'), 'obt:main');
      expect(normalizeScopeId(' '), isNull);
    });

    test('READ accepts a start-end range token', () {
      final intent = parseIntent('READ a/b.txt 30-90')!;
      expect(intent.args['start_line'], 30);
      expect(intent.args['end_line'], 90);
      final spaced = parseIntent('READ a/b.txt 30 90')!;
      expect(spaced.args['end_line'], 90);
    });

    test('firstUnreadLine skips already-read segments', () {
      final state = InvestigationState()
        ..noteRead('a.txt', 0, 29)
        ..noteRead('a.txt', 40, 59);
      expect(state.firstUnreadLine('a.txt', 0), 30);
      expect(state.firstUnreadLine('a.txt', 35), 35);
      expect(state.firstUnreadLine('a.txt', 45), 60);
      expect(state.firstUnreadLine('b.txt', 5), 5);
    });

    test('state shows labels, outlines and the missing-outline hint', () {
      const id = 'activities/act_fx/level_act_fx_02_beg.txt';
      final state = InvestigationState()..noteRead(id, 0, 10);
      expect(state.storyIdsWithoutLabel, {id});
      state.addStoryEntries([id], {id: _entry(id)});
      expect(state.storyIdsWithoutLabel, isEmpty);
      var text = state.serialize();
      expect(text, contains('$id［虚构活动 FX-2 行动前《转折》］:0-10'));
      expect(text, contains('OUTLINE act_fx'));

      final before = state.progressFingerprint;
      state.noteOutline('act_fx', '  《虚构活动》\n   1. FX-1 | a.txt');
      expect(state.progressFingerprint, isNot(before));
      text = state.serialize();
      expect(text, contains('已看梗概'));
      expect(text, isNot(contains('OUTLINE act_fx')));
    });

    test('follow-up history keeps answers and read chapters, not observations',
        () {
      final messages = [
        ChatMessage(
          id: '1',
          role: MessageRole.user,
          content: '问题一',
          timestamp: DateTime(2026),
        ),
        ChatMessage(
          id: '2',
          role: MessageRole.assistant,
          content: '${formatStoryAnswerEnvelope(StoryAnswerStatus.answered)}\n答案一',
          timestamp: DateTime(2026),
          steps: [
            ReActStep(
              type: ReActEventType.toolObservation,
              toolName: 'read_story_lines',
              content: appendDataBlock('Story: a.txt\n0 | 很长的原文', {
                'type': 'read_story_lines',
                'story_id': 'a.txt',
                'first_line': 0,
                'last_line': 29,
              }),
            ),
          ],
        ),
      ];
      final prior = lastTurnReadPages(messages);
      expect(prior.single.storyId, 'a.txt');
      expect(prior.single.lines.single.content, '很长的原文');
      final history = buildStoryQaHistory(messages);
      expect(history, hasLength(2));
      expect(history[1].content, startsWith('答案一'));
      expect(history[1].content, contains('a.txt:0-29'));
      expect(history[1].content, isNot(contains('STORY_ANSWER')));
      expect(history[1].content, isNot(contains('很长的原文')));
      expect(history[1].content, isNot(contains('Observation')));
    });
  });

  group('readable citations', () {
    test('replaces story ids with labels and 1-based lines', () {
      const id = 'activities/act_fx/level_act_fx_02_beg.txt';
      final labels = {id: '虚构活动 FX-2 行动前《转折》'};
      expect(
        humanizeCitations('见 `$id:4` 与 $id:7-9。', labels),
        '见 〔虚构活动 FX-2 行动前《转折》 第 5 行〕 与 〔虚构活动 FX-2 行动前《转折》 第 8–10 行〕。',
      );
      expect(formatLineReference('$id:0', const {}),
          '活动 act_fx · level_act_fx_02_beg · 第 1 行',);
      expect(extractCitedStoryIds('$id:1 b/c.txt:2'), {id, 'b/c.txt'});
    });
  });
}

StoryCatalogEntry _entry(String id) => StoryCatalogEntry(
      storyId: id,
      collectionId: 'act_fx',
      collectionName: '虚构活动',
      collectionType: 'ACTIVITY',
      storySort: 2,
      storyCode: 'FX-2',
      storyName: '转折',
      avgTag: '行动前',
    );

Future<void> _createStoryTables(Database db) async {
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
  const stories = {
    'activities/act_fx/level_act_fx_01_beg.txt': ['城门外很安静。', '甲：我会等。'],
    'activities/act_fx/level_act_fx_02_beg.txt': [
      '乙：今晚的会面不能让人知道。',
      '丙：这笔交易，我答应了。会面结束。',
      '交易的代价很高。',
    ],
  };
  for (final entry in stories.entries) {
    await db.insert('story_scopes', {
      'story_id': entry.key,
      'scope_type': 'activity',
      'scope_id': 'act_fx',
      'source_path': 'zh_CN/gamedata/story/${entry.key}',
    });
    await db.insert('story_chapter_profiles', {
      'story_id': entry.key,
      'scope_id': 'activity:act_fx',
      'title': p.basename(entry.key),
      'line_start': 0,
      'line_end': entry.value.length - 1,
      'speaker_set': '[]',
      'entity_density': '{}',
      'summary': entry.value.first,
    });
    for (var i = 0; i < entry.value.length; i++) {
      final text = entry.value[i];
      final colon = text.indexOf('：');
      await db.insert('story_lines', {
        'story_id': entry.key,
        'line_index': i,
        'speaker': colon > 0 ? text.substring(0, colon) : null,
        'content': colon > 0 ? text.substring(colon + 1) : text,
      });
    }
  }
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
