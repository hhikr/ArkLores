import 'dart:convert';
import 'dart:io';

import 'package:arklores/core/agent/loop_memory.dart';
import 'package:arklores/core/agent/react_loop.dart';
import 'package:arklores/core/agent/story_answer.dart';
import 'package:arklores/core/agent/tools/agent_tool.dart';
import 'package:arklores/core/agent/tools/tool_registry.dart';
import 'package:arklores/core/gamedata/build/arknights_importer.dart';
import 'package:arklores/core/gamedata/build/gamedata_schema.dart';
import 'package:arklores/core/gamedata/build/story_coverage_builder.dart';
import 'package:arklores/core/gamedata/gamedata_knowledge_store.dart';
import 'package:arklores/core/llm/llm_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/temp_dir.dart';

void main() {
  late Directory tempDir;
  late Directory sourceDir;
  late String dbPath;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('arklores_investigation');
    sourceDir = await _writeFixtureSource(tempDir);
    dbPath = p.join(tempDir.path, 'fixture.db');
    await _buildFixtureDb(sourceDir, dbPath);
  });

  tearDown(() async {
    await deleteTempDir(tempDir);
  });

  group('coverage builder progress (R2 UX)', () {
    test('reports per-chapter scan and profile progress', () async {
      final db = await databaseFactoryFfi.openDatabase(dbPath);
      // Drop the existing coverage layer so build() runs fully again.
      await db.delete('entity_story_mentions');
      await db.delete('story_chapter_profiles');
      await db.delete('rare_terms');
      final events = <(String, int, int)>[];
      await StoryCoverageBuilder(
        db: db,
        stats: BuildStats(),
        onProgress: (stage, done, total) {
          events.add((stage, done, total));
        },
      ).build();

      final scanEvents = events.where((e) => e.$1 == 'coverage_scan');
      expect(scanEvents, isNotEmpty);
      final scanList = scanEvents.toList();
      expect(scanList.first.$2, 1);
      expect(scanList.last.$2, scanList.last.$3);
      expect(scanList.last.$3, greaterThanOrEqualTo(5)); // 5 fixture chapters

      final profileEvents = events.where((e) => e.$1 == 'coverage_profiles');
      expect(profileEvents, isNotEmpty);
      expect(profileEvents.last.$2, profileEvents.last.$3);
      expect(
        events.map((e) => e.$1),
        containsAll([
          'coverage_speakers',
          'coverage_trie',
          'coverage_rare',
        ]),
      );
      await db.close();
    });
  });

  group('speaker entity expansion (R3)', () {
    test('promotes frequent speakers without an entity row', () async {
      final db = await databaseFactoryFfi.openDatabase(dbPath);
      final rows = await db.rawQuery(
        "SELECT id, name, entity_type FROM entities WHERE entity_type = 'speaker'",
      );
      expect(rows, isNotEmpty);
      expect(rows.first['name'], 'npc路人');
      await db.close();

      final store = GameDataKnowledgeStore(dbPath: dbPath);
      final coverage = await store.searchStoryCoverage(
        entityId: 'speaker:npc路人',
      );
      expect(coverage, isNotEmpty);
      expect(
        coverage.map((e) => e.storyId),
        containsAll([
          'activities/act_fixture/level_fixture_c1.txt',
          'activities/act_fixture/level_fixture_c2.txt',
        ]),
      );
      await store.close();
    });

    test('does not shadow real entities', () async {
      final db = await databaseFactoryFfi.openDatabase(dbPath);
      final rows = await db.rawQuery(
        "SELECT COUNT(*) AS c FROM entities WHERE name = '角色A'",
      );
      expect(rows.first['c'], 1); // only char_a, no speaker:角色A
      await db.close();
    });
  });

  group('story answer envelope (R13)', () {
    test('formats and parses the code-decided status', () {
      for (final status in StoryAnswerStatus.values) {
        final line = formatStoryAnswerEnvelope(status, confidence: '0.7');
        final parsed = parseStoryAnswerEnvelope('$line\n正文')!;
        expect(parsed.status, status);
        expect(parsed.confidence, '0.7');
      }
      final bare = parseStoryAnswerEnvelope(
        formatStoryAnswerEnvelope(StoryAnswerStatus.notCovered),
      )!;
      expect(bare.status, StoryAnswerStatus.notCovered);
      expect(bare.confidence, isNull);
      expect(parseStoryAnswerEnvelope('no envelope here'), isNull);
    });

    test('still reads pre-R13 envelopes of saved conversations', () {
      final answered = parseStoryAnswerEnvelope(
        '[INVESTIGATION_VERDICT: culprit=char_b | confidence=0.8 | '
        'basis=multi_hypothesis_contrast]\n正文',
      )!;
      expect(answered.status, StoryAnswerStatus.answered);
      expect(answered.confidence, '0.8');
      final unresolved = parseStoryAnswerEnvelope(
        '[INVESTIGATION_VERDICT: culprit=unresolved | confidence=0 | '
        'basis=insufficient_evidence]',
      )!;
      expect(unresolved.status, StoryAnswerStatus.partial);
    });
  });

  group('layered memory (M1)', () {
    test('caps Observation messages to the recent window and carries the '
        'memory block', () async {
      final mock = _RecordingLLMClient(iterations: 12);
      final registry = ToolRegistry()..register(_StaticObservationTool());
      final loop = ReActLoop(
        llmClient: mock,
        toolRegistry: registry,
      );
      await loop
          .run(
            systemPrompt: 'You are a helper.',
            chatHistory: [],
            userQuery: 'investigate',
          )
          .toList();

      expect(mock.receivedMessages, isNotEmpty);
      final last = mock.receivedMessages.last;
      // Only the recent window of raw observations remains in the request.
      final observationCount = last
          .where(
            (message) => message.content.startsWith('Observation: '),
          )
          .length;
      expect(observationCount, lessThanOrEqualTo(LoopMemory.recentWindowSize));
      // The memory block carries the read index + thought notes instead of
      // placeholder text.
      final joined = last.map((message) => message.content).join('\n');
      expect(joined, contains('调查记忆'));
      expect(joined, contains('调查要点'));
      expect(joined, isNot(contains('[prior observation trimmed')));
    });
  });
}

