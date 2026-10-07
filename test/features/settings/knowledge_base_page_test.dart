// The knowledge-base page: the download/update button for each install
// state, a download that cannot connect, and the build section.
import 'package:arklores/core/gamedata/gamedata_installer.dart';
import 'package:arklores/core/gamedata/gamedata_provider.dart';
import 'package:arklores/features/settings/knowledge_base_page.dart';
import 'package:arklores/shared/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_installer.dart';

Future<void> _pump(WidgetTester tester, FakeInstaller installer) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        gameDataInstallStatusProvider.overrideWith((ref) async => installer.status),
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
}

Future<void> _pumpStatus(WidgetTester tester, GameDataInstallStatus status) =>
    _pump(tester, FakeInstaller(status));

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  group('download button', () {
    testWidgets('not installed: download is offered', (tester) async {
      await _pumpStatus(tester, installStatus(installed: false, releaseSha: 'aa'));
      expect(find.text('下载'), findsOneWidget);
      expect(find.byKey(const Key('kb-redownload')), findsNothing);
    });

    testWidgets('installed and current: nothing to update', (tester) async {
      await _pumpStatus(
        tester,
        installStatus(installed: true, installedSha: 'AA', releaseSha: 'aa'),
      );
      expect(find.text('已是最新'), findsOneWidget);
      expect(find.text('更新'), findsNothing);
      final button = tester
          .widget<ElevatedButton>(find.byKey(const Key('kb-download-button')));
      expect(button.onPressed, isNull);
      expect(find.byKey(const Key('kb-redownload')), findsOneWidget);
    });

    testWidgets('a different official asset: update is offered',
        (tester) async {
      await _pumpStatus(
        tester,
        installStatus(installed: true, installedSha: 'aa', releaseSha: 'bb'),
      );
      expect(find.text('更新'), findsOneWidget);
      final button = tester
          .widget<ElevatedButton>(find.byKey(const Key('kb-download-button')));
      expect(button.onPressed, isNotNull);
      expect(find.byKey(const Key('kb-redownload')), findsNothing);
    });

    testWidgets('download again asks first', (tester) async {
      await _pumpStatus(
        tester,
        installStatus(installed: true, installedSha: 'aa', releaseSha: 'aa'),
      );
      await tester.tap(find.byKey(const Key('kb-redownload')));
      await tester.pumpAndSettle();
      expect(find.text('重新下载知识库？'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(find.text('重新下载知识库？'), findsNothing);
    });
  });

  testWidgets(
      'a download that cannot connect shows the attempt and the way around '
      'it, and can be cancelled', (tester) async {
    await _pump(tester, SilentInstaller(installStatus(installed: false, releaseSha: 'aa')));
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

  testWidgets('the build section: GitHub token, build and check for updates',
      (tester) async {
    await _pumpStatus(tester, installStatus(installed: false));
    expect(find.text('GitHub Token（可选）'), findsOneWidget);
    expect(find.text('保存'), findsOneWidget);
    expect(find.text('从源仓库构建'), findsWidgets); // card title + button
    expect(find.text('检查更新'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
