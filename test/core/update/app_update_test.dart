import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:arklores/core/gamedata/resumable_download.dart';
import 'package:arklores/core/update/app_update.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../support/app_update_fixture.dart';
import '../../support/temp_dir.dart';

void main() {
  test('semantic comparison handles minor and patch numbers', () {
    expect(
      compareAppVersions(
        parseAppVersion('v0.20.0')!,
        parseAppVersion('0.9.9')!,
      ),
      greaterThan(0),
    );
    expect(
      compareAppVersions(
        parseAppVersion('1.2.10')!,
        parseAppVersion('1.2.9')!,
      ),
      greaterThan(0),
    );
    expect(compareAppVersions([1, 2, 3], [1, 2, 3]), 0);
    expect(compareAppVersions([0, 20, 0], [1, 0, 0]), lessThan(0));
    expect(parseAppVersion('gamedata-channel'), isNull);
    expect(parseAppVersion('1.0.0-beta'), isNull);
  });

  test('selects stable app tags with both assets, by semantic version', () {
    final releases = [
      {'tag_name': 'gamedata-channel'},
      appReleaseJson('2.0.0', prerelease: true),
      {...appReleaseJson('3.0.0'), 'draft': true},
      {...appReleaseJson('4.0.0'), 'assets': <Object>[]},
      {...appReleaseJson('5.0.0'), 'tag_name': '5.0.0'},
      appReleaseJson('0.9.9'),
      appReleaseJson('0.20.1'),
      appReleaseJson('0.20.0'),
    ];
    final latest = pickLatestAppRelease(releases)!;
    expect(latest.tag, 'v0.20.1');
    expect(latest.apkName, 'ArkLores-0.20.1.apk');
    expect(latest.notesExcerpt(), 'Changes\n· Faster reading');
  });

  test('public request sends no credentials and rejects unusable responses',
      () async {
    for (final response in [
      http.Response('[]', 200),
      http.Response('oops', 200),
      http.Response('rate limit', 403),
    ]) {
      final updater = AppUpdater(
        client: () => MockClient((request) async {
          expect(request.headers.containsKey('authorization'), isFalse);
          return response;
        }),
      );
      await expectLater(
        updater.latest(),
        throwsA(
          isA<AppUpdateException>()
              .having((e) => e.failure, 'failure', AppUpdateFailure.check),
        ),
      );
    }
  });

  group('downloads', () {
    late Directory dir;
    final release = AppRelease.fromJson(appReleaseJson('1.0.0'))!;
    final bytes = utf8.encode('test APK content');
    final checksum = sha256.convert(bytes).toString();
    setUp(
      () async =>
          dir = await Directory.systemTemp.createTemp('arklores_update_'),
    );
    tearDown(() => deleteTempDir(dir));

    test('cancels while waiting for checksum without starting APK request',
        () async {
      final waiting = Completer<http.Response>();
      final started = Completer<void>();
      final token = GameDataDownloadToken();
      final updater = AppUpdater(
        cacheDirectory: () async => dir,
        client: () => MockClient((request) {
          expect(request.url.path, '/app.sha256');
          started.complete();
          return waiting.future;
        }),
      );
      final result = updater.download(release, cancelToken: token);
      final rejected =
          expectLater(result, throwsA(isA<GameDataDownloadCancelled>()));
      await started.future;
      token.cancel();
      await rejected;
      waiting.complete(http.Response(checksum, 200));
    });

    AppUpdater updater({required bool valid, bool resume = false}) =>
        AppUpdater(
          cacheDirectory: () async => dir,
          maxAttempts: 1,
          client: () => MockClient((request) async {
            if (request.url.path.endsWith('.sha256')) {
              return http.Response(
                '${valid ? checksum : '0' * 64}  ${release.apkName}\n',
                200,
              );
            }
            if (resume) {
              expect(request.headers['Range'], 'bytes=4-');
              return http.Response.bytes(bytes.sublist(4), 206);
            }
            return http.Response.bytes(bytes, 200);
          }),
        );

    test('rejects and removes APK on checksum mismatch', () async {
      await expectLater(
        updater(valid: false).download(release),
        throwsA(
          isA<AppUpdateException>()
              .having((e) => e.failure, 'failure', AppUpdateFailure.checksum),
        ),
      );
      expect(
        await File('${dir.path}/updates/${release.apkName}').exists(),
        isFalse,
      );
      expect(
        await File('${dir.path}/updates/${release.apkName}.download').exists(),
        isFalse,
      );
    });

    test('resumes partial bytes with matching checksum and reuses verified APK',
        () async {
      final folder = await Directory('${dir.path}/updates').create();
      final partial = File('${folder.path}/${release.apkName}.download');
      await partial.writeAsBytes(bytes.sublist(0, 4));
      await File('${partial.path}.key').writeAsString(checksum);
      final file = await updater(valid: true, resume: true).download(release);
      expect(await file.readAsBytes(), bytes);
      final cached = await updater(valid: true, resume: true).download(release);
      expect(cached.path, file.path);
    });
  });
}
