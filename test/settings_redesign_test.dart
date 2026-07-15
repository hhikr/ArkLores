import 'package:arklores/features/settings/settings_page.dart';
import 'package:arklores/main.dart';
import 'package:arklores/shared/l10n/generated/app_localizations.dart';
import 'package:arklores/shared/providers/theme_provider.dart';
import 'package:arklores/shared/theme/ark_theme_tokens.dart';
import 'package:arklores/shared/theme/endfield_theme_tokens.dart';
import 'package:arklores/shared/widgets/theme_aware_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('theme backgrounds follow the revised palette without changing yellow',
      () {
    final ark = ArkThemeTokens();
    final endfield = EndfieldThemeTokens();

    expect(ark.bgPrimary.r, closeTo(ark.bgPrimary.g, 0.01));
    expect(ark.bgPrimary.g, closeTo(ark.bgPrimary.b, 0.01));
    expect(endfield.isDark, isFalse);
    expect(endfield.bgPrimary.computeLuminance(), greaterThan(0.85));
    expect(endfield.cardSurface.computeLuminance(), greaterThan(0.95));
    expect(ark.accentPrimary, const Color(0xFF0BA0D0));
    expect(endfield.accentPrimary, const Color(0xFFF8D439));
  });

  testWidgets('settings redesign fits a narrow Chinese viewport',
      (tester) async {
    tester.view.physicalSize = const Size(720, 1600);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_testApp(locale: const Locale('zh')));
    await tester.pumpAndSettle();

    expect(find.text('设置'), findsOneWidget);
    expect(find.text('知识库管理'), findsNWidgets(2));
    expect(find.text('夜间'), findsOneWidget);
    expect(tester.getSize(find.text('知识库管理').first).height, lessThan(32));
    final cardWidths = List.generate(
      4,
      (index) => tester.getSize(find.byType(ThemeAwareCard).at(index)).width,
    );
    expect(cardWidths.first, closeTo(301, 1));
    for (final width in cardWidths.skip(1)) {
      expect(width, closeTo(cardWidths.first, 0.1));
    }
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('日间'));
    await tester.pumpAndSettle();

    final context = tester.element(find.byType(SettingsPage));
    final container = ProviderScope.containerOf(context);
    expect(
        container.read(themeProvider.notifier).currentTheme, AppTheme.endfield);
    expect(tester.takeException(), isNull);
  });

  testWidgets('settings redesign supports English and enlarged text',
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
    expect(find.text('DAY'), findsOneWidget);
    expect(find.text('Knowledge Base Management'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });
}

Widget _testApp({required Locale locale, double textScale = 1}) {
  return ProviderScope(
    child: Consumer(
      builder: (context, ref, _) {
        final tokens = ref.watch(themeProvider);
        return MaterialApp(
          theme: buildAppTheme(tokens),
          darkTheme: buildAppTheme(tokens),
          themeMode: ThemeMode.dark,
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
