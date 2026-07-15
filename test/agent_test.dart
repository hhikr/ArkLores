import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:arklores/core/agent/react_loop.dart';
import 'package:arklores/core/agent/fact_check_agent.dart';
import 'package:arklores/core/agent/tools/agent_tool.dart';
import 'package:arklores/core/agent/tools/search_local_lore.dart';
import 'package:arklores/core/agent/tools/tool_registry.dart';
import 'package:arklores/core/gamedata/gamedata_installer.dart';
import 'package:arklores/core/gamedata/gamedata_knowledge_store.dart';
import 'package:arklores/core/llm/llm_client.dart';
import 'package:arklores/core/llm/openai_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late sqflite.DatabaseFactory? previousDatabaseFactory;
  late DebugPrintCallback previousDebugPrint;

  setUp(() async {
    sqfliteFfiInit();
    try {
      previousDatabaseFactory = sqflite.databaseFactory;
    } catch (_) {
      previousDatabaseFactory = null;
    }
    sqflite.databaseFactory = databaseFactoryFfi;
    tempDir = await Directory.systemTemp.createTemp('arklores_agent_test_');
    previousDebugPrint = debugPrint;
    debugPrint = (message, {wrapWidth}) {};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => tempDir.path,
    );
  });

  tearDown(() async {
    debugPrint = previousDebugPrint;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
    if (previousDatabaseFactory != null) {
      sqflite.databaseFactory = previousDatabaseFactory!;
    }
    await tempDir.delete(recursive: true);
  });

  group('SearchLocalLoreTool GameData tests', () {
    test('prefers GameData entity documents when available', () async {
      final dbPath = '${tempDir.path}/arklores_gamedata_zh.db';
      await _createGameDataTestDb(dbPath);
      final tool = SearchLocalLoreTool(
        gameDataStore: GameDataKnowledgeStore(dbPath: dbPath),
      );

      final result = await tool.execute({'query': '阿米娅', 'top_k': 3});

      expect(result, isA<ToolExecutionResult>());
      final observation = (result as ToolExecutionResult).observation;
      expect(observation, contains('Source Kind: GameData'));
      expect(observation, contains('Retrieval Type: entity_document'));
      expect(
        observation,
        contains(
          'Ranking Reason: entity document exact match; highest priority for summaries',
        ),
      );
      expect(observation, contains('Content Type: operator_profile_bundle'));
      expect(
        observation,
        contains('zh_CN/gamedata/excel/handbook_info_table.json'),
      );
      expect(observation, contains('罗德岛的公开领袖'));
    });

    test('filters GameData by content_type', () async {
      final dbPath = '${tempDir.path}/arklores_gamedata_zh.db';
      await _createGameDataTestDb(dbPath);
      final tool = SearchLocalLoreTool(
        gameDataStore: GameDataKnowledgeStore(dbPath: dbPath),
      );

      final result = await tool.execute({
        'query': '阿米娅',
        'top_k': 3,
        'content_type': 'operator_voice',
      });

      expect(result, isA<ToolExecutionResult>());
      final observation = (result as ToolExecutionResult).observation;
      expect(observation, contains('Content Type: operator_voice'));
      expect(observation, contains('博士，我们继续前进吧。'));
      expect(observation, isNot(contains('operator_handbook_profile')));
    });

    test('resolves GameData aliases structurally', () async {
      final dbPath = '${tempDir.path}/arklores_gamedata_zh.db';
      await _createGameDataTestDb(dbPath);
      final tool = SearchLocalLoreTool(
        gameDataStore: GameDataKnowledgeStore(dbPath: dbPath),
      );

      final result = await tool.execute({'query': 'Amiya', 'top_k': 3});

      expect(result, isA<ToolExecutionResult>());
      final observation = (result as ToolExecutionResult).observation;
      expect(observation, contains('Source Kind: GameData'));
      expect(observation, contains('Entity ID: char_002_amiya'));
      expect(observation, contains('Retrieval Type: entity_document'));
    });

    test('uses entity document FTS for compound queries', () async {
      final dbPath = '${tempDir.path}/arklores_gamedata_zh.db';
      await _createGameDataTestDb(dbPath);
      final tool = SearchLocalLoreTool(
        gameDataStore: GameDataKnowledgeStore(dbPath: dbPath),
      );

      final result = await tool.execute({'query': '阿米娅 罗德岛 公开领袖', 'top_k': 3});

      expect(result, isA<ToolExecutionResult>());
      final observation = (result as ToolExecutionResult).observation;
      expect(observation, contains('Retrieval Type: entity_document_fts'));
      expect(observation, contains('Content Type: operator_profile_bundle'));
      expect(observation, contains('阿米娅是罗德岛的公开领袖'));
    });

    test('keeps GameData observations bounded', () async {
      final dbPath = '${tempDir.path}/arklores_gamedata_zh.db';
      await _createGameDataTestDb(dbPath);
      final db = await sqflite.openDatabase(dbPath);
      final longContent = '长篇测试 ${List.filled(1600, '剧情线索').join()} END_MARKER';
      await db.insert('normalized_records', {
        'id': 'record_long_lore',
        'game': 'arknights',
        'language': 'zh',
        'category': 'story',
        'subtype': 'event',
        'content_type': 'story_dialogue',
        'entity_id': 'event_long_lore',
        'entity_name': '长篇测试',
        'title': '长篇测试',
        'section': '剧情',
        'content': longContent,
        'source_path': 'zh_CN/gamedata/story/long_lore.txt',
        'raw_id': 'long_lore',
      });
      await db.close();

      final tool = SearchLocalLoreTool(
        gameDataStore: GameDataKnowledgeStore(dbPath: dbPath),
      );

      final result = await tool.execute({'query': '长篇测试', 'top_k': 3});

      expect(result, isA<ToolExecutionResult>());
      final observation = (result as ToolExecutionResult).observation;
      expect(observation.length, lessThanOrEqualTo(5200));
      expect(observation, contains('Content Excerpt:'));
      expect(observation, contains('[truncated]'));
      expect(observation, isNot(contains('END_MARKER')));
    });

    test('returns disambiguation candidates for exact alias collisions',
        () async {
      final dbPath = '${tempDir.path}/arklores_gamedata_zh.db';
      await _createGameDataTestDb(dbPath);
      await _insertAmbiguousAmiyaCandidate(dbPath);
      final tool = SearchLocalLoreTool(
        gameDataStore: GameDataKnowledgeStore(dbPath: dbPath),
      );

      final result = await tool.execute({'query': 'Amiya', 'top_k': 3});

      expect(result, isA<ToolExecutionResult>());
      final observation = (result as ToolExecutionResult).observation;
      expect(observation, contains('Ambiguous GameData entity query'));
      expect(observation, contains('Entity ID: char_002_amiya'));
      expect(observation, contains('Entity ID: token_amiya_memory'));
      expect(
          observation, contains('call search_local_lore again with entity_id'));
    });

    test('summary mode announces retrieval plan and includes story context',
        () async {
      final dbPath = '${tempDir.path}/arklores_gamedata_zh.db';
      await _createGameDataTestDb(dbPath);
      await _insertAmiyaStoryChunk(dbPath, withEntityId: true);
      final tool = SearchLocalLoreTool(
        gameDataStore: GameDataKnowledgeStore(dbPath: dbPath),
      );

      final result = await tool.execute({
        'query': '阿米娅',
        'top_k': 4,
        'search_mode': 'summary',
      });

      expect(result, isA<ToolExecutionResult>());
      final observation = (result as ToolExecutionResult).observation;
      expect(observation, contains('Retrieval Plan: summary mode'));
      expect(observation, contains('Retrieval Type: entity_document'));
      expect(observation, contains('Retrieval Type: summary_story_context'));
      expect(observation, contains('切尔诺伯格行动中，阿米娅与博士会合。'));
    });

    test('story intent query retrieves story chunks without entity_id',
        () async {
      final dbPath = '${tempDir.path}/arklores_gamedata_zh.db';
      await _createGameDataTestDb(dbPath);
      await _insertAmiyaStoryChunk(dbPath);
      final tool = SearchLocalLoreTool(
        gameDataStore: GameDataKnowledgeStore(dbPath: dbPath),
      );

      final result = await tool.execute({
        'query': '阿米娅 主线',
        'top_k': 3,
      });

      expect(result, isA<ToolExecutionResult>());
      final observation = (result as ToolExecutionResult).observation;
      expect(observation, contains('Retrieval Type: summary_story_context'));
      expect(observation, contains('切尔诺伯格行动中，阿米娅与博士会合。'));
      expect(observation, isNot(contains('No matching GameData result')));
    });

    test('normalizes entity content intent terms', () async {
      final dbPath = '${tempDir.path}/arklores_gamedata_zh.db';
      await _createGameDataTestDb(dbPath);
      final tool = SearchLocalLoreTool(
        gameDataStore: GameDataKnowledgeStore(dbPath: dbPath),
      );

      final result = await tool.execute({
        'query': '阿米娅 语音',
        'top_k': 3,
      });

      expect(result, isA<ToolExecutionResult>());
      final observation = (result as ToolExecutionResult).observation;
      expect(observation, contains('Content Type: operator_voice'));
      expect(observation, contains('博士，我们继续前进吧。'));
      expect(observation, isNot(contains('No matching GameData result')));
    });

    test('uses term AND fallback for compound roguelike queries', () async {
      final dbPath = '${tempDir.path}/arklores_gamedata_zh.db';
      await _createGameDataTestDb(dbPath);
      final db = await sqflite.openDatabase(dbPath);
      await db.insert('normalized_records', {
        'id': 'record_roguelike_collectible',
        'game': 'arknights',
        'language': 'zh',
        'category': 'roguelike',
        'subtype': 'topic',
        'content_type': 'roguelike_topic',
        'entity_id': 'roguelike_collectible',
        'entity_name': '藏品说明',
        'title': '奇物设计师',
        'section': '集成战略',
        'content': '在集成战略中，玩家可以获得各类收藏品并改变探索路线。',
        'source_path': 'zh_CN/gamedata/excel/roguelike_topic_table.json',
        'raw_id': 'roguelike_collectible',
      });
      await db.close();
      final tool = SearchLocalLoreTool(
        gameDataStore: GameDataKnowledgeStore(dbPath: dbPath),
      );

      final result = await tool.execute({
        'query': '集成战略 收藏品',
        'top_k': 3,
      });

      expect(result, isA<ToolExecutionResult>());
      final observation = (result as ToolExecutionResult).observation;
      expect(observation, contains('Content Type: roguelike_topic'));
      expect(observation, contains('各类收藏品'));
      expect(observation, isNot(contains('No matching GameData result')));
    });

    test('normalizes broad enemy intent to enemy profiles', () async {
      final dbPath = '${tempDir.path}/arklores_gamedata_zh.db';
      await _createGameDataTestDb(dbPath);
      final db = await sqflite.openDatabase(dbPath);
      await db.insert('normalized_records', {
        'id': 'record_enemy_profile',
        'game': 'arknights',
        'language': 'zh',
        'category': 'enemy',
        'subtype': 'profile',
        'content_type': 'enemy_profile',
        'entity_id': 'enemy_1001',
        'entity_name': '源石虫',
        'title': '源石虫',
        'section': '敌人介绍',
        'content': '敌人介绍：感染生物，常见于各类作战区域。',
        'source_path': 'zh_CN/gamedata/excel/enemy_handbook_table.json',
        'raw_id': 'enemy_1001',
      });
      await db.close();
      final tool = SearchLocalLoreTool(
        gameDataStore: GameDataKnowledgeStore(dbPath: dbPath),
      );

      final result = await tool.execute({
        'query': '敌人介绍',
        'top_k': 3,
      });

      expect(result, isA<ToolExecutionResult>());
      final observation = (result as ToolExecutionResult).observation;
      expect(observation, contains('Content Type: enemy_profile'));
      expect(observation, contains('源石虫'));
      expect(observation, isNot(contains('No matching GameData result')));
    });

    test('normalizes operator record intent to record stories', () async {
      final dbPath = '${tempDir.path}/arklores_gamedata_zh.db';
      await _createGameDataTestDb(dbPath);
      final db = await sqflite.openDatabase(dbPath);
      await db.insert('normalized_records', {
        'id': 'record_operator_memory',
        'game': 'arknights',
        'language': 'zh',
        'category': 'story',
        'subtype': 'operator_record',
        'content_type': 'operator_record_story',
        'entity_id': 'char_002_amiya',
        'entity_name': '阿米娅',
        'title': '阿米娅的干员秘录',
        'section': '干员秘录',
        'content': '干员秘录记录了阿米娅在罗德岛的片段。',
        'source_path':
            'zh_CN/gamedata/story/[uc]info/obt/memory/story_amiya_1_1.txt',
        'raw_id': 'story_amiya_1_1',
      });
      await db.close();
      final tool = SearchLocalLoreTool(
        gameDataStore: GameDataKnowledgeStore(dbPath: dbPath),
      );

      final result = await tool.execute({
        'query': '干员秘录',
        'top_k': 3,
      });

      expect(result, isA<ToolExecutionResult>());
      final observation = (result as ToolExecutionResult).observation;
      expect(observation, contains('Content Type: operator_record_story'));
      expect(observation, contains('阿米娅的干员秘录'));
      expect(observation, isNot(contains('No matching GameData result')));
    });

    test('intersects resolved story scope, entity, and claim terms', () async {
      final dbPath = '${tempDir.path}/arklores_gamedata_zh.db';
      await _createGameDataTestDb(dbPath);
      final db = await sqflite.openDatabase(dbPath);
      await db.insert('story_scopes', {
        'story_id': 'activities/act_test/story_01.txt',
        'scope_type': 'activity',
        'scope_id': 'act_test',
        'source_path': 'zh_CN/gamedata/story/activities/act_test/story_01.txt',
      });
      await db.insert('lore_chunks', {
        'id': 'scoped_story_evidence',
        'game': 'arknights',
        'source_type': 'game_story',
        'content_category': 'story',
        'content_subtype': 'activity',
        'content_type': 'story_dialogue',
        'story_id': 'activities/act_test/story_01.txt',
        'scope_type': 'activity',
        'scope_id': 'act_test',
        'page_title': 'story_01',
        'section': '剧情文本',
        'content': '阿米娅明确拒绝撤退，并选择牺牲自己保护其他人。',
        'source_path': 'zh_CN/gamedata/story/activities/act_test/story_01.txt',
        'language': 'zh',
        'raw_id': 'story_01:3',
      });
      await db.insert('lore_chunks', {
        'id': 'distant_scoped_story_evidence',
        'game': 'arknights',
        'source_type': 'game_story',
        'content_category': 'story',
        'content_subtype': 'activity',
        'content_type': 'story_dialogue',
        'story_id': 'activities/act_test/story_00.txt',
        'scope_type': 'activity',
        'scope_id': 'act_test',
        'content': '牺牲${List.filled(80, '无关背景').join()}阿米娅出现在远处。',
        'source_path': 'zh_CN/gamedata/story/activities/act_test/story_00.txt',
        'language': 'zh',
        'raw_id': 'story_00:1',
      });
      await db.close();
      final tool = SearchLocalLoreTool(
        gameDataStore: GameDataKnowledgeStore(dbPath: dbPath),
      );

      final result = await tool.execute({
        'query': '牺牲',
        'scope_id': 'activity:act_test',
        'entity_id': 'char_002_amiya',
        'search_mode': 'evidence',
      }) as ToolExecutionResult;

      expect(result.observation, contains('Evidence Scope Match: yes'));
      expect(result.observation, contains('scoped_story_evidence'));
      expect(result.observation, contains('选择牺牲自己'));
      expect(result.observation, isNot(contains('operator_profile_bundle')));
      expect(
        result.observation.indexOf('ID: scoped_story_evidence'),
        lessThan(
          result.observation.indexOf('ID: distant_scoped_story_evidence'),
        ),
      );
    });

    test('requires canonical scope type and a non-empty claim term', () async {
      final dbPath = '${tempDir.path}/arklores_gamedata_zh.db';
      await _createGameDataTestDb(dbPath);
      final db = await sqflite.openDatabase(dbPath);
      await db.insert('lore_chunks', {
        'id': 'same_scope_id_other_type',
        'game': 'arknights',
        'source_type': 'game_story',
        'content_category': 'story',
        'content_subtype': 'mainline',
        'content_type': 'story_dialogue',
        'story_id': 'mainline/act_test/story_01.txt',
        'scope_type': 'mainline',
        'scope_id': 'act_test',
        'content': '阿米娅选择牺牲自己。',
        'language': 'zh',
      });
      await db.close();
      final store = GameDataKnowledgeStore(dbPath: dbPath);
      final tool = SearchLocalLoreTool(gameDataStore: store);

      final wrongScope = await tool.execute({
        'query': '牺牲',
        'scope_id': 'activity:act_test',
        'entity_id': 'char_002_amiya',
        'search_mode': 'evidence',
      }) as ToolExecutionResult;
      expect(
        wrongScope.observation,
        contains('No scoped direct candidate'),
      );

      final emptyTerms = await store.search(
        query: '',
        scopeId: 'mainline:act_test',
        entityId: 'char_002_amiya',
        searchMode: 'evidence',
      );
      expect(emptyTerms, isEmpty);
    });

    test('guides invalid and empty scoped evidence searches to retry',
        () async {
      final dbPath = '${tempDir.path}/arklores_gamedata_zh.db';
      await _createGameDataTestDb(dbPath);
      final tool = SearchLocalLoreTool(
        gameDataStore: GameDataKnowledgeStore(dbPath: dbPath),
      );

      final missingIds = await tool.execute({
        'query': '离开',
        'search_mode': 'evidence',
      }) as ToolExecutionResult;
      expect(missingIds.observation, contains('requires both'));

      final noCandidate = await tool.execute({
        'query': '测试范围 测试角色',
        'scope_id': 'activity:act_test',
        'entity_id': 'char_002_amiya',
        'search_mode': 'evidence',
      }) as ToolExecutionResult;
      expect(noCandidate.observation, contains('only one short claim'));
      expect(noCandidate.observation, contains('same scope_id and entity_id'));
    });
  });

  group('GameDataInstaller tests', () {
    test('validates database before replacing installed DB', () async {
      final validDbPath = '${tempDir.path}/valid_gamedata.db';
      await _createGameDataTestDb(validDbPath);
      await _insertAmiyaStoryChunk(validDbPath);
      final installer = GameDataInstaller(installDirectory: tempDir);

      await installer.installFromBytes(
        await File(validDbPath).readAsBytes(),
        overwrite: true,
      );

      final status = await installer.getStatus();
      expect(status.installed, isTrue);
      expect(status.manifest['schema_version'], '2');
      expect(status.entityCount, '1');
    });

    test('rejects invalid database without replacing existing install',
        () async {
      final validDbPath = '${tempDir.path}/valid_gamedata.db';
      await _createGameDataTestDb(validDbPath);
      await _insertAmiyaStoryChunk(validDbPath);
      final installer = GameDataInstaller(installDirectory: tempDir);
      await installer.installFromBytes(
        await File(validDbPath).readAsBytes(),
        overwrite: true,
      );
      final installedPath = '${tempDir.path}/arklores_gamedata_zh.db';
      final beforeBytes = await File(installedPath).readAsBytes();

      expect(
        () => installer.installFromBytes(
          const [1, 2, 3, 4],
          overwrite: true,
        ),
        throwsA(isA<Object>()),
      );

      expect(await File(installedPath).readAsBytes(), beforeBytes);
    });

    test('rejects legacy schema before replacing the installed DB', () async {
      final legacyPath = '${tempDir.path}/legacy_gamedata.db';
      await _createGameDataTestDb(legacyPath);
      final db = await sqflite.openDatabase(legacyPath);
      await db.update(
        'gamedata_manifest',
        {'value': '1'},
        where: 'key = ?',
        whereArgs: ['schema_version'],
      );
      await db.close();
      final installer = GameDataInstaller(installDirectory: tempDir);
      final legacyBytes = await File(legacyPath).readAsBytes();

      expect(
        () => installer.installFromBytes(
          legacyBytes,
          overwrite: true,
        ),
        throwsA(isA<StateError>().having(
          (error) => '$error',
          'message',
          contains('incompatible'),
        )),
      );
    });
  });

  group('ReAct Loop Tests', () {
    test('runs, executes tools, and yields final answer', () async {
      final registry = ToolRegistry();
      registry.register(_StaticSearchTool());

      final reactLoop = ReActLoop(
        llmClient: _MockLLMClient(),
        toolRegistry: registry,
        maxIterations: 3,
      );

      final events = await reactLoop
          .run(
            systemPrompt: 'You are a helper.',
            chatHistory: [],
            userQuery: 'Who is W?',
          )
          .toList();

      final eventTypes = events.map((e) => e.type).toList();
      expect(eventTypes, contains(ReActEventType.thought));
      expect(eventTypes, contains(ReActEventType.toolCall));
      expect(eventTypes, contains(ReActEventType.toolObservation));
      expect(eventTypes, contains(ReActEventType.finalAnswerToken));
      expect(eventTypes, contains(ReActEventType.complete));

      final finalAnswerEvent =
          events.firstWhere((e) => e.type == ReActEventType.finalAnswerToken);
      expect(finalAnswerEvent.content, contains('W is a mercenary'));
    });

    test('parses loose Action Input key-value maps', () async {
      final registry = ToolRegistry();
      final tool = _CaptureTool();
      registry.register(tool);

      final reactLoop = ReActLoop(
        llmClient: _LooseActionInputLLMClient(),
        toolRegistry: registry,
        maxIterations: 2,
      );

      final events = await reactLoop
          .run(
            systemPrompt: 'You are a helper.',
            chatHistory: [],
            userQuery: '查缪因',
          )
          .toList();

      expect(tool.lastArgs?['query'], '缪因');
      expect(tool.lastArgs?['top_k'], 5);
      expect(
        events
            .where((e) => e.type == ReActEventType.finalAnswerToken)
            .single
            .content,
        contains('done'),
      );
    });

    test('ignores prose after Action Input JSON', () async {
      final registry = ToolRegistry();
      final tool = _CaptureTool();
      registry.register(tool);

      final reactLoop = ReActLoop(
        llmClient: _TrailingActionInputLLMClient(),
        toolRegistry: registry,
        maxIterations: 2,
      );

      final events = await reactLoop
          .run(
            systemPrompt: 'You are a helper.',
            chatHistory: [],
            userQuery: '查阿米娅',
          )
          .toList();

      expect(tool.lastArgs?['query'], '阿米娅 档案 干员 罗德岛');
      expect(tool.lastArgs?['top_k'], 5);
      expect(
        events
            .where((e) => e.type == ReActEventType.finalAnswerToken)
            .single
            .content,
        contains('done'),
      );
    });

    test('keeps the registered action name when providers add action metadata',
        () async {
      final registry = ToolRegistry();
      final tool = _CaptureTool();
      registry.register(tool);
      final loop = ReActLoop(
        llmClient: _ActionMetadataLLMClient(),
        toolRegistry: registry,
        maxIterations: 2,
      );

      await loop
          .run(systemPrompt: 'test', chatHistory: const [], userQuery: 'test')
          .toList();

      expect(tool.lastArgs?['query'], 'scope entity relation');
    });

    test('parses an action placed directly after sentence punctuation',
        () async {
      final registry = ToolRegistry();
      final tool = _CaptureTool();
      registry.register(tool);
      final loop = ReActLoop(
        llmClient: _PunctuatedActionLLMClient(),
        toolRegistry: registry,
        maxIterations: 2,
      );

      await loop
          .run(systemPrompt: 'test', chatHistory: const [], userQuery: 'test')
          .toList();

      expect(tool.lastArgs?['query'], '米格鲁');
    });

    test('requires a tool call before accepting a final answer when configured',
        () async {
      final registry = ToolRegistry();
      final tool = _CaptureTool();
      registry.register(tool);
      final loop = ReActLoop(
        llmClient: _EarlyFinalThenActionLLMClient(),
        toolRegistry: registry,
        maxIterations: 3,
        minimumToolCalls: 1,
      );

      final events = await loop
          .run(systemPrompt: 'test', chatHistory: const [], userQuery: 'test')
          .toList();

      expect(tool.lastArgs?['query'], 'required evidence');
      expect(
        events
            .where((event) => event.type == ReActEventType.finalAnswerToken)
            .single
            .content,
        'verified',
      );
    });

    test('does not treat handbook metadata as a Book source claim', () async {
      final loop = ReActLoop(
        llmClient: _HandbookAnswerLLMClient(),
        toolRegistry: ToolRegistry(),
      );
      final events = await loop
          .run(systemPrompt: 'test', chatHistory: const [], userQuery: 'test')
          .toList();
      final answer = events
          .where((event) => event.type == ReActEventType.finalAnswerToken)
          .single
          .content;
      expect(answer, contains('operator_handbook_profile'));
      expect(answer, isNot(contains('mentions Book evidence')));
    });

    test('reports empty final answers', () async {
      final reactLoop = ReActLoop(
        llmClient: _EmptyFinalAnswerLLMClient(),
        toolRegistry: ToolRegistry(),
        maxIterations: 1,
      );

      final events = await reactLoop
          .run(
            systemPrompt: 'You are a helper.',
            chatHistory: [],
            userQuery: 'empty',
          )
          .toList();

      expect(events.any((e) => e.type == ReActEventType.error), isTrue);
      expect(
        events.firstWhere((e) => e.type == ReActEventType.error).content,
        contains('empty final answer'),
      );
    });

    test('reports truncated ReAct steps', () async {
      final reactLoop = ReActLoop(
        llmClient: _TruncatedLLMClient(),
        toolRegistry: ToolRegistry(),
        maxIterations: 1,
      );

      final events = await reactLoop
          .run(
            systemPrompt: 'You are a helper.',
            chatHistory: [],
            userQuery: 'truncate',
          )
          .toList();

      expect(events.any((e) => e.type == ReActEventType.error), isTrue);
      expect(
        events.firstWhere((e) => e.type == ReActEventType.error).content,
        contains('truncated'),
      );
    });

    test('fallback warns about unsupported source claims', () async {
      final registry = ToolRegistry();
      registry.register(_NoMatchTool());
      final llm = _UnsupportedSourceFallbackLLMClient();
      final reactLoop = ReActLoop(
        llmClient: llm,
        toolRegistry: registry,
        maxIterations: 1,
      );

      final events = await reactLoop
          .run(
            systemPrompt: 'You are a helper.',
            chatHistory: [],
            userQuery: '阿米娅',
          )
          .toList();

      expect(llm.fallbackPrompt, contains('Wiki evidence available: no'));
      final answer = events
          .where((e) => e.type == ReActEventType.finalAnswerToken)
          .single
          .content;
      expect(answer, contains('Source warning'));
      expect(answer, contains('did not retrieve any observation'));
    });

    test('fallback counts current GameData no-result observations', () async {
      final registry = ToolRegistry();
      registry.register(_CurrentNoMatchTool());
      final llm = _UnsupportedSourceFallbackLLMClient();
      final reactLoop = ReActLoop(
        llmClient: llm,
        toolRegistry: registry,
        maxIterations: 1,
      );

      await reactLoop
          .run(
            systemPrompt: 'You are a helper.',
            chatHistory: [],
            userQuery: '阿米娅 主线',
          )
          .toList();

      expect(llm.fallbackPrompt, contains('Empty/error observations seen: 1'));
      expect(
        llm.fallbackPrompt,
        contains('Do not add well-known lore'),
      );
    });
  });

  group('FactCheck Agent Tests', () {
    test('keeps supported verdict only after directed GameData searches',
        () async {
      final llm = _FactCheckLLMClient();
      final tool = _FactCheckSearchTool();
      final agent = FactCheckAgent(llmClient: llm, searchTool: tool);

      final events = await agent.checkClaim(claim: '阿米娅是罗德岛的领袖吗？').toList();

      expect(tool.queries, ['阿米娅 罗德岛 身份', '阿米娅 领袖 反证']);
      expect(
        events
            .where((event) => event.type == ReActEventType.finalAnswerToken)
            .single
            .content,
        startsWith('[FACT_CHECK_VERDICT:supported]'),
      );
      expect(llm.systemPrompt, contains('仅使用 search_local_lore'));
      expect(llm.systemPrompt, isNot(contains('search_wiki')));
    });

    test('downgrades unsupported supported verdict to unavailable', () {
      final verdict = validateFactCheckVerdict(
        '[FACT_CHECK_VERDICT:supported]\n模型记忆说这是正确的。',
        const ['No matching GameData result found for "未知命题".'],
      );
      expect(verdict, FactCheckVerdict.unavailable);
    });

    test('keeps refuted verdict with an actual GameData record', () {
      final verdict = validateFactCheckVerdict(
        '[FACT_CHECK_VERDICT:refuted]',
        const [
          '=== Result #1 ===\nSource Kind: GameData\nEvidence Scope Match: yes\nEvidence Level: direct candidate\nSource Path: a.json\nRaw ID: a',
        ],
      );
      expect(verdict, FactCheckVerdict.refuted);
    });

    test('maps entity ambiguity without records to uncertain', () {
      final verdict = validateFactCheckVerdict(
        '[FACT_CHECK_VERDICT:uncertain]',
        const [
          'Ambiguous GameData entity query\n=== Candidate #1 ===\nSource Kind: GameData',
        ],
      );
      expect(verdict, FactCheckVerdict.uncertain);
    });

    test('maps empty coverage to unavailable', () {
      expect(
        validateFactCheckVerdict('[FACT_CHECK_VERDICT:uncertain]', const []),
        FactCheckVerdict.unavailable,
      );
    });

    test('passes prior claim and evidence marker to a follow-up', () async {
      final llm = _FactCheckLLMClient();
      final agent = FactCheckAgent(
        llmClient: llm,
        searchTool: _FactCheckSearchTool(),
      );
      await agent.checkClaim(
        claim: '那她什么时候加入的？',
        history: const [
          Message(role: MessageRole.user, content: '阿米娅属于罗德岛吗？'),
          Message(
            role: MessageRole.assistant,
            content: '[FACT_CHECK_VERDICT:supported] Source Path: a.json',
          ),
        ],
      ).toList();

      expect(
        llm.firstRequestMessages
            .any((message) => message.content.contains('阿米娅属于罗德岛')),
        isTrue,
      );
      expect(
        llm.firstRequestMessages
            .any((message) => message.content.contains('Source Path: a.json')),
        isTrue,
      );
    });

    test('logs the validated verdict through the shared ReAct logger',
        () async {
      final agent = FactCheckAgent(
        llmClient: _UnsupportedFactCheckLLMClient(),
        searchTool: _CurrentNoMatchTool(),
      );

      final events = await agent.checkClaim(claim: '未知命题').toList();
      expect(
        events
            .where((event) => event.type == ReActEventType.finalAnswerToken)
            .single
            .content,
        startsWith('[FACT_CHECK_VERDICT:unavailable]'),
      );

      final logDir = Directory('${tempDir.path}/ArkLores/agent_logs');
      final logFiles = await logDir
          .list()
          .where((entry) => entry is File && entry.path.endsWith('.log'))
          .cast<File>()
          .toList();
      expect(logFiles, hasLength(1));
      final log = await logFiles.single.readAsString();
      expect(log, contains('Agent  : FactCheck'));
      expect(log, contains('▶ TOOL CALL: search_local_lore'));
      expect(log, contains('No matching GameData result'));
      final loggedFinalAnswer = log.split('▶ FINAL ANSWER:').last;
      expect(
        loggedFinalAnswer,
        contains('[FACT_CHECK_VERDICT:unavailable]'),
      );
      expect(
        loggedFinalAnswer,
        isNot(contains('[FACT_CHECK_VERDICT:supported]')),
      );
    });
  });

  group('LLM Client Tests', () {
    test('OpenAICompatibleClient rejects invalid API key text clearly',
        () async {
      final client = OpenAICompatibleClient(
        config: const LLMConfig(
          chatApiKey: '截图中的完整报错具体内容为：下载失败',
        ),
        httpClient: MockClient((request) async {
          return http.Response('should not be called', 500);
        }),
      );

      expect(
        () => client.chatCompletion([Message.user('test')]),
        throwsA(
          isA<LLMException>().having(
            (e) => e.message,
            'message',
            contains('Please paste only the API key'),
          ),
        ),
      );
    });
  });
}

