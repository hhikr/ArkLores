import 'package:arklores/core/gamedata/gamedata_installer.dart';
import 'package:arklores/core/gamedata/gamedata_provider.dart';
import 'package:arklores/features/settings/knowledge_base_page.dart';
import 'package:arklores/shared/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

GameDataInstallStatus _status({
  required bool installed,
  String? installedSha,
  String? releaseSha,
}) =>
    GameDataInstallStatus(
      installed: installed,
      dbPath: installed ? 'db' : '',
      bytes: installed ? 1 : 0,
      manifest: const {},
      installedAssetSha: installedSha,
      releaseAssetSha: releaseSha,
    );

class _FakeInstaller extends GameDataInstaller {
  _FakeInstaller(this.status);
  final GameDataInstallStatus status;
  var downloads = 0;

  @override
  Future<GameDataInstallStatus> getStatus() async => status;

  @override
  Future<bool> installFromReleaseAsset({
    http.Client? client,
    void Function(int receivedBytes, int? totalBytes)? onProgress,
    bool overwrite = false,
    int maxAttempts = 4,
    Duration retryDelay = const Duration(seconds: 3),
    Duration stallTimeout = const Duration(seconds: 60),
  }) async {
    downloads++;
    return true;
  }
}

Future<void> _pump(WidgetTester tester, GameDataInstallStatus status) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        gameDataInstallStatusProvider.overrideWith((ref) async => status),
        gameDataInstallerProvider.overrideWithValue(_FakeInstaller(status)),
      ],
      child: MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const KnowledgeBasePage(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  group('knowledge base page: update button', () {
    testWidgets('not installed: download is offered', (tester) async {
      await _pump(tester, _status(installed: false, releaseSha: 'aa'));
      expect(find.text('下载'), findsOneWidget);
      expect(find.byKey(const Key('kb-redownload')), findsNothing);
    });

    testWidgets('installed and current: nothing to update', (tester) async {
      await _pump(
        tester,
        _status(installed: true, installedSha: 'AA', releaseSha: 'aa'),
      );
      expect(find.text('已是最新'), findsOneWidget);
      expect(find.text('更新'), findsNothing);
      final button = tester.widget<ElevatedButton>(
        find.byKey(const Key('kb-download-button')),
      );
      expect(button.onPressed, isNull);
      expect(find.byKey(const Key('kb-redownload')), findsOneWidget);
    });

    testWidgets('a different official asset: update is offered',
        (tester) async {
      await _pump(
        tester,
        _status(installed: true, installedSha: 'aa', releaseSha: 'bb'),
      );
      expect(find.text('更新'), findsOneWidget);
      final button = tester.widget<ElevatedButton>(
        find.byKey(const Key('kb-download-button')),
      );
      expect(button.onPressed, isNotNull);
      expect(find.byKey(const Key('kb-redownload')), findsNothing);
    });

    testWidgets('download again asks first', (tester) async {
      await _pump(
        tester,
        _status(installed: true, installedSha: 'aa', releaseSha: 'aa'),
      );
      await tester.tap(find.byKey(const Key('kb-redownload')));
      await tester.pumpAndSettle();
      expect(find.text('重新下载知识库？'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(find.text('重新下载知识库？'), findsNothing);
    });
  });

  group('download notifier', () {
    test('an installed, current knowledge base is not downloaded again',
        () async {
      final installer = _FakeInstaller(
        _status(installed: true, installedSha: 'aa', releaseSha: 'aa'),
      );
      final container = ProviderContainer(
        overrides: [gameDataInstallerProvider.overrideWithValue(installer)],
      );
      addTearDown(container.dispose);
      final notifier = container.read(gameDataDownloadProvider.notifier);
      await notifier.start();
      expect(installer.downloads, 0);
      await notifier.start(force: true);
      expect(installer.downloads, 1);
    });

    test('a newer official asset is downloaded', () async {
      final installer = _FakeInstaller(
        _status(installed: true, installedSha: 'aa', releaseSha: 'bb'),
      );
      final container = ProviderContainer(
        overrides: [gameDataInstallerProvider.overrideWithValue(installer)],
      );
      addTearDown(container.dispose);
      await container.read(gameDataDownloadProvider.notifier).start();
      expect(installer.downloads, 1);
    });
  });
}
