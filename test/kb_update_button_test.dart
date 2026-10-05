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
    void Function(GameDataInstallPhase phase, int attempt)? onPhase,
    GameDataDownloadToken? cancelToken,
    bool overwrite = false,
    int maxAttempts = 5,
    Duration retryDelay = const Duration(seconds: 3),
    Duration connectTimeout = const Duration(seconds: 90),
    Duration stallTimeout = const Duration(seconds: 60),
  }) async {
    downloads++;
    return true;
  }
}

/// An installer whose server never answers: it reports the second connection
/// attempt and waits until the user cancels.
class _SilentInstaller extends _FakeInstaller {
  _SilentInstaller(super.status);

  @override
  Future<bool> installFromReleaseAsset({
    http.Client? client,
    void Function(int receivedBytes, int? totalBytes)? onProgress,
    void Function(GameDataInstallPhase phase, int attempt)? onPhase,
    GameDataDownloadToken? cancelToken,
    bool overwrite = false,
    int maxAttempts = 5,
    Duration retryDelay = const Duration(seconds: 3),
    Duration connectTimeout = const Duration(seconds: 90),
    Duration stallTimeout = const Duration(seconds: 60),
  }) async {
    onPhase?.call(GameDataInstallPhase.connecting, 2);
    await cancelToken!.whenCancelled;
    throw const GameDataDownloadCancelled();
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

  group('a download that cannot connect', () {
    testWidgets('shows the attempt, the way around it, and can be cancelled',
        (tester) async {
      final installer = _SilentInstaller(_status(installed: false, releaseSha: 'aa'));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            gameDataInstallStatusProvider
                .overrideWith((ref) async => installer.status),
            gameDataInstallerProvider.overrideWithValue(installer),
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
      await tester.tap(find.byKey(const Key('kb-download-button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('下载中'), findsOneWidget);
      expect(find.textContaining('正在连接服务器…（第 2 次尝试）'), findsOneWidget);
      expect(find.textContaining('.download.gz'), findsOneWidget);
      expect(find.byKey(const Key('kb-cancel-download')), findsOneWidget);

      await tester.tap(find.byKey(const Key('kb-cancel-download')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('下载'), findsOneWidget);
      expect(find.byKey(const Key('kb-cancel-download')), findsNothing);
      // A cancel is not an error: no manual hint under a failure either.
      expect(find.textContaining('.download.gz'), findsNothing);
    });

    test('phases reach the state; cancel ends without an error', () async {
      final installer = _SilentInstaller(_status(installed: false, releaseSha: 'aa'));
      final container = ProviderContainer(
        overrides: [gameDataInstallerProvider.overrideWithValue(installer)],
      );
      addTearDown(container.dispose);
      final notifier = container.read(gameDataDownloadProvider.notifier);
      final running = notifier.start(force: true);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      var state = container.read(gameDataDownloadProvider);
      expect(state.downloading, isTrue);
      expect(state.phase, GameDataInstallPhase.connecting);
      expect(state.attempt, 2);
      notifier.cancel();
      await running;
      state = container.read(gameDataDownloadProvider);
      expect(state.downloading, isFalse);
      expect(state.error, isNull);
      expect(state.result, GameDataDownloadResult.none);
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