class _MockLLMClient extends LLMClient {
  int callCount = 0;

  @override
  Future<String> chat(
    List<Message> messages, {
    List<Map<String, dynamic>>? tools,
    double temperature = 0.7,
    int maxTokens = 2048,
    List<String>? stop,
  }) async {
    callCount++;
    if (callCount == 1) {
      return '''
Thought: I need to look up W in the local database.
Action: search_local_lore
Action Input: {"query": "W"}
''';
    }
    return '''
Thought: I have enough information to write the final answer.
Final Answer: W is a mercenary.
''';
  }

  @override
  Future<String> chatStream(
    List<Message> messages, {
    void Function(String token)? onToken,
    double temperature = 0.7,
    int maxTokens = 2048,
    List<String>? stop,
  }) async {
    return chat(
      messages,
      temperature: temperature,
      maxTokens: maxTokens,
      stop: stop,
    );
  }
}

class _FactCheckLLMClient extends LLMClient {
  int callCount = 0;
  String systemPrompt = '';
  List<Message> firstRequestMessages = const [];

  @override
  Future<String> chat(
    List<Message> messages, {
    List<Map<String, dynamic>>? tools,
    double temperature = 0.7,
    int maxTokens = 2048,
    List<String>? stop,
  }) async {
    callCount++;
    if (callCount == 1) {
      firstRequestMessages = List.of(messages);
      systemPrompt = messages.first.content;
      return 'Thought: 查身份支持证据。\nAction: search_local_lore\nAction Input: {"query":"阿米娅 罗德岛 身份"}';
    }
    if (callCount == 2) {
      return 'Thought: 查可能的反证。\nAction: search_local_lore\nAction Input: {"query":"阿米娅 领袖 反证"}';
    }
    return 'Thought: 证据足够。\nFinal Answer: [FACT_CHECK_VERDICT:supported]\n## 核查结论\n支持。';
  }

