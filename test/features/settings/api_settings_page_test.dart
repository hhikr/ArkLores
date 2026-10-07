// API settings: the fields show what is configured, a save persists chat
// and embedding settings together, a pasted non-key is refused.
import 'package:arklores/core/llm/llm_client.dart';
import 'package:arklores/features/settings/api_settings_page.dart';
import 'package:arklores/features/settings/settings_service.dart';
import 'package:arklores/shared/l10n/generated/app_localizations.dart';
import 'package:arklores/shared/providers/settings_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/plain_theme.dart';

const _current = LLMConfig(
  chatBaseUrl: 'https://api.example.com/v1',
  chatApiKey: 'old-key',
  chatModel: 'm1',
);

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  Future<ProviderContainer> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        initialApiConfigProvider.overrideWithValue(_current),
        plainThemeOverride(),
      ],
      child: MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const ApiSettingsPage(),
      ),
    ),);
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(tester.element(find.byType(ApiSettingsPage)));
  }

  /// The six fields: chat URL, key, model; embedding URL, key, model.
  Finder field(int i) => find.byType(TextField).at(i);

  Future<void> save(WidgetTester tester) async {
    await tester.ensureVisible(find.byType(ElevatedButton));
    await tester.tap(find.byType(ElevatedButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('shows the configured values; keys stay out of the keyboard',
      (tester) async {
    await pump(tester);
    expect(find.byType(TextField), findsNWidgets(6));
    expect(tester.widget<TextField>(field(0)).controller!.text, _current.chatBaseUrl);
    expect(tester.widget<TextField>(field(1)).controller!.text, 'old-key');
    expect(tester.widget<TextField>(field(2)).controller!.text, 'm1');
    for (final key in [field(1), field(4)]) {
      final f = tester.widget<TextField>(key);
      expect(f.autocorrect, isFalse);
      expect(f.enableSuggestions, isFalse);
    }
  });

  testWidgets('saving stores chat and embedding settings', (tester) async {
    final container = await pump(tester);
    await tester.enterText(field(1), ' new-key ');
    await tester.enterText(field(2), 'm2');
    await tester.enterText(field(4), 'embed-key');
    await save(tester);

    expect(container.read(apiConfigProvider).chatApiKey, 'new-key');
    final stored = await SettingsService().loadApiConfig();
    expect([stored.chatBaseUrl, stored.chatApiKey, stored.chatModel],
        [_current.chatBaseUrl, 'new-key', 'm2'],);
    expect((await SettingsService().loadEmbeddingConfig()).apiKey, 'embed-key');
    expect(find.text('✓ 已保存'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('pasted text that is not a key is refused', (tester) async {
    final container = await pump(tester);
    await tester.enterText(field(1), '截图中的完整报错具体内容为：下载失败');
    await save(tester);
    expect(find.byType(SnackBar), findsOneWidget);
    expect(container.read(apiConfigProvider).chatApiKey, 'old-key');
    expect((await SettingsService().loadApiConfig()).chatApiKey, isEmpty);
  });
}
