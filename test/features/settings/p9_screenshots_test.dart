import 'package:arklores/core/gamedata/story_coverage_models.dart';
import 'package:arklores/features/ai/story_labels_provider.dart';
import 'package:arklores/features/ai/story_reader_page.dart';
import 'package:arklores/features/settings/settings_sections.dart';
import 'package:arklores/main.dart';
import 'package:arklores/shared/l10n/generated/app_localizations.dart';
import 'package:arklores/shared/providers/settings_provider.dart';
import 'package:arklores/shared/providers/theme_provider.dart';
import 'package:arklores/shared/widgets/ef_widgets.dart';
import 'package:arklores/shared/widgets/industrial_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/memory_user_store.dart';
import '../../support/screenshot.dart';
import '../library/library_ui_test.dart' as fixture;

void main() {
  setUpAll(() async {
    for (final font in {
      'Roboto': 'assets/fonts/NotoSansSC.ttf',
      'Saira': 'assets/fonts/Saira.ttf',
      'NotoSansSC': 'assets/fonts/NotoSansSC.ttf',
      'EndfieldCipher': 'assets/fonts/EndfieldByButan.ttf',
      'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
    }.entries) {
      await (FontLoader(font.key)..addFont(rootBundle.load(font.value))).load();
    }
  });
  for (final dark in [false, true]) {
    testWidgets('P9 screenshots ${dark ? "dark" : "light"}', (tester) async {
      FlutterSecureStorage.setMockInitialValues({});
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final prefix = dark ? 'dark' : 'light';
      Future<void> host(Widget page) async {
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              ...fixture.overrides(MemoryUserStore()),
              initialSessionLogsEnabledProvider.overrideWithValue(false),
              initialThemeProvider
                  .overrideWithValue(dark ? AppTheme.ark : AppTheme.endfield),
              storyFullLinesProvider.overrideWith(
                (ref, id) async => [
                  for (var i = 0; i < 200; i++)
                    StoryLineEntry(
                      lineIndex: i,
                      speaker: '甲',
                      content: '第${i + 1}句。队伍沿着道路向前，远处传来通讯声。',
                    ),
                ],
              ),
            ],
            child: Consumer(
              builder: (context, ref, _) {
                final theme = ref.watch(themeProvider);
                return MaterialApp(
                  theme: buildAppTheme(theme),
                  locale: const Locale('zh'),
                  localizationsDelegates:
                      AppLocalizations.localizationsDelegates,
                  supportedLocales: AppLocalizations.supportedLocales,
                  home: Shot(
                      child: IndustrialBackdrop(theme: theme, child: page),),
                );
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.pump(const Duration(milliseconds: 500));
      }

      await host(const AiSettingsPage());
      expect(find.byType(SegmentedChoice<int>), findsNWidgets(2));
      expect(tester.takeException(), isNull);
      await shoot(tester, '${prefix}_settings_default', pixelRatio: 1);
      await tester.tap(find.text('32k'));
      await tester.tap(find.text('50%'));
      // Halfway through the slide.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      await shoot(tester, '${prefix}_settings_sliding', pixelRatio: 1);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await shoot(tester, '${prefix}_settings_min', pixelRatio: 1);
      await host(const StoryReaderPage(storyId: 'a/long.txt'));
      await tester.tap(find.byKey(const ValueKey('page-title')));
      await tester.pumpAndSettle();
      for (final (name, fraction) in [
        ('start', 0.0),
        ('middle', 0.5),
        ('end', 1.0),
      ]) {
        final rect = tester.getRect(find.byType(AppSlider));
        await tester.tapAt(
          Offset(
            rect.left + 14 + fraction * (rect.width - 28),
            rect.center.dy,
          ),
        );
        await tester.pumpAndSettle();
        await tester.pump(const Duration(milliseconds: 500));
        expect(tester.takeException(), isNull);
        await shoot(tester, '${prefix}_reader_$name', pixelRatio: 1);
      }
    });
  }
}
