import 'dart:io';

import 'package:arklores/core/gamedata/story_art_pack_installer.dart';
import 'package:arklores/core/gamedata/story_art_pack_provider.dart';
import 'package:arklores/core/library/story_art.dart';
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
                (ref) async => StoryArtPackStatus(installed: installed),
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
        expect(container.read(storyArtModeProvider), StoryArtMode.images);
        final row = find.byKey(const ValueKey('settings-story-art'));
        expect(
          tester.getTopLeft(row).dy,
          greaterThan(tester
              .getTopLeft(
                find.byKey(const ValueKey('settings-profile-sections')),
              )
              .dy,),
        );
        final labels = ['图片', '只标出', '不显示'];
        final descriptions = [
          '阅读器里显示场景、CG 与特写图。',
          '只标出换场景、CG 与特写的位置，不显示图。',
          '阅读器里不显示剧情美术。',
        ];
        for (final (i, mode) in StoryArtMode.values.indexed) {
          await tester.tap(find.text(labels[i]));
          await tester.pumpAndSettle();
          expect(container.read(storyArtModeProvider), mode);
          expect(await SettingsService().loadStoryArtMode(), mode);
          expect(
            find.text(descriptions[i] + (installed ? '' : ' 需要剧情美术包')),
            findsOneWidget,
          );
          expect(
            tester
                .widget<SegmentedChoice<StoryArtMode>>(
                  find.byType(SegmentedChoice<StoryArtMode>),
                )
                .value,
            mode,
          );
          if (installed && Platform.environment['T6_REAL_DATA'] == 'true') {
            await shoot(
              tester,
              '${dark ? 'dark' : 'light'}_settings_${mode.name}',
              pixelRatio: 1,
            );
          }
        }
        expect(tester.takeException(), isNull);
      });
    }
  }
}
