import 'dart:io';

import 'package:arklores/core/gamedata/story_art_pack.dart';
import 'package:arklores/core/gamedata/story_art_pack_provider.dart';
import 'package:arklores/core/gamedata/story_coverage_models.dart';
import 'package:arklores/core/library/collection_story_art.dart';
import 'package:arklores/core/library/library_provider.dart';
import 'package:arklores/core/library/library_queries.dart';
import 'package:arklores/core/library/story_art.dart';
import 'package:arklores/features/ai/story_labels_provider.dart';
import 'package:arklores/features/ai/story_reader_page.dart';
import 'package:arklores/features/library/collection_art_page.dart';
import 'package:arklores/features/library/collection_page.dart';
import 'package:arklores/features/library/story_art_viewer.dart';
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
import '../../support/story_art_pack_fixture.dart';
import '../../support/temp_dir.dart';
import 'library_ui_test.dart' as fixtures;
import 'story_art_viewer_test.dart' as viewer;

void main() {
  final real = Platform.environment['P16_REAL_DATA'] == 'true';
  late Directory dir;
  late StoryArtPack pack;
  List<CollectionArtShot> art = [];
  List<LibraryEntry> realStories = [];
  LibraryCollection collection = const LibraryCollection(
      id: 'fixture',
      kind: 'activity',
      name: 'Collection',
      stories: 0,
      others: 0,);
  setUpAll(() async {
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
    dir = await Directory.systemTemp.createTemp('collection-art');
    if (real) {
      final db = await databaseFactoryFfi.openDatabase(
          File('build/gamedata_portraits/arklores_gamedata_zh.db')
              .absolute
              .path,
          options: OpenDatabaseOptions(readOnly: true),);
      final row = (await db.rawQuery(
              "SELECT id FROM collections WHERE id LIKE '%act35side%' LIMIT 1",))
          .single;
      final id = row['id'] as String;
      collection = (await collectionById(db, id))!;
      final stories = await storiesOf(db, id);
      realStories = stories;
      final events = await readStoryArtEvents(db, stories.map((s) => s.rawId!));
      final source = StoryArtPack(
          File('build/story_art/arklores_story_art_zh.db').absolute.path,);
      final info = await source.artInfo([
        for (final e in events)
          if (e.image != null) (e.image!, e.kind),
      ]);
      art = groupCollectionArt(
          stories, events, (image, kind) => info[(image, kind)]?.solid,);
      await source.close();
      await db.close();
      pack = await viewer.memoryPack(
        File('build/story_art/arklores_story_art_zh.db').absolute.path,
        {
          for (final a in art) ...[
            (a.shot.image, a.shot.kind),
            for (final l in a.shot.layers) (l.image, 'item'),
          ],
        }.toList(),
      );
    } else {
      art = [
        for (var i = 0; i < 9; i++)
          CollectionArtShot(
            i < 4 ? 'first' : 'second',
            i < 4 ? 'First story' : 'Second story',
            StoryArtShot(
                kind: i < 7 ? 'cg' : 'scene',
                image: i < 7 ? 'cg' : 'scene',
                at: i,
                number: i + 1,
                total: 9,),
          ),
      ];
      pack = await viewer.memoryPack((await createStoryArtPack(dir)).path,
          [('cg', 'cg'), ('scene', 'scene')],);
    }
  });
  tearDownAll(() async {
    await pack.close();
    await deleteTempDir(dir);
  });
  Future<void> pump(WidgetTester tester, Widget home,
      {bool dark = false, bool empty = false,}) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        key: UniqueKey(),
        overrides: [
          ...fixtures.overrides(MemoryUserStore()),
          initialThemeProvider
              .overrideWithValue(dark ? AppTheme.ark : AppTheme.endfield),
          storyArtPackProvider.overrideWith((ref) async => pack),
          collectionStoryArtProvider
              .overrideWith((ref, _) async => empty ? [] : art),
          collectionProvider.overrideWith((ref, _) async => collection),
          collectionStoriesProvider.overrideWith((ref, _) async => realStories),
          collectionTypesProvider.overrideWith((ref, _) async => []),
          collectionInlineProvider.overrideWith((ref, _) async => []),
          collectionIntroProvider.overrideWith((ref, _) async => null),
          storyReadingProvider.overrideWith(
            (ref, id) async => StoryReading(
              hostId: id,
              lines: [
                for (var i = 0; i < 12; i++)
                  StoryLineEntry(lineIndex: i, content: 'Line $i'),
              ],
            ),
          ),
        ],
        child: Consumer(
          builder: (context, ref, _) => MaterialApp(
            theme: buildAppTheme(ref.watch(themeProvider)),
            locale: const Locale('zh'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            builder: (_, child) => Shot(child: child!),
            home: home,
          ),
        ),
      ),
    );
    await settle(tester);
  }

  Future<void> checkInitial(WidgetTester tester, int n) async {
    await tester.tap(find.byType(ArtThumbnail).at(n));
    await settle(tester);
    expect(
        tester.widget<StoryArtViewer>(find.byType(StoryArtViewer)).initial, n,);
  }

  testWidgets(
    'collection hides empty art and limits preview to six',
    (tester) async {
      await pump(tester, const CollectionPage(collectionId: 'fixture'),
          empty: true,);
      expect(find.text('剧情美术'), findsNothing);
      await pump(tester, const CollectionPage(collectionId: 'fixture'));
      expect(find.byType(ArtThumbnail), findsNWidgets(6));
      expect(find.text('全部剧情美术'), findsOneWidget);
      await checkInitial(tester, 2);
      expect(
          find.text(
              art.where((a) => a.shot.kind == 'cg').elementAt(2).storyTitle,),
          findsOneWidget,);
      await tester.tap(find.text('回到剧情这里'));
      await settle(tester);
      expect(
          tester
              .widget<StoryReaderPage>(find.byType(StoryReaderPage))
              .highlightStart,
          art[2].shot.at,);
      expect(
          tester.widget<StoryReaderPage>(find.byType(StoryReaderPage)).storyId,
          art[2].storyId,);
    },
    skip: real,
  );
  testWidgets(
    'groups and kind selection keep correct viewer initial page',
    (tester) async {
      await pump(tester, const CollectionArtPage(collectionId: 'fixture'));
      expect(find.text('First story'), findsOneWidget);
      expect(find.text('Second story'), findsOneWidget);
      await checkInitial(tester, 2);
      await tester.tap(find.byTooltip('关闭'));
      await settle(tester);
      await tester.tap(find.text('场景'));
      await settle(tester);
      expect(find.byType(ArtThumbnail), findsNWidgets(2));
      await checkInitial(tester, 1);
      expect(
          tester
              .widget<StoryArtViewer>(find.byType(StoryArtViewer))
              .pages
              .every((p) => p.shot!.kind == 'scene'),
          true,);
    },
    skip: real,
  );
  for (final dark in [false, true]) {
    final mode = dark ? 'dark' : 'light';
    testWidgets(
      'real collection art screenshots $mode',
      (tester) async {
        await pump(tester, CollectionPage(collectionId: collection.id),
            dark: dark,);
        await tester.scrollUntilVisible(find.text('剧情美术'), 450,
            scrollable: find.byType(Scrollable).first,);
        await settle(tester);
        await shoot(tester, 'collection_$mode');
        await pump(tester, CollectionArtPage(collectionId: collection.id),
            dark: dark,);
        await shoot(tester, 'all_cg_$mode');
        await tester.tap(find.byType(ArtThumbnail).first);
        await settle(tester);
        await shoot(tester, 'cg_viewer_$mode');
        await tester.tap(find.byTooltip('关闭'));
        await settle(tester);
        await tester.tap(find.text('场景'));
        await settle(tester);
        await shoot(tester, 'all_scenes_$mode');
      },
      skip: !real,
    );
  }
}

Future<void> settle(WidgetTester tester) async {
  await tester.pumpAndSettle();
  for (var i = 0; i < 12; i++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
  }
}
