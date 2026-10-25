import 'package:arklores/core/llm/llm_client.dart';
import 'package:arklores/features/settings/settings_page.dart';
import 'package:arklores/features/settings/settings_sections.dart';
import 'package:arklores/features/settings/settings_service.dart';
import 'package:arklores/main.dart';
import 'package:arklores/shared/l10n/generated/app_localizations.dart';
import 'package:arklores/shared/providers/settings_provider.dart';
import 'package:arklores/shared/providers/theme_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('AI context warning selection persists at 390px', (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_testApp(locale: const Locale('zh')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('settings-category-ai')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('64k'));
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(tester.element(find.byType(AiSettingsPage)));
    expect(container.read(contextWarnTokensProvider), 64000);
    expect(await SettingsService().loadContextWarnTokens(), 64000);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'the categories, each with what is in it; a category opens its '
      'page, where the theme switch works', (tester) async {
    tester.view.physicalSize = const Size(720, 1600);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_testApp(locale: const Locale('zh')));
    await tester.pumpAndSettle();

    expect(find.text('设置'), findsOneWidget);
    for (final key in ['appearance', 'profile', 'ai', 'knowledge', 'help']) {
      expect(
        find.byKey(ValueKey('settings-category-$key')),
        findsOneWidget,
        reason: key,
      );
    }
    // The settings themselves are a page further.
    expect(find.byKey(const ValueKey('settings-theme')), findsNothing);
    // The rows take the page's width (16 on each side).
    final list = tester.getRect(find.byKey(const ValueKey('settings-list')));
    final row = tester
        .getRect(find.byKey(const ValueKey('settings-category-appearance')));
    expect(row.left, list.left + 16);
    expect(row.right, list.right - 16);
    expect(row.height, greaterThanOrEqualTo(48));
    expect(tester.takeException(), isNull);

    await tester
        .tap(find.byKey(const ValueKey('settings-category-appearance')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('settings-theme')), findsOneWidget);
    await tester.tap(find.text('日间'));
    await tester.pumpAndSettle();

    final context = tester.element(find.byType(AppearanceSettingsPage));
    final container = ProviderScope.containerOf(context);
    expect(
        container.read(themeProvider.notifier).currentTheme, AppTheme.endfield,);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the other categories open their settings', (tester) async {
    tester.view.physicalSize = const Size(720, 1600);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_testApp(locale: const Locale('zh')));
    await tester.pumpAndSettle();

    for (final (key, inside) in [
      ('ai', 'settings-session-logs'),
      ('knowledge', 'settings-profile-sections'),
    ]) {
      await tester.tap(find.byKey(ValueKey('settings-category-$key')));
      await tester.pumpAndSettle();
      expect(find.byKey(ValueKey(inside)), findsOneWidget, reason: key);
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pumpAndSettle();
    }
    await tester.tap(find.byKey(const ValueKey('settings-category-help')));
    await tester.pumpAndSettle();
    expect(find.text('新用户导览'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('English with enlarged text',
      (tester) async {
    tester.view.physicalSize = const Size(840, 1800);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _testApp(locale: const Locale('en'), textScale: 1.6),
    );
    await tester.pumpAndSettle();

    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Knowledge & Library'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester
        .tap(find.byKey(const ValueKey('settings-category-appearance')));
    await tester.pumpAndSettle();
    expect(find.text('DAY'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Widget _testApp({required Locale locale, double textScale = 1}) {
  return ProviderScope(
    overrides: [
      initialSessionLogsEnabledProvider.overrideWithValue(false),
      initialApiConfigProvider.overrideWithValue(const LLMConfig()),
    ],
    child: Consumer(
      builder: (context, ref, _) {
        final tokens = ref.watch(themeProvider);
        return MaterialApp(
          theme: buildAppTheme(tokens),
          darkTheme: buildAppTheme(tokens),
          themeMode: tokens.isDark ? ThemeMode.dark : ThemeMode.light,
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(textScale),
            ),
            child: child!,
          ),
          home: const SettingsPage(),
        );
      },
    ),
  );
}
