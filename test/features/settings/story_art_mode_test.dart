import 'package:arklores/core/gamedata/story_art_pack_installer.dart';
import 'package:arklores/core/gamedata/story_art_pack_provider.dart';
import 'package:arklores/features/settings/settings_sections.dart';
import 'package:arklores/features/settings/settings_service.dart';
import 'package:arklores/main.dart' show buildAppTheme;
import 'package:arklores/shared/l10n/generated/app_localizations.dart';
import 'package:arklores/shared/providers/settings_provider.dart';
import 'package:arklores/shared/providers/theme_provider.dart';
import 'package:arklores/shared/widgets/ef_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/screenshot.dart';

void main() {
  setUpAll(() async {
    if (shotDir == null) return;
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
    for (final installed in [false, true]) {
      testWidgets('story art choices persist; dark=$dark installed=$installed',
          (tester) async {
        FlutterSecureStorage.setMockInitialValues({});
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              initialThemeProvider.overrideWithValue(
                dark ? AppTheme.ark : AppTheme.endfield,
              ),
              storyArtPackStatusProvider.overrideWith(
                (ref, variant) async => StoryArtPackStatus(installed: installed),
              ),
            ],
            child: Consumer(
              builder: (context, ref, _) => MaterialApp(
                theme: buildAppTheme(ref.watch(themeProvider)),
                locale: const Locale('zh'),
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                home: Shot(
                  child: Material(
                    color: ref.watch(themeProvider).bgPrimary,
                    child: const KnowledgeSettingsPage(),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final container = ProviderScope.containerOf(
          tester.element(find.byType(KnowledgeSettingsPage)),
        );
        expect(container.read(storyArtFoldedProvider), isTrue);
        final row = find.byKey(const ValueKey('settings-story-art'));
        expect(
          tester.getTopLeft(row).dy,
          greaterThan(tester
              .getTopLeft(
                find.byKey(const ValueKey('settings-profile-sections')),
              )
              .dy,),
        );
        final choices = [
          ('默认展开', false, '资料页的剧情美术总览全部展开。故事集里的美术页和阅读器总是显示。'),
          ('默认收起', true, '资料页的剧情美术总览按组收起，点开查看，避免先看到剧透。故事集里的美术页和阅读器总是显示。'),
        ];
        for (final (label, folded, description) in choices) {
          await tester.tap(find.text(label));
          await tester.pumpAndSettle();
          expect(container.read(storyArtFoldedProvider), folded);
          expect(await SettingsService().loadStoryArtFolded(), folded);
          expect(
            find.text(description + (installed ? '' : ' 需要剧情美术包')),
            findsOneWidget,
          );
          expect(
            tester
                .widget<SegmentedChoice<bool>>(
                  find.byType(SegmentedChoice<bool>),
                )
                .value,
            folded,
          );
        }
        expect(tester.takeException(), isNull);
      });
    }
  }
}
