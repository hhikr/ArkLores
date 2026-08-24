import 'dart:convert';
import 'dart:io';

import 'package:arklores/core/agent/agent_prompts.dart';
import 'package:arklores/core/agent/react_loop.dart';
import 'package:arklores/core/agent/story_coverage_transform.dart';
import 'package:arklores/core/agent/summary_agent.dart';
import 'package:arklores/core/agent/tools/agent_tool.dart';
import 'package:arklores/core/agent/tools/get_story_map.dart';
import 'package:arklores/core/agent/tools/read_story_lines.dart';
import 'package:arklores/core/agent/tools/search_story_coverage.dart';
import 'package:arklores/core/gamedata/build/arknights_importer.dart';
import 'package:arklores/core/gamedata/build/gamedata_schema.dart';
import 'package:arklores/core/gamedata/build/story_coverage_builder.dart';
import 'package:arklores/core/gamedata/gamedata_knowledge_store.dart';
import 'package:arklores/core/llm/llm_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Synthetic 5-chapter fixture mirroring docs/AI_RETRIEVAL_OPTIMIZATION.md
/// §4.5: chapter 1 holds a foreshadowing line without the victim name or the
/// word 死亡; chapters 2-3 mislead toward 角色A; chapter 5 (past timeline)
/// reveals 角色B. R1 asserts the deterministic coverage layer (all
/// appearances, pagination, profiles, rare terms) and the coverage report
/// validation; the full mystery reasoning is P1.
void main() {
  late Directory tempDir;
  late Directory sourceDir;
  late String dbPath;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('arklores_coverage_test');
    sourceDir = await _writeFixtureSource(tempDir);
    dbPath = '${tempDir.path}/fixture.db';
    await _buildFixtureDb(sourceDir, dbPath);
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  group('pure coverage helpers', () {
    test('mergeMentionRuns merges consecutive lines and keeps gaps', () {
      expect(mergeMentionRuns(const []), isEmpty);
      expect(
        mergeMentionRuns(const [1, 2, 3, 5, 6]),
        [
          (1, 3, 3),
          (5, 6, 2),
        ],
      );
      expect(mergeMentionRuns(const [7]), [(7, 7, 1)]);
      // Unsorted input is sorted first.
      expect(mergeMentionRuns(const [4, 1, 2]), [(1, 2, 2), (4, 4, 1)]);
    });

    test('extractCharacterBigrams keeps only CJK bigrams', () {
      expect(extractCharacterBigrams('阿米娅博士'), {'阿米', '米娅', '娅博', '博士'});
      expect(extractCharacterBigrams('A米1。'), isEmpty);
      expect(extractCharacterBigrams(''), isEmpty);
    });
  });

  group('story coverage builder (schema v3)', () {
    test('writes entity_story_mentions with merged runs', () async {
      final store = GameDataKnowledgeStore(dbPath: dbPath);

      final victim = await store.searchStoryCoverage(entityId: 'char_victim');
      expect(
        victim.map((e) => e.storyId).toSet(),
        {
          'activities/act_fixture/level_fixture_c3.txt',
          'activities/act_fixture/level_fixture_c4.txt',
        },
      );

      final a = await store.searchStoryCoverage(entityId: 'char_a');
      final aStories = a.map((e) => e.storyId).toList();
      expect(
        aStories,
        containsAll([
          'activities/act_fixture/level_fixture_c1.txt',
          'activities/act_fixture/level_fixture_c2.txt',
          'activities/act_fixture/level_fixture_c3.txt',
        ]),
      );
      // Chapter 2 has 40 consecutive mention lines -> a single merged run
      // (importer line_index starts at 0).
      final c2 = a.firstWhere(
        (e) => e.storyId.endsWith('level_fixture_c2.txt'),
      );
      expect(c2.lineStart, 0);
      expect(c2.lineEnd, 39);
      expect(c2.mentionCount, 40);
      expect(c2.scopeId, 'activity:act_fixture');

      final b = await store.searchStoryCoverage(entityId: 'char_b');
      expect(
        b.map((e) => e.storyId).toSet(),
        {
          'activities/act_fixture/level_fixture_c4.txt',
          'activities/act_fixture/level_fixture_c5.txt',
        },
      );
      await store.close();
    });

    test('writes story_chapter_profiles with keyword hits and summary', () async {
      final store = GameDataKnowledgeStore(dbPath: dbPath);
      final profiles = await store.getStoryMap(
        scopeId: 'activity:act_fixture',
      );
      expect(profiles, hasLength(5));

      final c3 = profiles.firstWhere(
        (profile) => profile.storyId.endsWith('level_fixture_c3.txt'),
      );
      expect(c3.keywordHits.containsKey('死亡'), isTrue);
      expect(c3.entityDensity.containsKey('char_a'), isTrue);
      expect(c3.lineStart, 0);
      expect(c3.summary, isNotNull);
      expect(c3.speakerSet, isNotEmpty);
      await store.close();
    });

    test('writes rare_terms for low doc_freq bigrams only', () async {
      final db = await databaseFactory.openDatabase(dbPath);
      final rows = await db.rawQuery(
        'SELECT term, doc_freq FROM rare_terms WHERE term = ?',
        ['匕首'],
      );
      expect(rows, hasLength(1));
      expect(rows.first['doc_freq'], 3); // appears in c1, c4, c5.
      final all = await db.rawQuery(
        'SELECT COUNT(*) AS c FROM rare_terms WHERE doc_freq > ?',
        [rareTermMaxDocFreq],
      );
      expect(all.first['c'], 0);
      await db.close();
    });

    test('rebuilds story_lines_fts (external content table)', () async {
      final db = await databaseFactory.openDatabase(dbPath);
      final rows = await db.rawQuery(
        'SELECT COUNT(*) AS c FROM story_lines_fts',
      );
      // External content FTS stores index rows, not the text; the index must
      // be non-empty after rebuild.
      expect((rows.first['c'] as int), greaterThan(0));
      await db.close();
    });
  });

  group('coverage tools', () {
    test('search_story_coverage resolves query and returns markers', () async {
      final tool = SearchStoryCoverageTool(
        gameDataStore: GameDataKnowledgeStore(dbPath: dbPath),
      );
      final result = await tool.execute({'query': '角色B'}) as ToolExecutionResult;
      expect(result.observation, contains('Coverage Scopes: 1'));
      expect(result.observation, contains('Coverage Stories: 2'));
      expect(result.observation, contains('Scope: activity:act_fixture'));
      expect(result.observation, contains('level_fixture_c5.txt'));
    });

    test('search_story_coverage disambiguates exact aliases', () async {
      final tool = SearchStoryCoverageTool(
        gameDataStore: GameDataKnowledgeStore(dbPath: dbPath),
      );
      // Resolving a single exact candidate by query picks the entity.
      final result =
          await tool.execute({'query': '角色A'}) as ToolExecutionResult;
      expect(result.observation, contains('角色A (char_a)'));
    });

    test('read_story_lines paginates with page_token', () async {
      final tool = ReadStoryLinesTool(
        gameDataStore: GameDataKnowledgeStore(dbPath: dbPath),
      );
      final first = await tool.execute({
        'story_id': 'activities/act_fixture/level_fixture_c2.txt',
        'max_lines': 10,
      }) as ToolExecutionResult;
      expect(first.observation, contains('Read Lines: 10'));
      expect(first.observation, contains('Next Page Token: 10'));

      final second = await tool.execute({
        'story_id': 'activities/act_fixture/level_fixture_c2.txt',
        'max_lines': 10,
        'page_token': '11',
      }) as ToolExecutionResult;
      expect(second.observation, contains('Read Lines: 10'));
      expect(second.observation, contains('11 | 角色A'));

      final last = await tool.execute({
        'story_id': 'activities/act_fixture/level_fixture_c2.txt',
        'max_lines': 10,
        'page_token': '31',
      }) as ToolExecutionResult;
      expect(last.observation, contains('End of Story: yes'));
    });

    test('read_story_lines reports missing story distinctly', () async {
      final tool = ReadStoryLinesTool(
        gameDataStore: GameDataKnowledgeStore(dbPath: dbPath),
      );
      final result = await tool.execute(
        {'story_id': 'activities/act_fixture/level_missing.txt'},
      ) as ToolExecutionResult;
      expect(result.observation, contains('Story not found'));
    });

    test('get_story_map lists chapters of a scope', () async {
      final tool = GetStoryMapTool(
        gameDataStore: GameDataKnowledgeStore(dbPath: dbPath),
      );
      final result = await tool.execute(
        {'scope_id': 'activity:act_fixture'},
      ) as ToolExecutionResult;
      expect(result.observation, contains('Mapped Stories: 5'));
      expect(result.observation, contains('Keyword Hits: 死亡'));
      expect(result.observation, contains('Summary:'));
    });
  });

  group('coverage report transform', () {
    test('appends a truthful line when the answer lacks one', () {
      final observations = [
        'Scope: activity:act_fixture\nCoverage Scopes: 1\n'
            'Story: s1 | Lines: 1-5',
        'Story: s1\nScope: activity:act_fixture\nRead Lines: 5\n'
            'End of Story: yes',
      ];
      final out = validateCoverageReport(
        '角色B在第五章承认了真相。',
        observations,
      );
      expect(out, contains('Coverage: read=1 | mapped=0 | skipped=0'));
    });

    test('rewrites a fabricated read count to the honest value', () {
      final observations = [
        'Scope: activity:act_fixture\nCoverage Scopes: 2\n'
            'Scope: main:main\nCoverage Scopes: 2',
        'Story: s1\nScope: activity:act_fixture\nRead Lines: 5\n'
            'End of Story: yes',
        'Scope: main:main\nMapped Stories: 1',
      ];
      final out = validateCoverageReport(
        '角色B是凶手。\n\nCoverage: read=5 | mapped=3 | skipped=0',
        observations,
      );
      expect(out, isNot(contains('read=5')));
      expect(out, contains('Coverage: read=1 | mapped=1 | skipped=0'));
    });

    test('leaves non-narrative answers untouched', () {
      final out = validateCoverageReport(
        '阿米娅是罗德岛的公开领袖。',
        ['Source Kind: GameData\n=== Result #1 ==='],
      );
      expect(out, '阿米娅是罗德岛的公开领袖。');
    });
  });

  group('Summary agent narrative workflow', () {
    test('runs coverage -> map -> read and normalizes the coverage line',
        () async {
      final llm = _ScriptedCoverageLLMClient();
      final agent = SummaryAgent(
        llmClient: llm,
        gameDataStore: GameDataKnowledgeStore(dbPath: dbPath),
      );

      final events = await agent
          .generateSummary(query: '角色B的剧情')
          .toList();
      final toolNames = events
          .where((event) => event.type == ReActEventType.toolCall)
          .map((event) => event.toolName)
          .toList();
      expect(toolNames, [
        'search_story_coverage',
        'get_story_map',
        'read_story_lines',
      ]);

      final finalAnswer = events
          .where((event) => event.type == ReActEventType.finalAnswerToken)
          .map((event) => event.content)
          .join();
      // The model fabricated read=5; the transform rewrites it to the actual
      // single scope that was read.
      expect(finalAnswer, contains('Coverage: read=1 | mapped=1 | skipped=0'));
      expect(finalAnswer, isNot(contains('read=5')));
    });

    test('registers all four tools', () {
      // Surface check: the Summary agent prompt advertises the coverage tools.
      final prompt = buildAgentPrompt(summaryInstructions);
      expect(prompt, contains('search_story_coverage'));
      expect(prompt, contains('get_story_map'));
      expect(prompt, contains('read_story_lines'));
      expect(prompt, contains('Coverage: read='));
    });
  });
}

