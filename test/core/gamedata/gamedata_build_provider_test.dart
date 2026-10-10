// The knowledge-base page's "check for updates" and "build": the notifier
// pulls the source (a zip the first time, the changed files after), builds
// in the background isolate and swaps the result in. Driven end to end
// against an in-memory GitHub and a temporary app folder.
import 'dart:io';

import 'package:arklores/core/gamedata/gamedata_build_provider.dart';
import 'package:arklores/core/gamedata/gamedata_installer.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/fake_github.dart';
import '../../support/source_fixture.dart';
import '../../support/sqlite.dart';
import '../../support/temp_dir.dart';

const _level = 'zh_CN/gamedata/levels/activities/act_fixture/level_fixture_01.json';

/// The fixture at commit c1, with a level file.
Map<String, String> _c1() => {...fixtureSource(), _level: '{}'};

/// c1 with chapter 5 changed and a chapter 6 added.
Map<String, String> _c2() => {
      ..._c1(),
      '$fixtureStoryDir/level_fixture_c5.txt':
          '[name="角色B"]当年我藏起匕首，是为了掩盖那场死亡的真相。\n[name="角色B"]补充一句。\n',
      '$fixtureStoryDir/level_fixture_c6.txt': '[name="角色B"]第六章新增。\n',
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory docs;
  late ProviderContainer container;
  late List<Uri> requests;
  var installedNotices = 0;

  setUpAll(useSqfliteFfi);
  setUp(() {
    docs = Directory.systemTemp.createTempSync('build_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => docs.path,
    );
    requests = [];
    installedNotices = 0;
    container = ProviderContainer(overrides: [
      gameDataBuildProvider.overrideWith(
        (ref) => GameDataBuildNotifier(onInstalled: () => installedNotices++),
      ),
    ],);
  });
  tearDown(() async {
    container.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
    await deleteTempDir(docs);
  });

  GameDataBuildNotifier notifier() =>
      container.read(gameDataBuildProvider.notifier);
  GameDataBuildUiState state() => container.read(gameDataBuildProvider);

  /// Runs [action] with every `http.Client()` answering as GitHub at
  /// [latest]; the request log starts empty.
  Future<void> online(
    Map<String, Map<String, String>> commits,
    String latest,
    Future<void> Function() action,
  ) {
    requests.clear();
    return http.runWithClient(
      action,
      () => fakeGitHub(commits, latest: latest, requests: requests),
    );
  }

  Iterable<String> hosts() => requests.map((u) => u.host);
  Iterable<String> rawPaths() => [
        for (final u in requests)
          if (u.host == 'raw.githubusercontent.com') u.pathSegments.skip(3).join('/'),
      ];
  Future<Map<String, String>> manifest() async =>
      (await const GameDataInstaller().getStatus()).manifest;
  String marker() => File(p.join(docs.path, 'gamedata_source', '.source_commit'))
      .readAsStringSync();

  Future<void> buildC1() => online({'c1': _c1()}, 'c1', notifier().buildFromSource);

  test('nothing installed: a complete build from the zip', () async {
    await buildC1();
    expect(state().error, isNull);
    expect(state().phase, GameDataBuildPhase.done);
    expect(state().incremental, isFalse);
    expect(hosts(), contains('codeload.github.com'));
    expect(hosts(), isNot(contains('raw.githubusercontent.com')));
    expect((await manifest())['source_arknights_commit'], 'c1');
    expect(installedNotices, 1);
    expect(marker(), 'c1');
    // 0.14: the database says it was built here, so the official asset is
    // not offered as an update over it.
    expect((await const GameDataInstaller().getStatus()).builtLocally, isTrue);
    // The level files were read for the build, then removed (they are
    // fetched again only when they change).
    final source = p.join(docs.path, 'gamedata_source', 'zh_CN', 'gamedata');
    expect(Directory(p.join(source, 'levels')).existsSync(), isFalse);
    expect(File(p.join(source, 'excel', 'item_table.json')).existsSync(), isTrue);
    // No build left behind in the temp folder.
    expect(
      Directory(p.join(docs.path, 'gamedata_build_tmp'))
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.db')),
      isEmpty,
    );

    // Built again at the same commit: nothing to do, nothing downloaded.
    notifier().dismissDone();
    await online({'c1': _c1()}, 'c1', notifier().buildFromSource);
    expect(state().noRelevantChanges, isTrue);
    expect(state().phase, GameDataBuildPhase.idle);
    expect(hosts(), isNot(contains('codeload.github.com')));
    expect(installedNotices, 1);
  }, timeout: const Timeout(Duration(minutes: 3)),);

  test('an update downloads only the changed files and reports them',
      () async {
    await buildC1();
    notifier().dismissDone();

    await online({'c1': _c1(), 'c2': _c2()}, 'c2', notifier().buildFromSource);
    expect(state().error, isNull);
    expect(state().phase, GameDataBuildPhase.done);
    expect(state().incremental, isTrue);
    expect(hosts(), isNot(contains('codeload.github.com')));
    expect(rawPaths(), containsAll([
      '$fixtureStoryDir/level_fixture_c5.txt',
      '$fixtureStoryDir/level_fixture_c6.txt',
    ]),);
    // Unchanged stories are not fetched (the database has them).
    expect(rawPaths(), isNot(contains('$fixtureStoryDir/level_fixture_c1.txt')));
    final report = state().report!;
    expect(report.storyAdded, 1);
    expect(report.storyChanged, 1);
    expect((await manifest())['source_arknights_commit'], 'c2');
    expect(marker(), 'c2');

    final db = await databaseFactoryFfi.openDatabase(
      p.join(docs.path, 'arklores_gamedata_zh.db'),
      options: OpenDatabaseOptions(readOnly: true),
    );
    final c6 = await db.rawQuery(
      "SELECT COUNT(*) AS n FROM story_lines WHERE story_id LIKE '%level_fixture_c6.txt'",
    );
    await db.close();
    expect(c6.single['n'], 1);
  }, timeout: const Timeout(Duration(minutes: 3)),);

  test('an installed commit gone upstream: rebuilt completely', () async {
    await buildC1();
    notifier().dismissDone();

    // History rewritten: c1 no longer exists.
    await online({'c2': _c2()}, 'c2', notifier().buildFromSource);
    expect(state().error, isNull);
    expect(state().phase, GameDataBuildPhase.done);
    expect(state().incremental, isFalse);
    expect(hosts(), contains('codeload.github.com'));
    expect((await manifest())['source_arknights_commit'], 'c2');
  }, timeout: const Timeout(Duration(minutes: 3)),);

  // 0.14: a complete rebuild starts a new database without the vectors of
  // the installed one, so it waits for a second, explicit start.
  test('a complete rebuild over a database with vectors asks first',
      () async {
    await buildC1();
    notifier().dismissDone();
    final db = await databaseFactoryFfi
        .openDatabase(p.join(docs.path, 'arklores_gamedata_zh.db'));
    await db.insert('gamedata_manifest', {
      'key': 'embedding_model',
      'value': 'emb',
    });
    await db.close();

    await online({'c2': _c2()}, 'c2', notifier().buildFromSource);
    expect(state().confirmFull, isTrue);
    expect(state().phase, GameDataBuildPhase.idle);
    expect(state().error, isNull);
    expect(hosts(), isNot(contains('codeload.github.com')));
    expect((await manifest())['source_arknights_commit'], 'c1');
    expect(installedNotices, 1);

    await online(
      {'c2': _c2()},
      'c2',
      () => notifier().buildFromSource(allowFull: true),
    );
    expect(state().confirmFull, isFalse);
    expect(state().phase, GameDataBuildPhase.done);
    expect(state().incremental, isFalse);
    expect((await manifest())['source_arknights_commit'], 'c2');
  }, timeout: const Timeout(Duration(minutes: 3)),);

  test('upstream moved without a relevant file: nothing to update', () async {
    await buildC1();
    notifier().dismissDone();

    await online({'c1': _c1(), 'c1b': _c1()}, 'c1b', notifier().buildFromSource);
    expect(state().noRelevantChanges, isTrue);
    expect(state().phase, GameDataBuildPhase.idle);
    expect(installedNotices, 1);
    expect((await manifest())['source_arknights_commit'], 'c1');
  }, timeout: const Timeout(Duration(minutes: 3)),);

  test('the update check counts what changed, by kind', () async {
    // Nothing installed: the latest commit, no comparison.
    await online({'c1': _c1()}, 'c1', notifier().checkForUpdates);
    expect(state().latestCommit, 'c1');
    expect(state().installedCommit, isNull);
    expect(state().noRelevantChanges, isFalse);

    await buildC1();
    notifier().dismissDone();
    await online({'c1': _c1(), 'c2': _c2()}, 'c2', notifier().checkForUpdates);
    expect(state().changedFileCount, 2);
    expect(state().changeSummary!.storyAdded, 1);
    expect(state().changeSummary!.storyChanged, 1);
    expect(hosts(), isNot(contains('raw.githubusercontent.com')));

    // The installed commit is gone: the update will be a complete rebuild.
    await online({'c2': _c2()}, 'c2', notifier().checkForUpdates);
    expect(state().changedFileCount, -1);
    expect(state().error, isNull);
  }, timeout: const Timeout(Duration(minutes: 3)),);

  // Seen on a phone: cancelling while the changed files were downloading did
  // not stop the download, and the update started again right away deleted
  // the tables under it.
  test('cancelled while downloading: stops, and the next update goes through',
      () async {
    await buildC1();
    notifier().dismissDone();

    var again = Future<void>.value();
    var cancelledOnce = false;
    final sub = container.listen(gameDataBuildProvider, (_, next) {
      if (cancelledOnce || next.phase != GameDataBuildPhase.downloading) return;
      cancelledOnce = true;
      notifier().cancel();
      // A tap on "update" before the cancelled run has ended is not a
      // second run beside it.
      again = notifier().buildFromSource();
    });
    await online({'c1': _c1(), 'c2': _c2()}, 'c2', () async {
      await notifier().buildFromSource();
      await again;
    });
    sub.close();
    expect(cancelledOnce, isTrue);
    expect(state().phase, GameDataBuildPhase.idle);
    expect(state().error, isNull);
    expect((await manifest())['source_arknights_commit'], 'c1');

    await online({'c1': _c1(), 'c2': _c2()}, 'c2', notifier().buildFromSource);
    expect(state().error, isNull);
    expect(state().phase, GameDataBuildPhase.done);
    expect(state().incremental, isTrue);
    expect((await manifest())['source_arknights_commit'], 'c2');
  }, timeout: const Timeout(Duration(minutes: 3)),);

  test('a failed download leaves an error and no database', () async {
    // The zip is not there.
    await online({}, 'c1', notifier().buildFromSource);
    expect(state().phase, GameDataBuildPhase.idle);
    expect(state().error, isNotNull);
    expect(File(p.join(docs.path, 'arklores_gamedata_zh.db')).existsSync(),
        isFalse,);
    expect(installedNotices, 0);

    // A failing check is reported as such.
    await http.runWithClient(
      notifier().checkForUpdates,
      () => fakeGitHubDown(),
    );
    expect(state().error, startsWith('check:'));

    // The next run that gets through takes the old message away, from its
    // start (it was kept through a whole successful build).
    await online({'c1': _c1()}, 'c1', notifier().checkForUpdates);
    expect(state().error, isNull);
    await http.runWithClient(
      notifier().checkForUpdates,
      () => fakeGitHubDown(),
    );
    expect(state().error, isNotNull);
    final seen = <String?>[];
    final sub = container.listen(
      gameDataBuildProvider,
      (_, next) => seen.add(next.error),
    );
    await buildC1();
    sub.close();
    expect(seen, isNotEmpty);
    expect(seen, everyElement(isNull));
    expect(state().phase, GameDataBuildPhase.done);
  }, timeout: const Timeout(Duration(minutes: 3)),);
}

/// A GitHub that answers every request with a server error.
http.Client fakeGitHubDown() => _Down();

class _Down extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      http.StreamedResponse(Stream.value(const []), 500);
}
