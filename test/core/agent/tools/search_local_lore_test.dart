// The roleplay agent's `search_local_lore` tool over a GameData database.
import 'dart:io';

import 'package:arklores/core/agent/tools/agent_tool.dart';
import 'package:arklores/core/agent/tools/search_local_lore.dart';
import 'package:arklores/core/gamedata/gamedata_knowledge_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../support/amiya_fixture.dart';
import '../../../support/gamedata_fixture.dart';
import '../../../support/sqlite.dart';
import '../../../support/temp_dir.dart';

void main() {
  late Directory dir;
  late String dbPath;

  setUpAll(useSqfliteFfi);
  setUp(() {
    dir = Directory.systemTemp.createTempSync('search_local_lore');
    dbPath = '${dir.path}/arklores_gamedata_zh.db';
  });
  tearDown(() => deleteTempDir(dir));

  Future<String> search(
    Map<String, dynamic> args, {
    Future<void> Function(Database db)? extra,
  }) async {
    await createAmiyaDb(dbPath, extra: extra);
    final store = GameDataKnowledgeStore(dbPath: dbPath);
    addTearDown(store.close);
    final result = await SearchLocalLoreTool(gameDataStore: store).execute(args);
    return (result as ToolExecutionResult).observation;
  }

  test('prefers GameData entity documents when available', () async {
    final observation = await search({'query': '阿米娅', 'top_k': 3});
    expect(observation, contains('Source Kind: GameData'));
    expect(observation, contains('Retrieval Type: entity_document'));
    expect(
      observation,
      contains(
        'Ranking Reason: entity document exact match; highest priority for summaries',
      ),
    );
    expect(observation, contains('Content Type: operator_profile_bundle'));
    expect(observation, contains('zh_CN/gamedata/excel/handbook_info_table.json'));
    expect(observation, contains('罗德岛的公开领袖'));
  });

  test('filters by content_type', () async {
    final observation = await search(
      {'query': '阿米娅', 'top_k': 3, 'content_type': 'operator_voice'},
    );
    expect(observation, contains('Content Type: operator_voice'));
    expect(observation, contains('博士，我们继续前进吧。'));
    expect(observation, isNot(contains('operator_handbook_profile')));
  });

  test('resolves aliases structurally', () async {
    final observation = await search({'query': 'Amiya', 'top_k': 3});
    expect(observation, contains('Source Kind: GameData'));
    expect(observation, contains('Entity ID: $amiyaId'));
    expect(observation, contains('Retrieval Type: entity_document'));
  });

  test('reopens the cached connection after the DB file is replaced', () async {
    await createAmiyaDb(dbPath);
    final store = GameDataKnowledgeStore(dbPath: dbPath);
    addTearDown(store.close);
    final tool = SearchLocalLoreTool(gameDataStore: store);
    Future<String> run(String q) async =>
        ((await tool.execute({'query': q, 'top_k': 3})) as ToolExecutionResult)
            .observation;

    expect(await run('阿米娅'), contains('Entity ID: $amiyaId'));
    // Not in the first file; a stale cached handle would keep saying so.
    expect(await run('测试新角色'), contains('No matching GameData result'));

    // An installer-style swap while the store holds a handle to the old file.
    final replaced = '${dir.path}/replaced_gamedata.db';
    await createAmiyaDb(
      replaced,
      extra: (db) => insertEntity(db, 'char_999_test', '测试新角色'),
    );
    await File(dbPath).delete();
    await File(replaced).rename(dbPath);

    expect(await run('测试新角色'), contains('Entity ID: char_999_test'));
  },
      // Replacing a file another handle keeps open needs POSIX semantics (the
      // app runs on Android); Windows locks open files.
      skip: Platform.isWindows ? 'requires POSIX open-file replacement' : false,);

  test('uses entity document FTS for compound queries', () async {
    final observation = await search({'query': '阿米娅 罗德岛 公开领袖', 'top_k': 3});
    expect(observation, contains('Retrieval Type: entity_document_fts'));
    expect(observation, contains('Content Type: operator_profile_bundle'));
    expect(observation, contains('阿米娅是罗德岛的公开领袖'));
  });

  test('keeps observations bounded', () async {
    final observation = await search(
      {'query': '长篇测试', 'top_k': 3},
      extra: (db) => insertRecord(
        db,
        'record_long_lore',
        contentType: 'story_dialogue',
        subtype: 'event',
        content: '长篇测试 ${List.filled(1600, '剧情线索').join()} END_MARKER',
        sourcePath: 'zh_CN/gamedata/story/long_lore.txt',
        fields: {
          'entity_id': 'event_long_lore',
          'entity_name': '长篇测试',
          'title': '长篇测试',
          'section': '剧情',
          'raw_id': 'long_lore',
        },
      ),
    );
    expect(observation.length, lessThanOrEqualTo(5200));
    expect(observation, contains('Content Excerpt:'));
    expect(observation, contains('[truncated]'));
    expect(observation, isNot(contains('END_MARKER')));
  });

  group('disambiguation', () {
    test('an exact alias shared by two entities lists both', () async {
      final observation =
          await search({'query': 'Amiya', 'top_k': 3}, extra: addAmbiguousAmiya);
      expect(observation, contains('Ambiguous GameData entity query'));
      expect(observation, contains('1. $amiyaId'));
      expect(observation, contains('2. token_amiya_memory'));
      expect(observation, contains('候选实体（请用 Entity ID 消歧）'));
    });

    test('an explicit entity_id skips it', () async {
      final observation = await search(
        {'query': 'Amiya', 'top_k': 3, 'entity_id': amiyaId},
        extra: addAmbiguousAmiya,
      );
      expect(observation, isNot(contains('Ambiguous')));
    });

    test('an entity-id literal resolves and searches by id', () async {
      final observation = await search({'query': amiyaId, 'top_k': 3});
      expect(observation, contains('Entity ID: $amiyaId'));
    });
  });

  group('search modes and intents', () {
    test('summary mode announces its plan and adds story context', () async {
      final observation = await search(
        {'query': '阿米娅', 'top_k': 4, 'search_mode': 'summary'},
        extra: (db) => addAmiyaStoryChunk(db, withEntityId: true),
      );
      expect(observation, contains('Retrieval Plan: summary mode'));
      expect(observation, contains('Retrieval Type: entity_document'));
      expect(observation, contains('Retrieval Type: summary_story_context'));
      expect(observation, contains('切尔诺伯格行动中，阿米娅与博士会合。'));
    });

    test('a story intent finds story chunks without an entity_id', () async {
      final observation = await search(
        {'query': '阿米娅 主线', 'top_k': 3},
        extra: addAmiyaStoryChunk,
      );
      expect(observation, contains('Retrieval Type: summary_story_context'));
      expect(observation, contains('切尔诺伯格行动中，阿米娅与博士会合。'));
      expect(observation, isNot(contains('No matching GameData result')));
    });

    test('a content word narrows to that content type', () async {
      final observation = await search({'query': '阿米娅 语音', 'top_k': 3});
      expect(observation, contains('Content Type: operator_voice'));
      expect(observation, contains('博士，我们继续前进吧。'));
    });

    test('compound queries fall back to AND over terms', () async {
      final observation = await search(
        {'query': '集成战略 收藏品', 'top_k': 3},
        extra: (db) => insertRecord(
          db,
          'record_roguelike_collectible',
          contentType: 'roguelike_topic',
          category: 'roguelike',
          subtype: 'topic',
          content: '在集成战略中，玩家可以获得各类收藏品并改变探索路线。',
          sourcePath: 'zh_CN/gamedata/excel/roguelike_topic_table.json',
          fields: {
            'entity_id': 'roguelike_collectible',
            'entity_name': '藏品说明',
            'title': '奇物设计师',
            'section': '集成战略',
            'raw_id': 'roguelike_collectible',
          },
        ),
      );
      expect(observation, contains('Content Type: roguelike_topic'));
      expect(observation, contains('各类收藏品'));
    });

    test('a broad enemy intent finds enemy profiles', () async {
      final observation = await search(
        {'query': '敌人介绍', 'top_k': 3},
        extra: (db) => insertRecord(
          db,
          'record_enemy_profile',
          contentType: 'enemy_profile',
          category: 'enemy',
          subtype: 'profile',
          content: '敌人介绍：感染生物，常见于各类作战区域。',
          sourcePath: 'zh_CN/gamedata/excel/enemy_handbook_table.json',
          fields: {
            'entity_id': 'enemy_1001',
            'entity_name': '源石虫',
            'title': '源石虫',
            'section': '敌人介绍',
            'raw_id': 'enemy_1001',
          },
        ),
      );
      expect(observation, contains('Content Type: enemy_profile'));
      expect(observation, contains('源石虫'));
    });

    test('an operator-record intent finds record stories', () async {
      final observation = await search(
        {'query': '干员秘录', 'top_k': 3},
        extra: (db) => insertRecord(
          db,
          'record_operator_memory',
          contentType: 'operator_record_story',
          subtype: 'operator_record',
          content: '干员秘录记录了阿米娅在罗德岛的片段。',
          sourcePath:
              'zh_CN/gamedata/story/[uc]info/obt/memory/story_amiya_1_1.txt',
          fields: {
            'entity_id': amiyaId,
            'entity_name': '阿米娅',
            'title': '阿米娅的干员秘录',
            'section': '干员秘录',
            'raw_id': 'story_amiya_1_1',
          },
        ),
      );
      expect(observation, contains('Content Type: operator_record_story'));
      expect(observation, contains('阿米娅的干员秘录'));
    });
  });

  group('evidence mode', () {
    Map<String, Object?> chunk(String id, String story, String content,
            {String scopeType = 'activity', String raw = '',}) =>
        {
          'id': id,
          'game': 'arknights',
          'source_type': 'game_story',
          'content_category': 'story',
          'content_subtype': scopeType,
          'content_type': 'story_dialogue',
          'story_id': story,
          'scope_type': scopeType,
          'scope_id': 'act_test',
          'content': content,
          'source_path': 'zh_CN/gamedata/story/$story',
          'language': 'zh',
          'raw_id': raw,
        };

    test('intersects the story scope, the entity and the claim terms',
        () async {
      final observation = await search(
        {
          'query': '牺牲',
          'scope_id': 'activity:act_test',
          'entity_id': amiyaId,
          'search_mode': 'evidence',
        },
        extra: (db) async {
          await db.insert('story_scopes', {
            'story_id': 'activities/act_test/story_01.txt',
            'scope_type': 'activity',
            'scope_id': 'act_test',
            'source_path':
                'zh_CN/gamedata/story/activities/act_test/story_01.txt',
          });
          await db.insert(
            'lore_chunks',
            chunk('scoped_story_evidence', 'activities/act_test/story_01.txt',
                '阿米娅明确拒绝撤退，并选择牺牲自己保护其他人。',
                raw: 'story_01:3',),
          );
          await db.insert(
            'lore_chunks',
            chunk(
              'distant_scoped_story_evidence',
              'activities/act_test/story_00.txt',
              '牺牲${List.filled(80, '无关背景').join()}阿米娅出现在远处。',
              raw: 'story_00:1',
            ),
          );
        },
      );
      expect(observation, contains('Evidence Scope Match: yes'));
      expect(observation, contains('ID: scoped_story_evidence'));
      expect(observation, contains('选择牺牲自己'));
      expect(observation, isNot(contains('operator_profile_bundle')));
      expect(
        observation.indexOf('ID: scoped_story_evidence'),
        lessThan(observation.indexOf('ID: distant_scoped_story_evidence')),
      );
    });

    test('needs the canonical scope type and a non-empty claim term',
        () async {
      final observation = await search(
        {
          'query': '牺牲',
          'scope_id': 'activity:act_test',
          'entity_id': amiyaId,
          'search_mode': 'evidence',
        },
        extra: (db) => db.insert(
          'lore_chunks',
          chunk('same_scope_id_other_type', 'mainline/act_test/story_01.txt',
              '阿米娅选择牺牲自己。',
              scopeType: 'mainline',),
        ),
      );
      expect(observation, contains('No scoped direct candidate'));

      final store = GameDataKnowledgeStore(dbPath: dbPath);
      addTearDown(store.close);
      expect(
        await store.search(
          query: '',
          scopeId: 'mainline:act_test',
          entityId: amiyaId,
          searchMode: 'evidence',
        ),
        isEmpty,
      );
    });

    test('invalid and empty searches are guided to retry', () async {
      await createAmiyaDb(dbPath);
      final store = GameDataKnowledgeStore(dbPath: dbPath);
      addTearDown(store.close);
      final tool = SearchLocalLoreTool(gameDataStore: store);

      final missingIds = await tool
          .execute({'query': '离开', 'search_mode': 'evidence'}) as ToolExecutionResult;
      expect(missingIds.observation, contains('requires both'));

      final noCandidate = await tool.execute({
        'query': '测试范围 测试角色',
        'scope_id': 'activity:act_test',
        'entity_id': amiyaId,
        'search_mode': 'evidence',
      }) as ToolExecutionResult;
      expect(noCandidate.observation, contains('only one short claim'));
      expect(noCandidate.observation, contains('same scope_id and entity_id'));
    });
  });
}
