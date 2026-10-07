import 'dart:convert';
import 'dart:io';

import 'package:arklores/core/agent/tools/agent_tool.dart';
import 'package:arklores/core/agent/tools/search_story_lines.dart';
import 'package:arklores/core/gamedata/build/arknights_importer.dart';
import 'package:arklores/core/gamedata/build/gamedata_schema.dart';
import 'package:arklores/core/gamedata/build/story_coverage_builder.dart';
import 'package:arklores/core/gamedata/gamedata_knowledge_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../support/temp_dir.dart';

/// Synthetic 5-chapter fixture (from the R1 retrieval design, see git
/// history): chapter 1 holds a foreshadowing line without the victim name or the
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
    await deleteTempDir(tempDir);
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
          'activities/act_fixture/level_fixture_c9.txt',
          'activities/act_fixture/level_fixture_c10.txt',
        },
      );
      await store.close();
    });

    test('writes story_chapter_profiles with keyword hits and summary', () async {
      final store = GameDataKnowledgeStore(dbPath: dbPath);
      final profiles = await store.getStoryMap(
        scopeId: 'activity:act_fixture',
      );
      expect(profiles, hasLength(7));

      final c3 = profiles.firstWhere(
        (profile) => profile.storyId.endsWith('level_fixture_c3.txt'),
      );
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

    test('reports per-chapter scan and profile progress', () async {
      final db = await databaseFactory.openDatabase(dbPath);
      // Drop the coverage layer so build() runs fully again.
      await db.delete('entity_story_mentions');
      await db.delete('story_chapter_profiles');
      await db.delete('rare_terms');
      final events = <(String, int, int)>[];
      await StoryCoverageBuilder(
        db: db,
        stats: BuildStats(),
        onProgress: (stage, done, total) => events.add((stage, done, total)),
      ).build();
      await db.close();

      final scan = events.where((e) => e.$1 == 'coverage_scan').toList();
      expect(scan.first.$2, 1);
      expect(scan.last.$2, scan.last.$3);
      expect(scan.last.$3, 7); // 7 fixture chapters
      final profiles = events.where((e) => e.$1 == 'coverage_profiles');
      expect(profiles, isNotEmpty);
      expect(profiles.last.$2, profiles.last.$3);
      expect(
        events.map((e) => e.$1),
        containsAll(['coverage_speakers', 'coverage_trie', 'coverage_rare']),
      );
    });

    test('frequent speakers without an entity become speaker entities',
        () async {
      final db = await databaseFactory.openDatabase(dbPath);
      final speakers = await db.rawQuery(
        "SELECT name FROM entities WHERE entity_type = 'speaker'",
      );
      // A speaker never shadows a real entity of the same name.
      final named = await db.rawQuery(
        "SELECT COUNT(*) AS c FROM entities WHERE name = '角色A'",
      );
      await db.close();
      expect(speakers.map((r) => r['name']), ['npc路人']);
      expect(named.first['c'], 1);

      final store = GameDataKnowledgeStore(dbPath: dbPath);
      addTearDown(store.close);
      final coverage = await store.searchStoryCoverage(entityId: 'speaker:npc路人');
      expect(
        coverage.map((e) => e.storyId),
        containsAll([
          'activities/act_fixture/level_fixture_c1.txt',
          'activities/act_fixture/level_fixture_c2.txt',
        ]),
      );
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
    test('search_story_lines finds stories by raw text (R12)', () async {
      final tool = SearchStoryLinesTool(
        gameDataStore: GameDataKnowledgeStore(dbPath: dbPath),
      );
      final dagger =
          await tool.execute({'query': '匕首'}) as ToolExecutionResult;
      for (final chapter in ['c1', 'c4', 'c5']) {
        expect(dagger.observation, contains('level_fixture_$chapter.txt'));
      }
      expect(dagger.observation, contains('locating hints'));
      expect(dagger.observation, contains('DATA: '));

      // Terms are AND-ed within one line.
      final both = await tool.execute({'query': '藏起 真相'})
          as ToolExecutionResult;
      expect(both.observation, contains('level_fixture_c5.txt'));
      expect(both.observation, isNot(contains('level_fixture_c1.txt')));

      final none = await tool.execute({'query': '不存在的短语'})
          as ToolExecutionResult;
      expect(none.observation, contains('No story line matches'));
      expect(none.observation, contains('no embedding API configured'));

      final scoped = await tool.execute({
        'query': '匕首',
        'scope_id': 'activity:no_such_scope',
      }) as ToolExecutionResult;
      expect(scoped.observation, contains('No story line matches'));
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
    '[name="角色A"]我什么都没看见。\n'
    // A frequent speaker without a character-table row.
    '[name="npc路人"]我好像看见了什么。\n'
    '[name="npc路人"]但我不确定。\n',
  );

  // Chapter 2: 40 lines of 角色A denying (misleading direction).
  final c2 = StringBuffer();
  for (var i = 1; i <= 40; i++) {
    c2.writeln('[name="角色A"]这是第$i次否认，我什么都没做。');
  }
  c2.writeln('[name="npc路人"]那晚确实有怪事。');
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

  // Chapters 9/10: lexicographic order would put c10 before c9; natural
  // (chapter-number) order must keep c9 before c10 (M4a).
  writeStory(
    'activities/act_fixture/level_fixture_c9.txt',
    '[name="角色B"]第九章：死亡现场的回响。\n',
  );
  writeStory(
    'activities/act_fixture/level_fixture_c10.txt',
    '[name="角色B"]第十章：最后的真相。\n',
  );

  return sourceDir;
}