Future<void> _buildFixtureDb(Directory sourceDir, String dbPath) async {
  final db = await databaseFactoryFfi.openDatabase(dbPath);
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

  writeStory(
    'activities/act_fixture/level_fixture_c1.txt',
    '[name="旁白"]那天夜里，染血的匕首在灰烬里闪着寒光。\n'
    '[name="角色A"]我什么都没看见。\n'
    '[name="npc路人"]我好像看见了什么。\n'
    '[name="npc路人"]但我不确定。\n',
  );
  final c2 = StringBuffer();
  for (var i = 1; i <= 40; i++) {
    c2.writeln('[name="角色A"]这是第$i次否认，我什么都没做。');
  }
  c2.writeln('[name="npc路人"]那晚确实有怪事。');
  writeStory('activities/act_fixture/level_fixture_c2.txt', c2.toString());
  writeStory(
    'activities/act_fixture/level_fixture_c3.txt',
    '[name="角色A"]受害者已经死亡，我亲眼看见那场死亡。\n',
  );
  writeStory(
    'activities/act_fixture/level_fixture_c4.txt',
    '[name="受害者"]我会回来的。\n[name="角色B"]匕首一直在我这里。\n',
  );
  writeStory(
    'activities/act_fixture/level_fixture_c5.txt',
    '[name="角色B"]当年我藏起匕首，是为了掩盖那场死亡的真相。\n',
  );

  return sourceDir;
}

/// Returns a fixed observation; used to test history trimming.
class _StaticObservationTool extends AgentTool {
  @override
  String get name => 'fixed_tool';

  @override
  String get description => 'Returns a fixed observation.';

  @override
  Map<String, dynamic> get parameters => {
        'type': 'object',
        'properties': {'q': {'type': 'string'}},
      };

  @override
  Future<dynamic> execute(Map<String, dynamic> arguments) async {
    return const ToolExecutionResult(observation: 'Fixed observation content');
  }
}

/// Scripted LLM: calls `fixed_tool` [iterations] times, then finalizes.
/// Records every message list it received.
class _RecordingLLMClient extends LLMClient {
  _RecordingLLMClient({required this.iterations});
  final int iterations;
  int callCount = 0;
  final List<List<Message>> receivedMessages = [];

  @override
  Future<String> chat(
    List<Message> messages, {
    List<Map<String, dynamic>>? tools,
    double temperature = 0.7,
    int maxTokens = 2048,
    List<String>? stop,
  }) async {
    callCount++;
    receivedMessages.add(List.of(messages));
    if (callCount <= iterations) {
      return '''
Thought: gather more evidence.
Action: fixed_tool
Action Input: {"q": "evidence"}
''';
    }
    return '''
Thought: done.
Final Answer: conclusion
''';
  }
}
