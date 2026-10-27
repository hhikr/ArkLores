import 'dart:convert';
import 'dart:io';

import 'package:arklores/core/update/app_update.dart';
import 'package:arklores/core/update/app_update_provider.dart';
import 'package:arklores/features/settings/settings_service.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../support/app_update_fixture.dart';
import '../../support/temp_dir.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test('automatic checks default off and settings persist', () async {
    final settings = SettingsService();
    expect(await settings.loadAutoUpdateCheck(), isFalse);
    expect(await settings.loadLastUpdateCheck(), isNull);
    await settings.saveAutoUpdateCheck(true);
    expect(await SettingsService().loadAutoUpdateCheck(), isTrue);
    await settings.saveAutoUpdateCheck(false);
    expect(await SettingsService().loadAutoUpdateCheck(), isFalse);
  });

  test('startup checks never download and count failures towards 24-hour limit',
      () async {
    final settings = SettingsService();
    var requests = 0;
    final updater = AppUpdater(
      client: () => MockClient((request) async {
        requests++;
        expect(request.url.host, 'api.github.com');
        return http.Response('rate limited', 403);
      }),
    );
    AppUpdateNotifier create() => AppUpdateNotifier(
          updater: updater,
          installer: AppInstaller(enabled: false),
          settings: settings,
          currentVersion: '0.20.0',
        );
    final now = DateTime.utc(2026, 10, 26);
    final first = create();
    addTearDown(first.dispose);
    await first.autoCheck(enabled: false, now: now);
    expect(requests, 0);
    await first.autoCheck(enabled: true, now: now);
    expect(first.state.phase, AppUpdatePhase.failed);
    expect(requests, 1);
    final second = create();
    addTearDown(second.dispose);
    await second.autoCheck(
      enabled: true,
      now: now.add(const Duration(hours: 23)),
    );
    expect(requests, 1);
    await second.autoCheck(
      enabled: true,
      now: now.add(const Duration(hours: 24)),
    );
    expect(requests, 2);
  });

  test('verified APK waits for permission then installs once on resume',
      () async {
    final dir = await Directory.systemTemp.createTemp('update_provider_');
    addTearDown(() => deleteTempDir(dir));
    const channel = MethodChannel('test/app_update');
    var allowed = false;
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      if (call.method == 'canInstall') return allowed;
      if (call.method == 'install') {
        expect(
          File((call.arguments as Map)['path'] as String).existsSync(),
          isTrue,
        );
      }
      return null;
    });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    final bytes = utf8.encode('APK');
    final notifier = AppUpdateNotifier(
      currentVersion: '0.20.0',
      settings: SettingsService(),
      installer: AppInstaller(channel: channel, enabled: true),
      updater: AppUpdater(
        cacheDirectory: () async => dir,
        client: () => MockClient((request) async {
          if (request.url.host == 'api.github.com') {
            return http.Response(
              jsonEncode([appReleaseJson('0.21.0')]),
              200,
            );
          }
          if (request.url.path.endsWith('.sha256')) {
            return http.Response(sha256.convert(bytes).toString(), 200);
          }
          return http.Response.bytes(bytes, 200);
        }),
      ),
    );
    addTearDown(notifier.dispose);
    await notifier.check();
    expect(notifier.state.phase, AppUpdatePhase.available);
    expect(calls, isEmpty);
    await notifier.downloadAndInstall('test');
    expect(notifier.state.phase, AppUpdatePhase.needsPermission);
    expect(calls, isNot(contains('install')));
    await notifier.openInstallSettings();
    expect(calls, contains('openInstallSettings'));
    await notifier.onResumed();
    expect(notifier.state.phase, AppUpdatePhase.needsPermission);
    allowed = true;
    await Future.wait([notifier.onResumed(), notifier.onResumed()]);
    expect(notifier.state.phase, AppUpdatePhase.ready);
    expect(calls.where((c) => c == 'install'), hasLength(1));
    await notifier.onResumed();
    expect(calls.where((c) => c == 'install'), hasLength(1));
  });
}
