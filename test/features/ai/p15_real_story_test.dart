// Story art in the reader on the real library and pack: the screenshots of
// P15 composite screenshots. Off by default; run with
// P15_REAL_DATA=true and ARKLORES_SHOT_DIR set (see notes/v0.20).
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

/// name → (story, the line opened at, open the progress panel, then
/// scrolled up by).
const _cases = {
  'cg_layers': (
    'activities/act35side/level_act35side_06_beg.txt',
    55,
    false,
    0.0
  ),
  'scene_layers': (
    'activities/act35side/level_act35side_st03.txt',
    0,
    false,
    0.0
  ),
};

class _Story {
  _Story(this.lines, this.art, this.pack);
  final List<StoryLineEntry> lines;
  final ReaderStoryArt art;
  final StoryArtPack pack;
}

void main() {
  final enabled = Platform.environment['P15_REAL_DATA'] == 'true';
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
          [
            for (final shot in shots) ...[
              (shot.image, shot.kind),
              for (final layer in shot.layers) (layer.image, 'item'),
            ],
          ],
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
      testWidgets(
        'shot ${c.key} $theme',
        (tester) async {
          final (id, _, panel, scroll) = c.value;
          final layered = stories[id]!
              .art
              .shots
              .where(
                (s) =>
                    s.layers.isNotEmpty &&
                    s.kind == (c.key == 'scene_layers' ? 'scene' : 'cg'),
              )
              .first;
          final resume = layered.at;
          debugPrint('P15 reader ${c.key}: $id:${layered.at}');
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
