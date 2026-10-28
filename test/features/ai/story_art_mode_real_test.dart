// Real-library screenshots, enabled with T6_REAL_DATA and ARKLORES_SHOT_DIR.
import 'dart:io';

import 'package:arklores/core/gamedata/story_art_pack.dart';
import 'package:arklores/core/gamedata/story_art_pack_provider.dart';
import 'package:arklores/core/gamedata/story_coverage_models.dart';
import 'package:arklores/core/library/story_art.dart';
import 'package:arklores/features/ai/reader_story_art.dart';
import 'package:arklores/features/ai/story_labels_provider.dart';
import 'package:arklores/features/ai/story_reader_page.dart';
import 'package:arklores/main.dart' show buildAppTheme;
import 'package:arklores/shared/l10n/generated/app_localizations.dart';
import 'package:arklores/shared/providers/settings_provider.dart';
import 'package:arklores/shared/providers/theme_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/memory_user_store.dart';
import '../../support/screenshot.dart';
import '../../support/sqlite.dart';
import '../library/library_ui_test.dart' as fixtures;

const _db =
    'C:/Users/hhikr/Desktop/ArkLores/build/gamedata_portraits/arklores_gamedata_zh.db';
const _pack =
    'C:/Users/hhikr/Desktop/ArkLores/build/story_art/arklores_story_art_zh.db';

/// The story with the longest CG segment found (116–222).
const _longCg = 'activities/act33side/level_act33side_07_beg.txt';

/// name → (story, the line opened at, open the progress panel, then
/// scrolled up by).
const _cases = {
  'marks_scene': (_longCg, 38, false, 0.0),
  'marks_cg': (_longCg, 115, false, 0.0),
  'marks_panel': (_longCg, 150, true, 0.0),
};

class _Story {
  _Story(this.lines, this.art, this.pack);
  final List<StoryLineEntry> lines;
  final ReaderStoryArt art;
  final StoryArtPack pack;
}

void main() {
  final enabled = Platform.environment['T6_REAL_DATA'] == 'true';
  final stories = <String, _Story>{};

  setUpAll(() async {
    if (!enabled) return;
    useSqfliteFfi();
    for (final font in {
      'Roboto': 'assets/fonts/NotoSansSC.ttf',
      'Saira': 'assets/fonts/Saira.ttf',
      'NotoSansSC': 'assets/fonts/NotoSansSC.ttf',
      'EndfieldCipher': 'assets/fonts/EndfieldByButan.ttf',
      'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
    }.entries) {
      await (FontLoader(font.key)..addFont(rootBundle.load(font.value))).load();
    }
    final db = await databaseFactoryFfi.openDatabase(
      File(_db).absolute.path,
      options: OpenDatabaseOptions(readOnly: true),
    );
    final source = StoryArtPack(File(_pack).absolute.path);
    for (final id in {for (final c in _cases.values) c.$1}) {
      final rows = await db.query(
        'story_lines',
        where: 'story_id = ?',
        whereArgs: [id],
        orderBy: 'line_index',
      );
      final lines = [
        for (final row in rows)
          StoryLineEntry(
            lineIndex: row['line_index'] as int,
            content: row['content'] as String,
            speaker: row['speaker'] as String?,
            kind: row['kind'] as String?,
          ),
      ];
      final events = await readStoryArtEvents(db, [id]);
      final info = await source.artInfo([
        for (final e in events)
          if (e.image != null) (e.image!, e.kind),
      ]);
      final titles = <String, StoryArtTitle?>{};
      for (final e in events.where((e) => e.kind == 'cg' && e.image != null)) {
        titles[e.image!] = await source.artTitle(e.image!);
      }
      final shots = arrangeStoryArt(
        events,
        (image, kind) => info[(image, kind)]?.solid,
        titleGroup: (image) => titles[image]?.groupKey,
      );
      stories[id] = _Story(
        lines,
        ReaderStoryArt(shots, info, titles),
        source,
      );
    }
    await db.close();
    addTearDown(source.close);
  });

  Future<void> open(
    WidgetTester tester,
    String id,
    int? resume, {
    required bool dark,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final story = stories[id]!;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...fixtures.overrides(MemoryUserStore()),
          initialStoryArtModeProvider.overrideWithValue(StoryArtMode.marks),
          initialThemeProvider
              .overrideWithValue(dark ? AppTheme.ark : AppTheme.endfield),
          storyArtPackProvider.overrideWith((ref) async => story.pack),
          storyFullLinesProvider.overrideWith((ref, _) async => story.lines),
          readerStoryArtProvider.overrideWith((ref, key) async => story.art),
        ],
        child: Consumer(
          builder: (context, ref, _) => MaterialApp(
            theme: buildAppTheme(ref.watch(themeProvider)),
            locale: const Locale('zh'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Shot(
              child: StoryReaderPage(storyId: id, resumeLine: resume),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final dark in [false, true]) {
    final theme = dark ? 'dark' : 'light';
    for (final c in _cases.entries) {
      testWidgets(
        'shot ${c.key} $theme',
        (tester) async {
          final (id, resume, panel, scroll) = c.value;
          await open(tester, id, resume, dark: dark);
          if (scroll > 0) {
            final position = tester
                .state<ScrollableState>(
                  find
                      .descendant(
                        of: find.byKey(const ValueKey('story-reader-scroll')),
                        matching: find.byType(Scrollable),
                      )
                      .first,
                )
                .position;
            position.jumpTo(position.pixels + scroll);
            for (var i = 0; i < 6; i++) {
              await tester.pumpAndSettle();
              await tester.runAsync(
                () => Future<void>.delayed(const Duration(seconds: 1)),
              );
            }
            await tester.pumpAndSettle();
          }
          if (panel) {
            await tester.tap(find.byKey(const ValueKey('page-title')));
            await tester.pumpAndSettle();
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(seconds: 1)),
            );
            await tester.pumpAndSettle();
          }
          await shoot(tester, '${theme}_${c.key}', pixelRatio: 1);
          expect(tester.takeException(), isNull);
        },
        skip: !enabled,
      );
    }
  }
}
