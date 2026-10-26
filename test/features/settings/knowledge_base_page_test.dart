// The knowledge-base page: the download/update button for each install
// state, a download that cannot connect, and the build section.
import 'package:arklores/core/gamedata/gamedata_build_provider.dart';
import 'package:arklores/core/gamedata/gamedata_installer.dart';
import 'package:arklores/core/gamedata/gamedata_provider.dart';
import 'package:arklores/features/settings/knowledge_base_page.dart';
import 'package:arklores/shared/l10n/generated/app_localizations.dart';
import 'package:arklores/shared/widgets/ef_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_installer.dart';

Future<void> _pump(WidgetTester tester, FakeInstaller installer) async {
  // A tall phone: every card of the page is laid out.
  tester.view.physicalSize = const Size(800, 3200);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        gameDataInstallStatusProvider.overrideWith((ref) async => installer.status),
        gameDataInstallerProvider.overrideWithValue(installer),
        // The other game's page is kept alive beside the shown one.
        endfieldInstallStatusProvider
            .overrideWith((ref) async => installStatus(installed: false)),
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
      // A badge says so; the one button is "download again".
      expect(find.byKey(const Key('kb-status-current')), findsOneWidget);
      expect(find.text('已是最新'), findsOneWidget);
      expect(find.text('更新'), findsNothing);
      expect(find.byKey(const Key('kb-download-button')), findsNothing);
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
          .widget<AppButton>(find.byKey(const Key('kb-download-button')));
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

  testWidgets('the update from game data: check, update, and the GitHub '
      'token folded away', (tester) async {
    await _pumpStatus(tester, installStatus(installed: false));
    expect(find.text('用游戏数据更新'), findsOneWidget);
    expect(find.text('拉取并更新'), findsOneWidget);
    expect(find.text('检查更新'), findsOneWidget);
    // The token is one folded row until asked for.
    expect(find.text('GitHub Token（可选）'), findsOneWidget);
    expect(find.text('保存'), findsNothing);
    await tester.ensureVisible(find.byKey(const Key('kb-build-token-toggle')));
    await tester.tap(find.byKey(const Key('kb-build-token-toggle')));
    await tester.pumpAndSettle();
    expect(find.text('保存'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // After an update the installed commit is the latest one: the button that
  // pulls is off (it stayed live and ran the whole check again), the check
  // button is not, and another database put in place turns it on again.
  testWidgets('after an update there is nothing to pull', (tester) async {
    final build = _DoneBuild();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          gameDataInstallStatusProvider.overrideWith(
            (ref) async => installStatus(installed: true, builtLocally: true),
          ),
          endfieldInstallStatusProvider
              .overrideWith((ref) async => installStatus(installed: false)),
          gameDataBuildProvider.overrideWith((ref) => build),
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
    await tester.scrollUntilVisible(
      find.byKey(const Key('kb-build-start')),
      200,
      scrollable: find.descendant(
        of: find.byKey(const ValueKey('kb-game-arknights')),
        matching: find.byType(Scrollable),
      ),
    );
    ElevatedButton pull() => tester
        .widget<ElevatedButton>(find.byKey(const Key('kb-build-start')));
    expect(pull().onPressed, isNull);
    final check = tester.widget<OutlinedButton>(
      find.ancestor(
        of: find.text('检查更新'),
        matching: find.byWidgetPredicate((w) => w is OutlinedButton),
      ),
    );
    expect(check.onPressed, isNotNull);
    // The same once the "done" note is gone.
    build.dismissDone();
    await tester.pump();
    expect(pull().onPressed, isNull);

    build.installedChanged('older');
    await tester.pump();
    expect(pull().onPressed, isNotNull);
  });

  // 0.14: one page per game, the same parts in the same order; nothing on
  // the page says what the AI uses as evidence (it was out of date).
  testWidgets('each game has its own page, chosen in the top bar',
      (tester) async {
    await _pumpStatus(
      tester,
      installStatus(
        installed: true,
        installedSha: 'aa',
        releaseSha: 'aa',
        manifest: const {
          'story_line_count': '1200',
          'normalized_record_count': '340',
          'source_arknights_commit': 'a550f5e0123',
        },
      ),
    );
    expect(find.byType(AppBar), findsNothing);
    expect(find.byKey(const ValueKey('kb-tab-arknights')), findsOneWidget);
    expect(find.byKey(const ValueKey('kb-tab-endfield')), findsOneWidget);
    expect(find.text('明日方舟知识库'), findsOneWidget);
    expect(find.textContaining('不作为 AI 的证据来源'), findsNothing);
    // What is in it, in the reader's words (no table names).
    for (final fact in ['剧情 1200 行', '资料 340 条', '数据版本 a550f5e']) {
      expect(find.text(fact), findsOneWidget, reason: fact);
    }
    expect(find.textContaining('entities'), findsNothing);
    expect(find.text('用游戏数据更新'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('kb-tab-endfield')));
    await tester.pumpAndSettle();
    expect(find.text('明日方舟知识库'), findsNothing);
    expect(find.text('用游戏数据更新'), findsNothing);
    expect(find.textContaining('随 App 发布更新'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // 0.14: a knowledge base updated on the device is newer than the official
  // asset; that asset is not offered as an "update" over it.
  testWidgets('updated on this device: no update offered, going back to '
      'the official one asks first', (tester) async {
    final installer = FakeInstaller(
      installStatus(installed: true, releaseSha: 'aa', builtLocally: true),
    );
    await _pump(tester, installer);
    expect(installer.status.updateAvailable, isFalse);
    expect(find.byKey(const Key('kb-status-local')), findsOneWidget);
    expect(find.text('本机更新'), findsOneWidget);
    expect(find.text('更新'), findsNothing);
    expect(find.byKey(const Key('kb-download-button')), findsNothing);
    expect(find.textContaining('有新版官方知识库'), findsNothing);
    expect(find.text('换回官方版本'), findsOneWidget);

    await tester.tap(find.byKey(const Key('kb-redownload')));
    await tester.pumpAndSettle();
    expect(find.text('换回官方知识库？'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(installer.downloads, 0);
    expect(tester.takeException(), isNull);
  });
}

/// The card's state right after a successful update.
class _DoneBuild extends GameDataBuildNotifier {
  _DoneBuild() : super(onInstalled: () {}) {
    state = const GameDataBuildUiState(
      phase: GameDataBuildPhase.done,
      latestCommit: 'latest',
      installedCommit: 'latest',
      incremental: true,
    );
  }
}