  @override
  Future<String> chatStream(
    List<Message> messages, {
    void Function(String token)? onToken,
    double temperature = 0.7,
    int maxTokens = 2048,
    List<String>? stop,
  }) =>
      chat(messages,
          temperature: temperature, maxTokens: maxTokens, stop: stop);
}

class _FactCheckSearchTool extends AgentTool {
  final queries = <String>[];

  @override
  String get name => 'search_local_lore';

  @override
  String get description => 'GameData-only fact-check search.';

  @override
  Map<String, dynamic> get parameters => {
        'type': 'object',
        'properties': {
          'query': {'type': 'string'},
        },
        'required': ['query'],
      };

  @override
  Future<dynamic> execute(Map<String, dynamic> arguments) async {
    queries.add(arguments['query'] as String);
    return const ToolExecutionResult(
      observation: '=== Result #1 ===\nSource Kind: GameData\n'
          'Evidence Scope Match: yes\nEvidence Level: direct candidate\n'
          'Content Type: operator_profile\nSource Path: character_table.json\n'
          'Raw ID: char_002_amiya\nContent Excerpt: 阿米娅是罗德岛的公开领袖。',
    );
  }
}

class _UnsupportedFactCheckLLMClient extends _MockLLMClient {
  @override
  Future<String> chat(
    List<Message> messages, {
    List<Map<String, dynamic>>? tools,
    double temperature = 0.7,
    int maxTokens = 2048,
    List<String>? stop,
  }) async {
    callCount++;
    if (callCount == 1) {
      return 'Thought: 检索本地证据。\nAction: search_local_lore\n'
          'Action Input: {"query":"未知命题"}';
    }
    return 'Thought: 完成。\nFinal Answer: '
        '[FACT_CHECK_VERDICT:supported]\n错误地声称支持。';
  }
}

