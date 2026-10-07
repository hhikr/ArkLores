// Installing the knowledge base: validation before replacing, the release
// asset download (resume, retries, cancel, a file placed by hand) and the
// "update available" marker.
import 'dart:async';
import 'dart:io';

import 'package:arklores/core/gamedata/game.dart';
import 'package:arklores/core/gamedata/gamedata_installer.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/amiya_fixture.dart';
import '../../support/sqlite.dart';
import '../../support/temp_dir.dart';

void main() {
  late Directory dir;

  setUpAll(useSqfliteFfi);
  setUp(() => dir = Directory.systemTemp.createTempSync('gamedata_installer'));
  tearDown(() => deleteTempDir(dir));

  String installed() => '${dir.path}/arklores_gamedata_zh.db';
  File partial() => File('${installed()}.download.gz');
  File partialKey() => File('${installed()}.download.gz.key');

  /// A valid knowledge base, as raw bytes.
  Future<List<int>> validDb({String name = 'valid_gamedata.db'}) async {
    final path = '${dir.path}/$name';
    await createAmiyaDb(path, extra: addAmiyaStoryChunk);
    return File(path).readAsBytes();
  }

  /// A valid knowledge base whose manifest [key] is set to [value].
  Future<List<int>> dbWithManifest(String key, String value) async {
    final path = '${dir.path}/edited.db';
    await createAmiyaDb(path);
    final db = await databaseFactoryFfi.openDatabase(path);
    await db.update('gamedata_manifest', {'value': value},
        where: 'key = ?', whereArgs: [key],);
    await db.close();
    return File(path).readAsBytes();
  }

  GameDataInstaller withAsset(List<int> gz, {String url = 'https://example.com/db.gz'}) =>
      GameDataInstaller(
        installDirectory: dir,
        releaseAssetUrl: url,
        releaseAssetSha: sha256.convert(gz).toString(),
      );

  group('validation before replacing', () {
    test('a valid database installs', () async {
      final installer = GameDataInstaller(installDirectory: dir);
      await installer.installFromBytes(await validDb(), overwrite: true);
      final status = await installer.getStatus();
      expect(status.installed, isTrue);
      expect(status.manifest['schema_version'], '5');
      expect(status.entityCount, '1');
    });

    test("each game installs into its own file; one never replaces the other", () async {
      final arknights = GameDataInstaller(installDirectory: dir);
      const endfield = GameDataInstaller.forGame(Game.endfield);
      final ef = GameDataInstaller(
        installDirectory: dir,
        game: endfield.game,
      );
      await arknights.installFromBytes(await validDb(), overwrite: true);
      await ef.installFromBytes(await validDb(name: 'ef.db'), overwrite: true);
      expect(File(installed()).existsSync(), isTrue);
      expect(File('${dir.path}/${Game.endfield.dbFileName}').existsSync(), isTrue);
      expect((await ef.getStatus()).dbPath, endsWith(Game.endfield.dbFileName));
      // No Endfield asset in a build without its URL: nothing to update to.
      expect(endfield.releaseAssetUrl, isEmpty);
    });

    test('garbage is refused and the installed database is kept', () async {
      final installer = GameDataInstaller(installDirectory: dir);
      await installer.installFromBytes(await validDb(), overwrite: true);
      final before = await File(installed()).readAsBytes();
      expect(
        () => installer.installFromBytes(const [1, 2, 3, 4], overwrite: true),
        throwsA(isA<Object>()),
      );
      expect(await File(installed()).readAsBytes(), before);
    });

    test('an older schema is refused', () async {
      final bytes = await dbWithManifest('schema_version', '1');
      expect(
        () => GameDataInstaller(installDirectory: dir)
            .installFromBytes(bytes, overwrite: true),
        throwsA(isA<StateError>()
            .having((e) => '$e', 'message', contains('incompatible')),),
      );
    });

    test('an empty story_line_count is refused', () async {
      final bytes = await dbWithManifest('story_line_count', '0');
      expect(
        () => GameDataInstaller(installDirectory: dir)
            .installFromBytes(bytes, overwrite: true),
        throwsA(isA<StateError>()
            .having((e) => '$e', 'message', contains('story_line_count')),),
      );
    });
  });

  group('release asset', () {
    test('remembers the installed asset and flags a newer one', () async {
      final raw = await validDb();
      final gz = gzip.encode(raw);
      final gzSha = sha256.convert(gz).toString();

      // A database installed without a marker (pre-v0.10.1 or built in the
      // app) differs from the asset this build points at.
      final installer = withAsset(gz);
      await installer.installFromBytes(raw, overwrite: true);
      expect((await installer.getStatus()).updateAvailable, isTrue);

      expect(
        await installer.installFromReleaseAsset(
          client: MockClient((_) async => http.Response.bytes(gz, 200)),
          overwrite: true,
        ),
        isTrue,
      );
      var status = await installer.getStatus();
      expect(status.installedAssetSha, gzSha);
      expect(status.updateAvailable, isFalse);

      // The next app build points at a new data release.
      status = await GameDataInstaller(
        installDirectory: dir,
        releaseAssetUrl: 'https://example.com/db.gz',
        releaseAssetSha: 'f' * 64,
      ).getStatus();
      expect(status.updateAvailable, isTrue);

      // No configured asset: nothing to offer.
      status = await GameDataInstaller(
        installDirectory: dir,
        releaseAssetUrl: '',
        releaseAssetSha: '',
      ).getStatus();
      expect(status.updateAvailable, isFalse);
    });

    test('a dropped download resumes with a Range request', () async {
      final gz = gzip.encode(await validDb());
      final half = gz.length ~/ 2;
      final ranges = <String?>[];
      final client = MockClient.streaming((request, _) async {
        final range = request.headers['Range'];
        ranges.add(range);
        if (range == null) {
          // Half the file, then the connection drops.
          final controller = StreamController<List<int>>();
          controller
            ..add(gz.sublist(0, half))
            ..addError(const HandshakeException('Connection terminated during handshake'));
          unawaited(controller.close());
          return http.StreamedResponse(controller.stream, 200,
              contentLength: gz.length,);
        }
        final from = int.parse(RegExp(r'bytes=(\d+)-').firstMatch(range)!.group(1)!);
        return http.StreamedResponse(Stream.value(gz.sublist(from)), 206,
            contentLength: gz.length - from,);
      });
      final installer = withAsset(gz);
      final progress = <int>[];
      expect(
        await installer.installFromReleaseAsset(
          client: client,
          overwrite: true,
          retryDelay: Duration.zero,
          onProgress: (received, _) => progress.add(received),
        ),
        isTrue,
      );
      expect(ranges, [null, 'bytes=$half-']);
      expect(progress.last, gz.length);
      final status = await installer.getStatus();
      expect(status.installed, isTrue);
      expect(status.updateAvailable, isFalse);
      expect(partial().existsSync(), isFalse);
    });

    test('HTTP errors are not retried; a partial of another asset is dropped',
        () async {
      var calls = 0;
      final installer = GameDataInstaller(
        installDirectory: dir,
        releaseAssetUrl: 'https://example.com/db.gz',
        releaseAssetSha: 'a' * 64,
      );
      partial().writeAsBytesSync([1, 2, 3]);
      partialKey().writeAsStringSync('b' * 64);
      final ranges = <String?>[];
      await expectLater(
        installer.installFromReleaseAsset(
          client: MockClient((request) async {
            ranges.add(request.headers['Range']);
            calls++;
            return http.Response('missing', 404);
          }),
          overwrite: true,
          retryDelay: Duration.zero,
        ),
        throwsA(isA<StateError>().having((e) => '$e', 'message', contains('HTTP 404'))),
      );
      expect(calls, 1);
      expect(ranges, [null]); // the stale partial was not resumed
      expect(isTransientNetworkError(const HandshakeException('x')), isTrue);
      expect(isTransientNetworkError(StateError('HTTP 404')), isFalse);
    });

    test('reports its phases; a failure leaves no key file', () async {
      final gz = gzip.encode(await validDb());
      final installer = withAsset(gz);
      final phases = <GameDataInstallPhase>[];
      expect(
        await installer.installFromReleaseAsset(
          client: MockClient((_) async => http.Response.bytes(gz, 200)),
          overwrite: true,
          onPhase: (phase, attempt) {
            if (phases.isEmpty || phases.last != phase) phases.add(phase);
          },
        ),
        isTrue,
      );
      expect(phases, [
        GameDataInstallPhase.connecting,
        GameDataInstallPhase.downloading,
        GameDataInstallPhase.verifying,
        GameDataInstallPhase.installing,
      ]);

      // Failed before any byte arrived: no partial file, so no key file.
      await expectLater(
        installer.installFromReleaseAsset(
          client: MockClient((_) async => http.Response('missing', 404)),
          overwrite: true,
        ),
        throwsA(isA<StateError>()),
      );
      expect(partialKey().existsSync(), isFalse);
    });

    test('a silent server is retried, then can be cancelled', () async {
      var calls = 0;
      final silent = MockClient.streaming((request, _) {
        calls++;
        return Completer<http.StreamedResponse>().future;
      });
      final installer = GameDataInstaller(
        installDirectory: dir,
        releaseAssetUrl: 'https://example.com/db.gz',
        releaseAssetSha: 'a' * 64,
      );
      final attempts = <int>[];
      await expectLater(
        installer.installFromReleaseAsset(
          client: silent,
          overwrite: true,
          maxAttempts: 3,
          retryDelay: Duration.zero,
          connectTimeout: const Duration(milliseconds: 40),
          onPhase: (phase, attempt) => attempts.add(attempt),
        ),
        throwsA(isA<TimeoutException>()),
      );
      expect(calls, 3);
      expect(attempts, [1, 2, 3]);

      final token = GameDataDownloadToken();
      final waiting = installer.installFromReleaseAsset(
        client: silent,
        overwrite: true,
        cancelToken: token,
        connectTimeout: const Duration(seconds: 30),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      token.cancel();
      await expectLater(waiting, throwsA(isA<GameDataDownloadCancelled>()));
    });

    test('a file placed by hand at the partial path is checked', () async {
      final gz = gzip.encode(await validDb());
      final installer = withAsset(gz);

      // A wrong file is refused and not kept.
      partial().writeAsBytesSync([1, 2, 3, 4]);
      await expectLater(
        installer.installFromReleaseAsset(
          client: MockClient((r) async => http.Response('', 416)),
          overwrite: true,
        ),
        throwsA(isA<StateError>()
            .having((e) => '$e', 'message', contains('checksum mismatch')),),
      );
      expect(partial().existsSync(), isFalse);

      // The right one needs no download: the server's 416 says it is whole.
      partial().writeAsBytesSync(gz);
      expect(
        await installer.installFromReleaseAsset(
          client: MockClient((r) async => http.Response('', 416)),
          overwrite: true,
        ),
        isTrue,
      );
      expect((await installer.getStatus()).installed, isTrue);
    });

    test('a whole file with the right checksum installs without the server',
        () async {
      final gz = gzip.encode(await validDb());
      final installer = withAsset(gz, url: 'https://example.com/not-published.gz');
      partial().writeAsBytesSync(gz);
      var asked = false;
      expect(
        await installer.installFromReleaseAsset(
          client: MockClient((r) async {
            asked = true;
            return http.Response('missing', 404);
          }),
          overwrite: true,
        ),
        isTrue,
      );
      expect(asked, isFalse);
      expect((await installer.getStatus()).installed, isTrue);
    });
  });
}
