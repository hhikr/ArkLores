// Real-library screenshots, enabled with T8_REAL_DATA and ARKLORES_SHOT_DIR.
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
import 'package:arklores/shared/widgets/story_art_composite.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/memory_user_store.dart';
import '../../support/screenshot.dart';
import '../../support/sqlite.dart';
import '../library/library_ui_test.dart' as fixtures;
import '../library/story_art_viewer_test.dart' show memoryPack;

const _db =
    'C:/Users/hhikr/Desktop/ArkLores/build/gamedata_portraits/arklores_gamedata_zh.db';
const _pack =
    'C:/Users/hhikr/Desktop/ArkLores/build/story_art/arklores_story_art_zh.db';

/// The story with the longest CG segment found (116–222).
const _longCg = 'activities/act33side/level_act33side_07_beg.txt';

/// Each case opens immediately before the picture it exercises.
const _cases = {
  'scene': (_longCg, 38),
  'cg': (_longCg, 115),
  'wide': ('activities/act11d7/level_act11d7_st01.txt', 162),
};

class _Story {
  _Story(this.lines, this.art, this.pack);
  final List<StoryLineEntry> lines;
  final ReaderStoryArt art;
  final StoryArtPack pack;
}

void main() {
  final enabled = Platform.environment['T8_REAL_DATA'] == 'true';
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
        await memoryPack(
          _pack,
          {
            for (final shot in shots) ...[
              (shot.image, shot.kind),
              for (final layer in shot.layers) (layer.image, 'item'),
            ],
          }.toList(),
        ),
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
          initialStoryArtModeProvider.overrideWithValue(StoryArtMode.images),
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
          final (id, resume) = c.value;
          await open(tester, id, resume, dark: dark);
          final art = stories[id]!.art;
          final isCg = c.key == 'cg';
          final index = art.shots.indexWhere(
            (s) => isCg
                ? s.kind == 'cg'
                : s.kind == 'scene' &&
                    s.at >= resume &&
                    (c.key != 'wide' || s.layout == 'row'),
          );
          expect(index, greaterThanOrEqualTo(0));
          final head = find.byKey(
            ValueKey(
              'story-art-${isCg ? 'cg' : 'scene'}-toggle-$index',
            ),
          );
          await tester.ensureVisible(head);
          await tester.pumpAndSettle();
          await shoot(tester, '${theme}_${c.key}_collapsed', pixelRatio: 1);
          expect(find.byType(StoryArtComposite), findsNothing);
          await tester.tap(head);
          await tester.pumpAndSettle();
          for (var i = 0; i < 10; i++) {
            await tester.runAsync(
                () => Future<void>.delayed(const Duration(milliseconds: 100)),);
            await tester.pumpAndSettle();
          }
          if (!isCg) {
            final shot = art.shots[index];
            final info = art.info[(shot.image, 'background')]!;
            final size = tester.getSize(find.byKey(
              ValueKey('story-art-scene-picture-$index'),
            ),);
            expect(size.width, 358);
            expect(size.height, closeTo(size.width * info.height / info.width, .01));
            if (c.key == 'wide') {
              expect(shot.layout, 'row');
              expect(info.width, 1280);
              expect(info.height, 501);
            }
          }
          await shoot(tester, '${theme}_${c.key}_expanded', pixelRatio: 1);
          if (c.key != 'wide') {
            await tester.tap(find.byKey(const ValueKey('page-title')));
            await tester.pumpAndSettle();
            for (var i = 0; i < 10; i++) {
              await tester.runAsync(
                () => Future<void>.delayed(const Duration(milliseconds: 100)),
              );
              await tester.pumpAndSettle();
            }
            await shoot(tester, '${theme}_${c.key}_panel', pixelRatio: 1);
            await tester.tap(head);
            await tester.pumpAndSettle();
            await shoot(tester, '${theme}_${c.key}_panel_collapsed',
                pixelRatio: 1,);
          }

          expect(tester.takeException(), isNull);
        },
        skip: !enabled,
      );
    }
  }
}