class _CaptureTool extends AgentTool {
  Map<String, dynamic>? lastArgs;

  @override
  String get name => 'search_local_lore';

  @override
  String get description => 'Capture tool arguments for tests.';

  @override
  Map<String, dynamic> get parameters => {
        'type': 'object',
        'properties': {
          'query': {'type': 'string'},
          'top_k': {'type': 'integer'},
        },
        'required': ['query'],
      };

  @override
  Future<dynamic> execute(Map<String, dynamic> arguments) async {
    lastArgs = Map<String, dynamic>.of(arguments);
    return 'captured';
  }
}

class _StaticSearchTool extends AgentTool {
  @override
  String get name => 'search_local_lore';

  @override
  String get description => 'Returns a static search observation.';

  @override
  Map<String, dynamic> get parameters => {
        'type': 'object',
        'properties': {
          'query': {'type': 'string'},
        },
        'required': ['query'],
      };

  @override
  Future<dynamic> execute(Map<String, dynamic> arguments) async {
    return 'Source Kind: GameData\nContent Excerpt:\nW is a mercenary.';
  }
}

class _NoMatchTool extends AgentTool {
  @override
  String get name => 'search_local_lore';

  @override
  String get description => 'Always returns no matching records.';

  @override
  Map<String, dynamic> get parameters => {
        'type': 'object',
        'properties': {
          'query': {'type': 'string'},
        },
        'required': ['query'],
      };

