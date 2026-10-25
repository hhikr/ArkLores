// The Wiki page's own state around the WebView (which is an empty box
// here): long site names fit a phone-wide tab bar, closing the page saves
// where it was, and the pages' dark mode follows the app theme.
import 'package:arklores/features/settings/settings_service.dart';
import 'package:arklores/features/wiki/wiki_browser_controls.dart';
import 'package:arklores/features/wiki/wiki_browser_page.dart';
import 'package:arklores/shared/l10n/generated/app_localizations.dart';
import 'package:arklores/shared/providers/theme_provider.dart';
import 'package:arklores/shared/theme/app_theme.dart';
import 'package:arklores/shared/theme/endfield_theme_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_webview.dart';
import '../../support/plain_theme.dart';

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    InAppWebViewPlatform.instance = FakeWebViewPlatform();
  });

  Future<void> pump(WidgetTester tester, {ThemeNotifier? theme}) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        if (theme == null)
          plainThemeOverride()
        else
          themeProvider.overrideWith((ref) => theme),
      ],
      child: MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const WikiBrowserPage(),
      ),
    ),);
    await tester.pump(const Duration(milliseconds: 500));
  }

  testWidgets('long site names fit a phone-wide tab bar', (tester) async {
    await SettingsService().saveWikiSites([
      ...SettingsService.defaultWikiSites,
      const WikiSiteConfig(
        id: 'custom_1',
        label: '一个名字非常非常非常长的自定义资料站点',
        url: 'https://example.com',
      ),
    ]);
    await pump(tester);
    expect(find.textContaining('一个名字'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('closing the page saves the tab and the pages it was on',
      (tester) async {
    await SettingsService().saveWikiTabIndex(1);
    await pump(tester);
    expect(await SettingsService().loadWikiAppliedUrl(0), isNull);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 100));
    final service = SettingsService();
    expect(await service.loadWikiTabIndex(), 1);
    expect(await service.loadWikiAppliedUrl(0),
        SettingsService.defaultWikiSites.first.url,);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the pages follow the app theme; a switch by hand holds '
      'until the theme next changes', (tester) async {
    final theme = _SettableTheme();
    await pump(tester, theme: theme);
    bool dark() =>
        tester.widget<ExpandableTray>(find.byType(ExpandableTray)).isDarkMode;
    Future<void> show(AppThemeTokens tokens) async {
      theme.show(tokens);
      await tester.pump();
    }

    expect(dark(), isTrue); // the dark theme
    await show(EndfieldThemeTokens());
    expect(dark(), isFalse);

    // Dark by hand, on the light theme: kept and saved.
    tester.widget<ExpandableTray>(find.byType(ExpandableTray)).onToggleDarkMode();
    await tester.pump();
    expect(dark(), isTrue);
    expect(await SettingsService().loadWikiDarkMode(), isTrue);

    // The theme turns dark and back: the pages follow it, the switch is gone.
    await show(PlainArkThemeTokens());
    await show(EndfieldThemeTokens());
    expect(dark(), isFalse);
    expect(await SettingsService().loadWikiDarkMode(), isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a saved switch against the theme is restored', (tester) async {
    await SettingsService().saveWikiDarkMode(false);
    await pump(tester, theme: _SettableTheme()); // the dark theme
    expect(
      tester.widget<ExpandableTray>(find.byType(ExpandableTray)).isDarkMode,
      isFalse,
    );
  });

  testWidgets('a saved switch that equals the theme now is dropped: the '
      'theme turned while the app was closed', (tester) async {
    await SettingsService().saveWikiDarkMode(true);
    await pump(tester, theme: _SettableTheme()); // the dark theme
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 100));
    expect(await SettingsService().loadWikiDarkMode(), isNull);
  });
}

/// The app theme, set by the test.
class _SettableTheme extends ThemeNotifier {
  _SettableTheme() : super(PlainArkThemeTokens());

  void show(AppThemeTokens tokens) => state = tokens;
}
