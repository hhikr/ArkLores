import 'dart:convert';
import 'dart:io';

import 'package:arklores/core/gamedata/build/gamedata_schema.dart';
import 'package:arklores/core/gamedata/build/source/arknights_source_client.dart';
import 'package:arklores/core/gamedata/build/source/source_sync.dart';
import 'package:arklores/core/gamedata/story_vector_updater.dart';
import 'package:arklores/core/gamedata/story_vectors.dart';
import 'package:arklores/core/llm/embedding_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/temp_dir.dart';

/// The incremental update channel: what an update downloads, the vectors it
/// leaves to regenerate and what that costs. Fixture names are fictional.
void main() {
  sqfliteFfiInit();

  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('arklores_inc_test'));
  tearDown(() => deleteTempDir(dir));

  group('SourceSync', () {
    const base = 'zh_CN/gamedata';
    late List<String> downloads;

    ArknightsSourceClient clientWith(List<Map<String, String>> changes) {
      downloads = [];
      return ArknightsSourceClient(
        client: MockClient((request) async {
          if (request.url.host == 'api.github.com') {
            final page = int.parse(request.url.queryParameters['page']!);
            return http.Response(
              jsonEncode({'files': page == 1 ? changes : <Object?>[]}),
              200,
            );
          }
          // raw.githubusercontent.com/<repo>/<sha>/<path>
          final path = request.url.path.split('/').skip(4).join('/');
          downloads.add(Uri.decodeFull(path));
          return http.Response('{"from":"${request.url.pathSegments[2]}"}', 200);
        }),
      );
    }

    test('downloads the changed files and only the missing context tables',
        () async {
      final source = Directory(p.join(dir.path, 'src'));
      // One context table is on disk already (and current).
      final have = File(p.join(source.path, '$base/excel/zone_table.json'));
      have.parent.createSync(recursive: true);
      have.writeAsStringSync('{"mine":true}');
      File(p.join(source.path, '$base/story/old.txt'))
        ..createSync(recursive: true)
        ..writeAsStringSync('removed soon');

      final sync = SourceSync(
        client: clientWith([
          {'filename': '$base/story/a/new.txt', 'status': 'added'},
          {'filename': '$base/story/old.txt', 'status': 'removed'},
          {'filename': '$base/excel/item_table.json', 'status': 'modified'},
          {'filename': '$base/levels/obt/x/level_a.json', 'status': 'modified'},
          {'filename': '$base/bakemuzzledata/m.json', 'status': 'modified'},
        ]),
        sourceDir: source,
      );
      final result = await sync.sync(installedSha: 'old', latestSha: 'new');

      expect(result.changes.map((c) => c.path), [
        '$base/story/a/new.txt',
        '$base/story/old.txt',
        '$base/excel/item_table.json',
        '$base/levels/obt/x/level_a.json',
      ]);
      final summary = result.summary;
      expect((summary.storyAdded, summary.storyRemoved), (1, 1));
      expect(summary.tables, ['item_table.json']);
      expect(summary.levelFiles, 1);
      // The context table already there is kept, the others come at the
      // latest commit; the changed files come too.
      expect(have.readAsStringSync(), '{"mine":true}');
      final contextDownloads =
          downloads.where((d) => d.contains('/excel/')).toList();
      expect(
        contextDownloads.length,
        ArknightsSourcePaths.excelTables.length - 1 + 1, // + item_table once
      );
      expect(downloads, contains('$base/story/a/new.txt'));
      expect(File(p.join(source.path, '$base/story/old.txt')).existsSync(), isFalse);
      expect(
        File(p.join(source.path, '$base/story/a/new.txt')).readAsStringSync(),
        contains('"from":"new"'),
      );
    });

    test('a directory older than the installed database refreshes its tables',
        () async {
      final source = Directory(p.join(dir.path, 'src'));
      final stale = File(p.join(source.path, '$base/excel/zone_table.json'));
      stale.parent.createSync(recursive: true);
      stale.writeAsStringSync('{"stale":true}');
      final sync = SourceSync(
        client: clientWith([
          {'filename': '$base/story/a/new.txt', 'status': 'added'},
        ]),
        sourceDir: source,
      );
      await sync.markSynced('older-commit');
      await sync.sync(installedSha: 'installed', latestSha: 'latest');
      expect(stale.readAsStringSync(), contains('"from":"latest"'));
      await sync.markSynced('latest');
      expect(await sync.localCommit(), 'latest');
    });

    test('nothing relevant changed: nothing is downloaded', () async {
      final sync = SourceSync(
        client: clientWith([
          {'filename': '$base/bakemuzzledata/m.json', 'status': 'modified'},
        ]),
        sourceDir: Directory(p.join(dir.path, 'src')),
      );
      final result = await sync.sync(installedSha: 'old', latestSha: 'new');
      expect(result.upToDate, isTrue);
      expect(downloads, isEmpty);
    });

    test('more changes than the compare API lists is reported', () async {
      final client = ArknightsSourceClient(
        client: MockClient(
          (request) async => http.Response(
            jsonEncode({
              'files': [
                for (var i = 0; i < 100; i++)
                  {'filename': '$base/story/s_$i.txt', 'status': 'added'},
              ],
            }),
            200,
          ),
        ),
      );
      expect(
        client.compareCommits(baseSha: 'a', headSha: 'b'),
        throwsA(isA<GameDataSourceTooManyChangesException>()),
      );
    });
  });

  group('story vectors', () {
    late Database db;

    Future<void> addStory(String id, List<(String, String)> lines) async {
      await db.insert('story_scopes', {
        'story_id': id,
        'scope_type': 'activity',
        'scope_id': 'act_fx',
        'source_path': id,
      });
      for (var i = 0; i < lines.length; i++) {
        await db.insert('story_lines', {
          'id': '$id#$i',
          'game': 'arknights',
          'story_id': id,
          'speaker': i.isEven ? '甲' : null,
          'content': '第 $i 行的内容，写得足够长一些。',
          'line_index': i,
          'kind': lines[i].$1,
        });
      }
    }

    setUp(() async {
      db = await databaseFactoryFfi.openDatabase(p.join(dir.path, 'v.db'));
      await createGamedataSchema(db);
      await addStory('s/a.txt', [for (var i = 0; i < 30; i++) ('dialogue', '')]);
      await addStory('s/b.txt', [for (var i = 0; i < 5; i++) ('narration', '')]);
      await addStory('s/tutorial.txt', [for (var i = 0; i < 5; i++) ('system', '')]);
    });

    tearDown(() => db.close());

    test('the plan of a database without vectors is a first build', () async {
      final plan = await planVectorUpdate(db);
      expect(plan.hasTable, isFalse);
      expect(plan.isFirstBuild, isTrue);
      // Tutorial text is not embedded.
      expect(plan.pendingStories, 2);
      // 30 lines -> 4 chunks of 12 (step 8), 5 lines -> 1.
      expect(plan.pendingChunks, 5);
      expect(plan.estimatedTokens, greaterThan(0));
      expect(plan.estimatedYuan(), lessThan(0.01));
      expect(plan.estimatedYuan(1), plan.estimatedTokens / 1000);
    });

    test('updating embeds only stories without vectors', () async {
      final client = _FakeEmbedder();
      final first = await updateStoryVectors(db: db, client: client);
      expect(first.stories, 2);
      expect(first.chunks, 5);
      expect(first.tokensUsed, 5 * 100);
      expect((await planVectorUpdate(db)).nothingToDo, isTrue);
      final manifest = await db.query(
        'gamedata_manifest',
        where: 'key = ?',
        whereArgs: [manifestEmbeddingModel],
      );
      expect(manifest.single['value'], _FakeEmbedder.modelName);

      // A story changed (its vectors were dropped) and one is new.
      await db.delete(
        storyChunkVectorsTable,
        where: 'story_id = ?',
        whereArgs: ['s/b.txt'],
      );
      await addStory('s/c.txt', [for (var i = 0; i < 3; i++) ('dialogue', '')]);
      final plan = await planVectorUpdate(db);
      expect(plan.isFirstBuild, isFalse);
      expect(plan.pendingStories, 2);
      expect(plan.storiesWithVectors, 1);

      final before = client.calls;
      final second = await updateStoryVectors(db: db, client: client);
      expect(second.stories, 2);
      expect(client.calls, greaterThan(before));
      expect(
        (await db.rawQuery(
          'SELECT COUNT(DISTINCT story_id) AS n FROM $storyChunkVectorsTable',
        ))
            .single['n'],
        3,
      );
    });

    test('vectors of another model are never mixed in', () async {
      await updateStoryVectors(db: db, client: _FakeEmbedder());
      await db.delete(
        storyChunkVectorsTable,
        where: 'story_id = ?',
        whereArgs: ['s/b.txt'],
      );
      expect(
        updateStoryVectors(db: db, client: _FakeEmbedder(model: 'other')),
        throwsA(isA<VectorModelMismatch>()),
      );
    });

    test('stopping keeps the finished stories', () async {
      var polls = 0;
      final result = await updateStoryVectors(
        db: db,
        client: _FakeEmbedder(),
        concurrency: 1,
        shouldCancel: () => polls++ >= 1,
      );
      expect(result.cancelled, isTrue);
      expect(result.stories, 1);
      expect((await planVectorUpdate(db)).pendingStories, 1);
    });
  });
}

class _FakeEmbedder implements EmbeddingClient {
  _FakeEmbedder({this.model = modelName});
  static const String modelName = 'fake-embed';

  @override
  final String model;

  @override
  int get dimensions => 8;

  int calls = 0;
  int _tokens = 0;

  @override
  int get tokensUsed => _tokens;

  @override
  Future<List<List<double>>> embed(List<String> texts) async {
    calls++;
    _tokens += texts.length * 100;
    return [
      for (final text in texts)
        [for (var i = 0; i < 8; i++) (text.length + i).toDouble()],
    ];
  }
}