  @override
  Future<dynamic> execute(Map<String, dynamic> arguments) async {
    return 'No matching records found in the database.';
  }
}

class _CurrentNoMatchTool extends AgentTool {
  @override
  String get name => 'search_local_lore';

  @override
  String get description => 'Returns current GameData no-result text.';

  @override
  Map<String, dynamic> get parameters => {
        'type': 'object',
        'properties': {
          'query': {'type': 'string'},
        },
        'required': ['query'],
      };

  @override
  Future<dynamic> execute(Map<String, dynamic> arguments) async {
    return 'No matching GameData result found for "${arguments['query']}". The local GameData knowledge DB is installed, but structured/FTS search returned no result.';
  }
}

class _LooseActionInputLLMClient extends _MockLLMClient {
  @override
  Future<String> chat(
    List<Message> messages, {
    List<Map<String, dynamic>>? tools,
    double temperature = 0.7,
    int maxTokens = 2048,
    List<String>? stop,
  }) async {
    callCount++;
    if (callCount == 1) {
      return '''
Thought: I need local lore.
Action: search_local_lore
Action Input: {query: 缪因, top_k: 5}
''';
    }
    return '''
Thought: I have enough information to answer.
Final Answer: done
''';
  }
}

class _TrailingActionInputLLMClient extends _MockLLMClient {
  @override
  Future<String> chat(
    List<Message> messages, {
    List<Map<String, dynamic>>? tools,
    double temperature = 0.7,
    int maxTokens = 2048,
    List<String>? stop,
  }) async {
    callCount++;
    if (callCount == 1) {
      return '''
Thought: I need local lore.
Action: search_local_lore
Action Input: {"query": "阿米娅 档案 干员 罗德岛", "top_k": 5}
Based on the search results, I should continue reasoning here by mistake.
''';
    }
    return '''
Thought: I have enough information to answer.
Final Answer: done
''';
  }
}

