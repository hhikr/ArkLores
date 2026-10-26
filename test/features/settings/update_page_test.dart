import 'dart:async';
import 'dart:convert';

import 'package:arklores/core/update/app_update.dart';
import 'package:arklores/core/update/app_update_provider.dart';
import 'package:arklores/features/settings/settings_sections.dart';
import 'package:arklores/features/settings/settings_service.dart';
import 'package:arklores/features/settings/update_page.dart';
import 'package:arklores/features/settings/update_startup.dart';
import 'package:arklores/main.dart';
import 'package:arklores/shared/l10n/generated/app_localizations.dart';
import 'package:arklores/shared/providers/theme_provider.dart';
import 'package:arklores/shared/widgets/ef_widgets.dart';
import 'package:arklores/shared/widgets/industrial_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../support/app_update_fixture.dart';
import '../../support/screenshot.dart';

class StatusNotifier extends AppUpdateNotifier {
  StatusNotifier(AppUpdateState initial)
      : super(
          updater: AppUpdater(),
          installer: AppInstaller(enabled: false),
          settings: SettingsService(),
          currentVersion: '0.20.0',
        ) {
    state = initial;
  }
}

Widget testApp({
  required AppUpdateNotifier notifier,
  Widget home = const UpdatePage(),
  bool automatic = false,
  Locale locale = const Locale('zh'),
  double scale = 1,
}) =>
    ProviderScope(
      overrides: [
        appUpdateProvider.overrideWith((ref) => notifier),
        appInstallerProvider.overrideWithValue(AppInstaller(enabled: true)),
        initialAutoUpdateCheckProvider.overrideWithValue(automatic),
      ],
      child: Consumer(
        builder: (context, ref, _) => MaterialApp(
          theme: buildAppTheme(ref.watch(themeProvider)),
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: Shot(
            child: IndustrialBackdrop(
              theme: ref.watch(themeProvider),
              child: home,
            ),
          ),
        ),
      ),
    );

void main() {
  setUpAll(() async {
    if (shotDir == null) return;
    for (final entry in {
      'Roboto': 'assets/fonts/NotoSansSC.ttf',
      'Saira': 'assets/fonts/Saira.ttf',
      'NotoSansSC': 'assets/fonts/NotoSansSC.ttf',
      'EndfieldCipher': 'assets/fonts/EndfieldByButan.ttf',
      'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
    }.entries) {
      await (FontLoader(entry.key)..addFont(rootBundle.load(entry.value)))
          .load();
    }
  });
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  final release = AppRelease.fromJson(appReleaseJson('0.21.0'))!;

  testWidgets(
      'manual check uses mock HTTP, persists switch, shows latest and errors locally',
      (tester) async {
    final reply = Completer<http.Response>();
    final notifier = AppUpdateNotifier(
      updater: AppUpdater(client: () => MockClient((_) => reply.future)),
      installer: AppInstaller(enabled: false),
      settings: SettingsService(),
      currentVersion: '0.20.0',
    );
    await tester.pumpWidget(testApp(notifier: notifier));
    await tester.pumpAndSettle();
    expect(find.text('0.20.0（build 43）'), findsOneWidget);
    expect(await SettingsService().loadAutoUpdateCheck(), isFalse);
    await tester.tap(find.byKey(const ValueKey('settings-auto-update')));
    await tester.pumpAndSettle();
    expect(await SettingsService().loadAutoUpdateCheck(), isTrue);
    await tester.tap(find.byKey(const ValueKey('update-check')));
    await tester.pump();
    await tester.pump();
    expect(find.text('正在检查。'), findsOneWidget);
    reply.complete(http.Response(jsonEncode([appReleaseJson('0.20.0')]), 200));
    await tester.pumpAndSettle();
    expect(find.text('已是最新版本。'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final phase in AppUpdatePhase.values) {
    testWidgets('update page renders ${phase.name} at narrow width',
        (tester) async {
      tester.view.physicalSize = const Size(390, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final state = AppUpdateState(
        phase: phase,
        release: phase == AppUpdatePhase.idle ||
                phase == AppUpdatePhase.checking ||
                phase == AppUpdatePhase.upToDate
            ? null
            : release,
        received: 1024 * 1024,
        total: 10 * 1024 * 1024,
        failure: AppUpdateFailure.checksum,
      );
      await tester.pumpWidget(testApp(notifier: StatusNotifier(state)));
      await tester.pump(const Duration(milliseconds: 300));
      if (state.release != null) {
        expect(find.text('新版本 0.21.0'), findsOneWidget);
        expect(find.byKey(const ValueKey('update-notes')), findsOneWidget);
      }
      if (phase == AppUpdatePhase.needsPermission ||
          phase == AppUpdatePhase.failed) {
        expect(find.byType(NoticeBox), findsOneWidget);
      }
      if (phase == AppUpdatePhase.downloading) {
        expect(find.byKey(const ValueKey('update-progress')), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
      if (phase == AppUpdatePhase.available ||
          phase == AppUpdatePhase.needsPermission ||
          phase == AppUpdatePhase.failed) {
        await shoot(tester, 'update-${phase.name}-zh');
      }
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('English update notes and actions fit at larger text scale',
      (tester) async {
    tester.view.physicalSize = const Size(390, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      testApp(
        notifier: StatusNotifier(
          AppUpdateState(phase: AppUpdatePhase.available, release: release),
        ),
        locale: const Locale('en'),
        scale: 1.6,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('New version 0.21.0'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('help links to updates with the current version', (tester) async {
    await tester.pumpWidget(
      testApp(
        notifier: StatusNotifier(const AppUpdateState()),
        home: const HelpSettingsPage(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('settings-update')));
    await tester.pumpAndSettle();
    expect(find.byType(UpdatePage), findsOneWidget);
    expect(find.text('0.20.0（build 43）'), findsOneWidget);
  });

  testWidgets('automatic startup check offers a link and never downloads',
      (tester) async {
    var requests = 0;
    final notifier = AppUpdateNotifier(
      updater: AppUpdater(
        client: () => MockClient((request) async {
          requests++;
          expect(request.url.host, 'api.github.com');
          return http.Response(
            jsonEncode([appReleaseJson('0.21.0')]),
            200,
          );
        }),
      ),
      installer: AppInstaller(enabled: false),
      settings: SettingsService(),
      currentVersion: '0.20.0',
    );
    await tester.pumpWidget(
      testApp(
        notifier: notifier,
        automatic: true,
        home: const UpdateStartup(child: Scaffold(body: Text('Home'))),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('有新版本 0.21.0'), findsOneWidget);
    expect(requests, 1);
    await tester.tap(find.text('查看'));
    await tester.pumpAndSettle();
    expect(find.byType(UpdatePage), findsOneWidget);
    expect(find.text('新版本 0.21.0'), findsOneWidget);
    expect(requests, 1);
  });
}
