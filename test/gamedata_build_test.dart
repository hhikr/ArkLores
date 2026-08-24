import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:arklores/core/gamedata/build/gamedata_build_isolate.dart';
import 'package:arklores/core/gamedata/build/gamedata_build_service.dart';
import 'package:arklores/core/gamedata/build/source/arknights_source_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory tempDir;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('arklores_build_test');
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  group('ArknightsSourceClient', () {
    test('fetchLatestCommit parses the sha', () async {
      final client = ArknightsSourceClient(
        client: MockClient((request) async {
          expect(request.url.path, contains('/commits/master'));
          return http.Response('{"sha":"abc123def456"}', 200);
        }),
      );
      expect(await client.fetchLatestCommit(), 'abc123def456');
    });

    test('fetchLatestCommit surfaces HTTP errors', () async {
      final client = ArknightsSourceClient(
        client: MockClient((request) async => http.Response('oops', 500)),
      );
      expect(
        () => client.fetchLatestCommit(),
        throwsA(isA<StateError>()),
      );
    });

    test('fetchLatestCommit falls back to the atom feed on API 403', () async {
      final client = ArknightsSourceClient(
        client: MockClient((request) async {
          if (request.url.host == 'api.github.com') {
            return http.Response('rate limited', 403);
          }
          // Atom feed (non-API): include two entries; the newest is first.
          return http.Response(
            '<?xml version="1.0"?>'
            '<feed><entry><id>tag:github.com,2008:Grit::Commit/'
            'abcdef0123456789abcdef0123456789abcdef01</id></entry>'
            '<entry><id>tag:github.com,2008:Grit::Commit/'
            '0000000000000000000000000000000000000000</id></entry>'
            '</feed>',
            200,
          );
        }),
      );
      expect(
        await client.fetchLatestCommit(),
        'abcdef0123456789abcdef0123456789abcdef01',
      );
    });

    test('compareCommits throws a rate-limit exception on 403', () async {
      final client = ArknightsSourceClient(
        client: MockClient(
          (request) async => http.Response('{"message":"rate limit"}', 403),
        ),
      );
      expect(
        () => client.compareCommits(baseSha: 'old', headSha: 'new'),
        throwsA(isA<GameDataSourceRateLimitedException>()),
      );
    });

    test('compareCommits filters to the importer whitelist and paginates',
        () async {
      var calls = 0;
      final client = ArknightsSourceClient(
        client: MockClient((request) async {
          calls++;
          final page = request.url.queryParameters['page'];
          if (page == '1') {
            final files = [
              {
                'filename':
                    'zh_CN/gamedata/story/activities/act_x/level_1.txt',
                'status': 'added',
              },
              for (var i = 0; i < 99; i++)
                {'filename': 'zh_CN/gamedata/levels/lvl_$i.json', 'status': 'added'},
            ];
            return http.Response(jsonEncode({'files': files}), 200);
          }
          return http.Response(
            jsonEncode({
              'files': [
                {
                  'filename': 'zh_CN/gamedata/excel/activity_table.json',
                  'status': 'modified',
                },
                {
                  'filename':
                      'zh_CN/gamedata/story/main/removed_1.txt',
                  'status': 'removed',
                },
              ],
            }),
            200,
          );
        }),
      );
      final changes = await client.compareCommits(
        baseSha: 'old',
        headSha: 'new',
      );
      expect(
        changes.map((c) => c.path).toList(),
        [
          'zh_CN/gamedata/story/activities/act_x/level_1.txt',
          'zh_CN/gamedata/excel/activity_table.json',
          'zh_CN/gamedata/story/main/removed_1.txt',
        ],
      );
      expect(changes.first.isRemoval, isFalse);
      expect(changes.last.isRemoval, isTrue);
      expect(calls, 2);
    });

    test('whitelist predicates', () {
      expect(
        ArknightsSourcePaths.isStoryFile(
          'zh_CN/gamedata/story/main/level_1.txt',
        ),
        isTrue,
      );
      expect(
        ArknightsSourcePaths.isStoryFile('zh_CN/gamedata/levels/x.json'),
        isFalse,
      );
      expect(
        ArknightsSourcePaths.isImporterRelevant(
          'zh_CN/gamedata/excel/character_table.json',
        ),
        isTrue,
      );
      expect(
        ArknightsSourcePaths.isImporterRelevant(
          'zh_CN/gamedata/excel/unknown_table.json',
        ),
        isFalse,
      );
    });
  });

  group('zip filtered extraction', () {
    test('extracts only importer-relevant entries and strips top dir',
        () async {
      final zipPath = p.join(tempDir.path, 'src.zip');
      final outDir = Directory(p.join(tempDir.path, 'out'));
      final archive = Archive();
      void add(String name, String content) {
        final bytes = utf8.encode(content);
        archive.addFile(ArchiveFile(name, bytes.length, bytes));
      }

      add(
        'ArknightsGameData-test/zh_CN/gamedata/excel/character_table.json',
        '{"a":1}',
      );
      add(
        'ArknightsGameData-test/zh_CN/gamedata/story/main/level_1.txt',
        '[name="阿米娅"]你好',
      );
      add(
        'ArknightsGameData-test/zh_CN/gamedata/levels/enemydata/x.json',
        'skip me',
      );
      add('ArknightsGameData-test/README.md', 'skip me too');
      final bytes = ZipEncoder().encode(archive);
      await File(zipPath).writeAsBytes(bytes!);

      await ArknightsSourceClient.extractWhitelistedZip(
        zipPath: zipPath,
        outputDir: outDir,
      );
      expect(
        await File(
          p.join(outDir.path, 'zh_CN/gamedata/excel/character_table.json'),
        ).exists(),
        isTrue,
      );
      expect(
        await File(
          p.join(outDir.path, 'zh_CN/gamedata/story/main/level_1.txt'),
        ).exists(),
        isTrue,
      );
      expect(
        await File(
          p.join(outDir.path, 'zh_CN/gamedata/levels/enemydata/x.json'),
        ).exists(),
        isFalse,
      );
      expect(
        await File(p.join(outDir.path, 'README.md')).exists(),
        isFalse,
      );
    });
  });

  group('GameDataBuildService', () {
    test('full build produces a valid schema v3 database', () async {
      final sourceDir = await _writeFixtureSource(tempDir);
      final output = p.join(tempDir.path, 'built.db');
      final service = GameDataBuildService();
      final result = await service.build(
        GameDataBuildOptions(
          sourceDir: sourceDir.path,
          outputDbPath: output,
          commitSha: 'c1',
        ),
      );
      expect(result.incremental, isFalse);
      await validateGameDataDatabaseFile(output);

      final db = await databaseFactoryFfi.openDatabase(output);
      final storyLines = await db.rawQuery(
        'SELECT COUNT(*) AS c FROM story_lines',
      );
      expect(storyLines.first['c'], 46);
      final mentions = await db.rawQuery(
        'SELECT COUNT(*) AS c FROM entity_story_mentions',
      );
      expect((mentions.first['c'] as int), greaterThan(0));
      final manifest = await db.rawQuery(
        'SELECT value FROM gamedata_manifest WHERE key = \'source_arknights_commit\'',
      );
      expect(manifest.first['value'], 'c1');
      await db.close();
    });

    test('incremental update applies changes and preserves the rest',
        () async {
      final sourceDir = await _writeFixtureSource(tempDir);
      final v1 = p.join(tempDir.path, 'v1.db');
      final v2 = p.join(tempDir.path, 'v2.db');
      final service = GameDataBuildService();
      await service.build(
        GameDataBuildOptions(
          sourceDir: sourceDir.path,
          outputDbPath: v1,
          commitSha: 'c1',
        ),
      );

      // Modify the source tree.
      final newStory = File(
        p.join(
          sourceDir.path,
          'zh_CN/gamedata/story/activities/act_fixture/level_fixture_c6.txt',
        ),
      );
      newStory.parent.createSync(recursive: true);
      newStory.writeAsStringSync('[name="角色B"]第六章新增。\n');

      final c5 = File(
        p.join(
          sourceDir.path,
          'zh_CN/gamedata/story/activities/act_fixture/level_fixture_c5.txt',
        ),
      );
      c5.writeAsStringSync('${c5.readAsStringSync()}[name="角色B"]补充一句。\n');

      final itemTable = File(
        p.join(sourceDir.path, 'zh_CN/gamedata/excel/item_table.json'),
      );
      itemTable.writeAsStringSync(
        '{"items":{"item_001":{"id":"item_001","name":"源石",'
        '"description":"源石是泰拉世界的基石，新描述。"}}}',
      );

      final changes = [
        const SourceFileChange(
          path:
              'zh_CN/gamedata/story/activities/act_fixture/level_fixture_c6.txt',
          status: 'added',
        ),
        const SourceFileChange(
          path:
              'zh_CN/gamedata/story/activities/act_fixture/level_fixture_c5.txt',
          status: 'modified',
        ),
        const SourceFileChange(
          path: 'zh_CN/gamedata/excel/item_table.json',
          status: 'modified',
        ),
      ];
      final result = await service.build(
        GameDataBuildOptions(
          sourceDir: sourceDir.path,
          outputDbPath: v2,
          existingDbPath: v1,
          commitSha: 'c2',
          changedFiles: changes,
        ),
      );
      expect(result.incremental, isTrue);
      await validateGameDataDatabaseFile(v2);

      final db = await databaseFactoryFfi.openDatabase(v2);
      final c5Lines = await db.rawQuery(
        'SELECT COUNT(*) AS c FROM story_lines WHERE story_id = '
        "'activities/act_fixture/level_fixture_c5.txt'",
      );
      expect(c5Lines.first['c'], 2);
      final c6Lines = await db.rawQuery(
        'SELECT COUNT(*) AS c FROM story_lines WHERE story_id = '
        "'activities/act_fixture/level_fixture_c6.txt'",
      );
      expect(c6Lines.first['c'], 1);
      final newDesc = await db.rawQuery(
        'SELECT content FROM normalized_records WHERE content LIKE \'%新描述%\'',
      );
      expect(newDesc, isNotEmpty);
      final bMentions = await db.rawQuery(
        'SELECT story_id FROM entity_story_mentions WHERE entity_id = \'char_b\'',
      );
      expect(
        bMentions.map((row) => row['story_id']),
        contains('activities/act_fixture/level_fixture_c6.txt'),
      );
      final commit = await db.rawQuery(
        'SELECT value FROM gamedata_manifest WHERE key = \'source_arknights_commit\'',
      );
      expect(commit.first['value'], 'c2');
      await db.close();

      // The v1 database must be untouched.
      final v1db = await databaseFactoryFfi.openDatabase(v1);
      final v1C6 = await v1db.rawQuery(
        'SELECT COUNT(*) AS c FROM story_lines WHERE story_id = '
        "'activities/act_fixture/level_fixture_c6.txt'",
      );
      expect(v1C6.first['c'], 0);
      await v1db.close();
    });

    test('replaceInstalledDatabase swaps the built DB over the installed one',
        () async {
      final sourceDir = await _writeFixtureSource(tempDir);
      final output = p.join(tempDir.path, 'built.db');
      final install = p.join(tempDir.path, 'arklores_gamedata_zh.db');
      final service = GameDataBuildService();
      await service.build(
        GameDataBuildOptions(
          sourceDir: sourceDir.path,
          outputDbPath: output,
          commitSha: 'c1',
        ),
      );
      await File(install).writeAsBytes(const [1, 2, 3]);

      await service.replaceInstalledDatabase(
        builtPath: output,
        installPath: install,
      );
      final db = await databaseFactoryFfi.openDatabase(install);
      final entities = await db.rawQuery(
        'SELECT COUNT(*) AS c FROM entities',
      );
      expect(entities.first['c'], 4); // 3 operators + item:item_001
      await db.close();
    });
  });

  group('GameDataBuildRunner (isolate)', () {
    test('streams progress and done events from a background isolate',
        () async {
      final sourceDir = await _writeFixtureSource(tempDir);
      final output = p.join(tempDir.path, 'isolate.db');
      final runner = GameDataBuildRunner();
      final done = Completer<GameDataBuildEvent>();
      final progressStages = <String>{};
      late final StreamSubscription<GameDataBuildEvent> sub;
      sub = runner.events.listen((event) {
        if (event.type == GameDataBuildEventType.progress) {
          progressStages.add(event.stage);
        } else if (event.type == GameDataBuildEventType.done) {
          if (!done.isCompleted) done.complete(event);
        } else if (event.type == GameDataBuildEventType.error) {
          if (!done.isCompleted) {
            done.completeError(StateError(event.message ?? 'build error'));
          }
        }
      });
      await runner.start(
        GameDataBuildOptions(
          sourceDir: sourceDir.path,
          outputDbPath: output,
          commitSha: 'c1',
        ),
      );
      final event = await done.future
          .timeout(const Duration(seconds: 120));
      expect(event.incremental, isFalse);
      expect(event.stats['storyLines'], 46);
      expect(progressStages, contains('stories'));
      await sub.cancel();
      runner.kill();
    });
  });
}

/// Writes a minimal but complete ArknightsGameData-shaped source tree
/// (same fixture as test/story_coverage_test.dart).
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
  writeJson('item_table.json', {
    'items': {
      'item_001': {
        'id': 'item_001',
        'name': '源石',
        'description': '源石是泰拉世界的基石。',
      },
    },
  });
  for (final name in const [
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
    '[name="角色A"]我什么都没看见。\n',
  );
  final c2 = StringBuffer();
  for (var i = 1; i <= 40; i++) {
    c2.writeln('[name="角色A"]这是第$i次否认，我什么都没做。');
  }
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