class _ActionMetadataLLMClient extends _MockLLMClient {
  @override
  Future<String> chat(
    List<Message> messages, {
    List<Map<String, dynamic>>? tools,
    double temperature = 0.7,
    int maxTokens = 2048,
    List<String>? stop,
  }) async {
    callCount++;
    if (callCount == 1) {
      return 'Action: search_local_lore\nAction Query: arg/search\n'
          'Action Tool: search_local_lore\n'
          'Action Input: {"query":"scope entity relation"}';
    }
    return 'Final Answer: done';
  }
}

class _PunctuatedActionLLMClient extends _MockLLMClient {
  @override
  Future<String> chat(
    List<Message> messages, {
    List<Map<String, dynamic>>? tools,
    double temperature = 0.7,
    int maxTokens = 2048,
    List<String>? stop,
  }) async {
    callCount++;
    if (callCount == 1) {
      return '现在查询实体。Action: search_local_lore\n'
          'Action Input: {"query":"米格鲁"}';
    }
    return 'Final Answer: done';
  }
}

class _EarlyFinalThenActionLLMClient extends _MockLLMClient {
  @override
  Future<String> chat(
    List<Message> messages, {
    List<Map<String, dynamic>>? tools,
    double temperature = 0.7,
    int maxTokens = 2048,
    List<String>? stop,
  }) async {
    callCount++;
    if (callCount == 1) return 'Final Answer: unverified';
    if (callCount == 2) {
      return 'Action: search_local_lore\n'
          'Action Input: {"query":"required evidence"}';
    }
    return 'Final Answer: verified';
  }
}