/// Builds a schema v3 DB from [sourceDir] using the production build pipeline
/// pieces (schema + importer + coverage builder + FTS rebuild).
Future<void> _buildFixtureDb(Directory sourceDir, String dbPath) async {
  final db = await databaseFactory.openDatabase(dbPath);
  final stats = BuildStats();
  try {
    await createGamedataSchema(db);
    await writeGamedataManifest(db, {
      'schema_version': '$gamedataSchemaVersion',
      'language': gamedataLanguage,
      'source_arknights_repo': arknightsSourceRepoUrl,
      'source_arknights_branch': 'master',
      'source_arknights_commit': 'test-fixture',
    });
    await ArknightsImporter(
      sourceDir: sourceDir,
      db: db,
      stats: stats,
      storyLimit: 0,
    ).importAll();
    await StoryCoverageBuilder(db: db, stats: stats).build();
    await rebuildGamedataFts(db);
  } finally {
    await db.close();
  }
}

/// Writes a minimal but complete ArknightsGameData-shaped source tree.
Future<Directory> _writeFixtureSource(Directory tempDir) async {
  final sourceDir = Directory(p.join(tempDir.path, 'src'));
  final excel = Directory(
    p.join(sourceDir.path, 'zh_CN', 'gamedata', 'excel'),
  )..createSync(recursive: true);
  final story = Directory(
    p.join(sourceDir.path, 'zh_CN', 'gamedata', 'story'),
  )..createSync(recursive: true);

  void writeJson(String name, Object data) {
    File(p.join(excel.path, name))
        .writeAsStringSync(jsonEncode(data), flush: true);
  }

  writeJson('character_table.json', {
    'char_victim': {
      'name': '受害者',
      'appellation': '',
      'displayNumber': '',
      'description': '测试受害者角色。',
      'itemUsage': '',
      'itemDesc': '',
    },
    'char_a': {
      'name': '角色A',
      'appellation': '',
      'displayNumber': '',
      'description': '误导角色。',
      'itemUsage': '',
      'itemDesc': '',
    },
    'char_b': {
      'name': '角色B',
      'appellation': '',
      'displayNumber': '',
      'description': '真相角色。',
      'itemUsage': '',
      'itemDesc': '',
    },
  });
  writeJson('handbook_info_table.json', {'handbookDict': <String, dynamic>{}});
  writeJson('charword_table.json', {'charWords': <String, dynamic>{}});
  for (final name in const [
    'item_table',
    'skin_table',
    'medal_table',
    'uniequip_table',
    'enemy_handbook_table',
    'stage_table',
    'zone_table',
    'campaign_table',
    'activity_table',
    'retro_table',
    'mission_table',
    'roguelike_table',
    'roguelike_topic_table',
    'sandbox_table',
    'sandbox_perm_table',
  ]) {
    writeJson('$name.json', <String, dynamic>{});
  }

  void writeStory(String rel, String content) {
    final file = File(p.join(story.path, rel));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content, flush: true);
  }

  // Chapter 1: foreshadowing without the victim name or the word 死亡.
  writeStory(
    'activities/act_fixture/level_fixture_c1.txt',
    '[name="旁白"]那天夜里，染血的匕首在灰烬里闪着寒光。\n'
    '[name="角色A"]我什么都没看见。\n',
  );

  // Chapter 2: 40 lines of 角色A denying (misleading direction).
  final c2 = StringBuffer();
  for (var i = 1; i <= 40; i++) {
    c2.writeln('[name="角色A"]这是第$i次否认，我什么都没做。');
  }
  writeStory(
    'activities/act_fixture/level_fixture_c2.txt',
    c2.toString(),
  );

  // Chapter 3: explicit death statement (triage keyword hit).
  writeStory(
    'activities/act_fixture/level_fixture_c3.txt',
    '[name="角色A"]受害者已经死亡，我亲眼看见那场死亡。\n',
  );

  // Chapter 4: victim and 角色B appear together.
  writeStory(
    'activities/act_fixture/level_fixture_c4.txt',
    '[name="受害者"]我会回来的。\n'
    '[name="角色B"]匕首一直在我这里。\n',
  );

  // Chapter 5: past-timeline reveal by 角色B.
  writeStory(
    'activities/act_fixture/level_fixture_c5.txt',
    '[name="角色B"]当年我藏起匕首，是为了掩盖那场死亡的真相。\n',
  );

  return sourceDir;
}

/// Scripted LLM that follows the narrative workflow
/// coverage -> map -> read -> final (with a fabricated coverage line).
class _ScriptedCoverageLLMClient extends LLMClient {
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
    switch (callCount) {
      case 1:
        return '''
Thought: 我需要先枚举角色B的全部出场。
Action: search_story_coverage
Action Input: {"query": "角色B"}
''';
      case 2:
        return '''
Thought: 查看出场章节的画像以选择精读范围。
Action: get_story_map
Action Input: {"story_ids": ["activities/act_fixture/level_fixture_c5.txt"]}
''';
      case 3:
        return '''
Thought: 通读关键章节原文。
Action: read_story_lines
Action Input: {"story_id": "activities/act_fixture/level_fixture_c5.txt"}
''';
      default:
        return '''
Thought: 我已有足够信息。
Final Answer: 角色B在第五章承认当年藏起匕首是为了掩盖真相。

Coverage: read=5 | mapped=3 | skipped=0
''';
    }
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
