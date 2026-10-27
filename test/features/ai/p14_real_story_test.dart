// Story art in the reader on the real library and pack: the screenshots of
// P14 and the frame timing of a long CG segment. Off by default; run with
// P14_REAL_DATA=true and ARKLORES_SHOT_DIR set (see notes/v0.20).
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
import '../library/story_art_viewer_test.dart' as viewer;

const _db = 'build/gamedata_portraits/arklores_gamedata_zh.db';
const _pack = 'build/story_art/arklores_story_art_zh.db';

/// The story with the longest CG segment found (116–222).
const _longCg = 'activities/act33side/level_act33side_07_beg.txt';

/// name → (story, the line opened at, open the progress panel, then
/// scrolled up by).
const _cases = {
  'scene_open': (_longCg, null, false, 0.0),
  'scene_change': (_longCg, 38, false, 0.0),
  'cg_start': (_longCg, 115, false, 0.0),
  'cg_end': (_longCg, 217, false, 0.0),
  'cg_tall': ('activities/act6d5/level_act6d5_st01.txt', 101, false, 0.0),
  'cg_empty': ('activities/act12side/level_act12side_st01.txt', 17, false, 560.0),
  'item': ('activities/act35side/level_act35side_06_beg.txt', 55, false, 300.0),
  'panel': (_longCg, 150, true, 0.0),
};

class _Story {
  _Story(this.lines, this.art, this.pack);
  final List<StoryLineEntry> lines;
  final ReaderStoryArt art;
  final StoryArtPack pack;
}

void main() {
  final enabled = Platform.environment['P14_REAL_DATA'] == 'true';
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
        await viewer.memoryPack(
          File(_pack).absolute.path,
          [for (final shot in shots) (shot.image, shot.kind)],
        ),
      );
    }
    await db.close();
    await source.close();
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
    // The pictures decode on real time, one after another.
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(seconds: 1)),
      );
      await tester.pumpAndSettle();
    }
  }

  for (final dark in [false, true]) {
    final theme = dark ? 'dark' : 'light';
    for (final c in _cases.entries) {
      testWidgets('shot ${c.key} $theme', (tester) async {
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
      }, skip: !enabled,);
    }

    testWidgets('long CG stays lazy; scroll timing $theme', (tester) async {
      await open(tester, _longCg, 115, dark: dark);
      final elapsed = <int>[];
      for (var i = 0; i < 20; i++) {
        await tester.drag(
          find.byKey(const ValueKey('story-reader-scroll')),
          const Offset(0, -180),
        );
        final clock = Stopwatch()..start();
        await tester.pump(const Duration(milliseconds: 16));
        elapsed.add(clock.elapsedMicroseconds);
      }
      // 106 lines in the segment: built lazily, a screen's worth at a time.
      expect(find.byType(CgFrameSlice).evaluate().length, lessThan(40));
      expect(tester.takeException(), isNull);
      elapsed.sort();
      // The whole pump on the test clock: wall-clock upper bounds.
      debugPrint(
        'P14 timing $theme: pump median '
        '${elapsed[elapsed.length ~/ 2] / 1000} ms, '
        'max ${elapsed.last / 1000} ms',
      );
      await shoot(tester, '${theme}_cg_middle', pixelRatio: 1);
    }, skip: !enabled,);
  }
}