class _HandbookAnswerLLMClient extends _MockLLMClient {
  @override
  Future<String> chat(
    List<Message> messages, {
    List<Map<String, dynamic>>? tools,
    double temperature = 0.7,
    int maxTokens = 2048,
    List<String>? stop,
  }) async =>
      'Final Answer: Content Type: operator_handbook_profile';
}

class _EmptyFinalAnswerLLMClient extends _MockLLMClient {
  @override
  Future<String> chat(
    List<Message> messages, {
    List<Map<String, dynamic>>? tools,
    double temperature = 0.7,
    int maxTokens = 2048,
    List<String>? stop,
  }) async {
    return 'Thought: done\nFinal Answer:';
  }
}

class _TruncatedLLMClient extends _MockLLMClient {
  @override
  Future<ChatCompletionResult> chatCompletion(
    List<Message> messages, {
    List<Map<String, dynamic>>? tools,
    double temperature = 0.7,
    int maxTokens = 2048,
    List<String>? stop,
  }) async {
    return const ChatCompletionResult(
      content: 'Thought: too long',
      finishReason: 'length',
    );
  }
}

class _UnsupportedSourceFallbackLLMClient extends _MockLLMClient {
  String? fallbackPrompt;

  @override
  Future<String> chat(
    List<Message> messages, {
    List<Map<String, dynamic>>? tools,
    double temperature = 0.7,
    int maxTokens = 2048,
    List<String>? stop,
  }) async {
    callCount++;
    if (callCount == 1) {
      return '''
Thought: I need local lore.
Action: search_local_lore
Action Input: {"query": "阿米娅"}
''';
    }
    fallbackPrompt = messages.last.content;
    return '''
Final Answer: 我已通过 Wiki 获取了阿米娅的背景概述。
''';
  }
}

Future<void> _createGameDataTestDb(String path) async {
  final db = await sqflite.openDatabase(
    path,
    version: 1,
    onCreate: (db, version) async {
      await db.execute('''
        CREATE TABLE entities (
          id           TEXT PRIMARY KEY,
          name         TEXT NOT NULL,
          aliases      TEXT,
          entity_type  TEXT NOT NULL,
          source_type  TEXT NOT NULL,
          game         TEXT NOT NULL,
          source_path  TEXT,
          game_version TEXT,
          updated_at   INTEGER
        )
      ''');
      await db.execute('''
        CREATE TABLE entity_aliases (
          alias       TEXT NOT NULL,
          entity_id   TEXT NOT NULL,
          alias_type  TEXT NOT NULL,
          confidence  REAL NOT NULL DEFAULT 1.0,
          source_path TEXT,
          PRIMARY KEY (alias, entity_id, alias_type),
          FOREIGN KEY (entity_id) REFERENCES entities(id)
        )
      ''');
      await db.execute('''
        CREATE TABLE normalized_records (
          id               TEXT PRIMARY KEY,
          game             TEXT NOT NULL,
          language         TEXT NOT NULL DEFAULT 'zh',
          category         TEXT NOT NULL,
          subtype          TEXT NOT NULL,
          content_type     TEXT NOT NULL,
          entity_id        TEXT,
          entity_name      TEXT,
          parent_id        TEXT,
          parent_type      TEXT,
          title            TEXT,
          section          TEXT,
          speaker          TEXT,
          content          TEXT NOT NULL,
          source_path      TEXT NOT NULL,
          raw_id           TEXT,
          line_start       INTEGER,
          line_end         INTEGER,
          source_repo      TEXT,
          source_commit    TEXT,
          game_version     TEXT,
          updated_at       INTEGER
        )
      ''');
      await db.execute('''
        CREATE TABLE lore_chunks (
          id               TEXT PRIMARY KEY,
          game             TEXT NOT NULL,
          source_type      TEXT NOT NULL,
          content_category TEXT,
          content_subtype  TEXT,
          content_type     TEXT,
          entity_id        TEXT,
          story_id         TEXT,
          scope_type       TEXT,
          scope_id         TEXT,
          page_title       TEXT,
          section          TEXT,
          content          TEXT NOT NULL,
          source_path      TEXT,
          source_url       TEXT,
          line_start       INTEGER,
          line_end         INTEGER,
          speaker          TEXT,
          language         TEXT NOT NULL DEFAULT 'zh',
          game_version     TEXT,
          updated_at       INTEGER,
          raw_id           TEXT,
          retrieval_hint   TEXT
        )
      ''');
      await db.execute('''
        CREATE TABLE story_scopes (
          story_id    TEXT PRIMARY KEY,
          scope_type  TEXT NOT NULL,
          scope_id    TEXT NOT NULL,
          source_path TEXT NOT NULL
        )
      ''');
      await db.execute('''
        CREATE TABLE story_lines (
          id               TEXT PRIMARY KEY,
          game             TEXT NOT NULL,
          story_id         TEXT NOT NULL,
          story_title      TEXT,
          segment          TEXT,
          line_index       INTEGER NOT NULL,
          speaker          TEXT,
          content          TEXT NOT NULL,
          source_path      TEXT NOT NULL,
          raw_id           TEXT,
          language         TEXT NOT NULL DEFAULT 'zh',
          game_version     TEXT,
          updated_at       INTEGER
        )
      ''');
      await db.execute('''
        CREATE TABLE entity_documents (
          id                TEXT PRIMARY KEY,
          game              TEXT NOT NULL,
          language          TEXT NOT NULL DEFAULT 'zh',
          entity_id         TEXT NOT NULL,
          entity_name       TEXT NOT NULL,
          entity_type       TEXT NOT NULL,
          document_type     TEXT NOT NULL,
          title             TEXT NOT NULL,
          summary           TEXT,
          content           TEXT NOT NULL,
          source_paths      TEXT,
          source_record_ids TEXT,
          updated_at        INTEGER
        )
      ''');
      await db.execute('''
        CREATE TABLE gamedata_manifest (
          key   TEXT PRIMARY KEY,
          value TEXT NOT NULL
        )
      ''');
      await db.execute('''
        CREATE VIRTUAL TABLE entity_documents_fts USING fts5(
          entity_name,
          entity_type,
          document_type,
          title,
          summary,
          content,
          content='entity_documents',
          content_rowid='rowid',
          tokenize='trigram'
        )
      ''');
      await db.execute('''
        CREATE VIRTUAL TABLE lore_chunks_fts USING fts5(
          page_title,
          section,
          content,
          raw_id,
          content='lore_chunks',
          content_rowid='rowid',
          tokenize='trigram'
        )
      ''');
    },
  );

  await db.insert('gamedata_manifest', {
    'key': 'schema_version',
    'value': '2',
  });
  await db.insert('gamedata_manifest', {
    'key': 'entity_count',
    'value': '1',
  });
  await db.insert('gamedata_manifest', {
    'key': 'normalized_record_count',
    'value': '2',
  });
  await db.insert('gamedata_manifest', {
    'key': 'lore_chunk_count',
    'value': '1',
  });
  await db.insert('entities', {
    'id': 'char_002_amiya',
    'name': '阿米娅',
    'aliases': '["Amiya"]',
    'entity_type': 'operator',
    'source_type': 'operator_handbook_profile',
    'game': 'arknights',
    'source_path': 'zh_CN/gamedata/excel/character_table.json',
  });
  await db.insert('entity_aliases', {
    'alias': '阿米娅',
    'entity_id': 'char_002_amiya',
    'alias_type': 'canonical',
    'confidence': 1.0,
    'source_path': 'zh_CN/gamedata/excel/character_table.json',
  });
  await db.insert('entity_aliases', {
    'alias': 'Amiya',
    'entity_id': 'char_002_amiya',
    'alias_type': 'alias',
    'confidence': 0.8,
    'source_path': 'zh_CN/gamedata/excel/character_table.json',
  });
  await db.insert('normalized_records', {
    'id': 'record_profile_amiya',
    'game': 'arknights',
    'language': 'zh',
    'category': 'operator',
    'subtype': 'handbook_profile',
    'content_type': 'operator_handbook_profile',
    'entity_id': 'char_002_amiya',
    'entity_name': '阿米娅',
    'title': '阿米娅',
    'section': '档案资料',
    'content': '阿米娅是罗德岛的公开领袖，也是剧情中的核心角色。',
    'source_path': 'zh_CN/gamedata/excel/handbook_info_table.json',
    'raw_id': 'char_002_amiya',
  });
  await db.insert('normalized_records', {
    'id': 'record_voice_amiya',
    'game': 'arknights',
    'language': 'zh',
    'category': 'operator',
    'subtype': 'voice',
    'content_type': 'operator_voice',
    'entity_id': 'char_002_amiya',
    'entity_name': '阿米娅',
    'title': '交谈1',
    'section': '交谈1',
    'content': '博士，我们继续前进吧。',
    'source_path': 'zh_CN/gamedata/excel/charword_table.json',
    'raw_id': 'char_002_amiya_CN_001',
  });
  await db.insert('entity_documents', {
    'id': 'doc_operator_amiya',
    'game': 'arknights',
    'language': 'zh',
    'entity_id': 'char_002_amiya',
    'entity_name': '阿米娅',
    'entity_type': 'operator',
    'document_type': 'operator_profile_bundle',
    'title': '阿米娅',
    'summary': '阿米娅是罗德岛的公开领袖。',
    'content': '## 基础信息\n阿米娅是罗德岛的公开领袖。\n\n## 档案资料\n她也是剧情中的核心角色。',
    'source_paths':
        '["zh_CN/gamedata/excel/character_table.json","zh_CN/gamedata/excel/handbook_info_table.json"]',
    'source_record_ids': '["char_002_amiya"]',
  });
  await db.execute(
    "INSERT INTO entity_documents_fts(entity_documents_fts) VALUES('rebuild')",
  );
  await db.execute(
    "INSERT INTO lore_chunks_fts(lore_chunks_fts) VALUES('rebuild')",
  );
  await db.close();
}

Future<void> _insertAmbiguousAmiyaCandidate(String path) async {
  final db = await sqflite.openDatabase(path);
  await db.insert('entities', {
    'id': 'token_amiya_memory',
    'name': '阿米娅的记忆',
    'aliases': '["Amiya"]',
    'entity_type': 'item',
    'source_type': 'item_description',
    'game': 'arknights',
    'source_path': 'zh_CN/gamedata/excel/item_table.json',
  });
  await db.insert('entity_aliases', {
    'alias': 'Amiya',
    'entity_id': 'token_amiya_memory',
    'alias_type': 'alias',
    'confidence': 0.7,
    'source_path': 'zh_CN/gamedata/excel/item_table.json',
  });
  await db.close();
}

Future<void> _insertAmiyaStoryChunk(
  String path, {
  bool withEntityId = false,
}) async {
  final db = await sqflite.openDatabase(path);
  await db.insert('lore_chunks', {
    'id': 'chunk_story_amiya_chernobog',
    'game': 'arknights',
    'source_type': 'game_data',
    'content_category': 'story',
    'content_subtype': 'main',
    'content_type': 'story_dialogue',
    'entity_id': withEntityId ? 'char_002_amiya' : null,
    'story_id': 'main_00_01',
    'page_title': '切尔诺伯格行动',
    'section': '行动前',
    'content': '切尔诺伯格行动中，阿米娅与博士会合。',
    'source_path': 'zh_CN/gamedata/story/[uc]obt/main_00_01.txt',
    'language': 'zh',
    'raw_id': 'main_00_01',
  });
  await db.execute(
    "INSERT INTO lore_chunks_fts(lore_chunks_fts) VALUES('rebuild')",
  );
  await db.close();
}
