import 'dart:io';

import 'package:arklores/core/gamedata/story_art_pack.dart';
import 'package:arklores/core/gamedata/story_art_pack_provider.dart';
import 'package:arklores/core/library/collection_story_art.dart';
import 'package:arklores/core/library/library_provider.dart';
import 'package:arklores/core/library/library_queries.dart';
import 'package:arklores/core/library/story_art.dart';
import 'package:arklores/core/library/story_art_gallery.dart';
import 'package:arklores/features/library/collection_art_page.dart';
import 'package:arklores/features/library/portrait_sheet.dart';
import 'package:arklores/features/library/story_art_gallery_page.dart';
import 'package:arklores/features/library/story_art_viewer.dart';
import 'package:arklores/features/materials/materials_page.dart';
import 'package:arklores/main.dart' show buildAppTheme;
import 'package:arklores/shared/l10n/generated/app_localizations.dart';
import 'package:arklores/shared/providers/theme_provider.dart';
import 'package:arklores/shared/widgets/ef_widgets.dart';
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
import 'collection_art_test.dart' as collection;
import 'library_ui_test.dart' as fixtures;
import 'story_art_viewer_test.dart' show memoryPack;

class _Pack extends StoryArtPack {
  _Pack(this.art, this.portraits) : super('memory');
  final StoryArtPack art;
  final Map<String, PortraitLayers?> portraits;
  @override
  Future<bool> get installed async => true;
  @override
  Future<Map<(String, String), StoryArtInfo>> artInfo(
    Iterable<(String, String)> keys,
  ) =>
      art.artInfo(keys);
  @override
  Future<StoryArtImage?> artImage(String image, String kind) =>
      art.artImage(image, kind);
  @override
  Future<StoryArtTitle?> artTitle(String image) => art.artTitle(image);
  @override
  Future<PortraitLayers?> layers(String sprite) async => portraits[sprite];
}

Future<void> settle(WidgetTester tester) async {
  await collection.settle(tester);
  if (Platform.environment['T7_REAL_DATA'] == 'true') {
    for (var i = 0; i < 40; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),);
      await tester.pumpAndSettle();
    }
  }
}

void main() {
  final real = Platform.environment['T7_REAL_DATA'] == 'true';
  late Directory dir;
  late StoryArtPack pack;
  late StoryArtGallery gallery;
  List<ShelfSummary> realShelves = [];
  List<({String type, int count})> realCodex = [];
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
    dir = await Directory.systemTemp.createTemp('gallery-page');
    final path = real
        ? File('build/story_art/arklores_story_art_zh.db').absolute.path
        : (await createStoryArtPack(dir)).path;
    final source = StoryArtPack(path);
    if (real) {
      final db = await databaseFactoryFfi.openDatabase(
        File('build/gamedata_portraits/arklores_gamedata_zh.db').absolute.path,
        options: OpenDatabaseOptions(readOnly: true),
      );
      gallery = await readStoryArtGallery(db, source);
      realShelves = await shelfSummaries(db);
      realCodex = await codexTypes(db);
      await db.close();
    } else {
      gallery = StoryArtGallery(
        available: true,
        groups: [
          for (final id in ['first', 'second'])
            GalleryArtGroup(id, id, [
              for (var i = 0; i < 3; i++)
                CollectionArtShot(
                    id, id, StoryArtShot(kind: 'cg', image: 'cg', at: i),),
              CollectionArtShot(id, id,
                  const StoryArtShot(kind: 'scene', image: 'scene', at: 8),),
            ]),
        ],
        portraits: const [
          GalleryPortrait('g', 'same', ['Alpha', 'Alias'], 20),
          GalleryPortrait('h', 'whole', ['Beta'], 10),
        ],
      );
    }
    final art = await memoryPack(path, [
      for (final kind in ['cg', 'scene'])
        for (final shot in gallery.shots(kind).take(60))
          (shot.shot.image, kind),
    ]);
    pack = _Pack(art, {
      for (final p in gallery.portraits.take(20))
        p.sprite: await source.layers(p.sprite),
    });
    await source.close();
  });
  tearDownAll(() async => deleteTempDir(dir));

  Future<void> pump(
    WidgetTester tester,
    Widget home, {
    bool dark = false,
    bool empty = false,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        key: UniqueKey(),
        overrides: [
          ...fixtures.overrides(MemoryUserStore()),
          if (real) ...[
            shelfSummariesProvider
                .overrideWith((ref, game) async => realShelves),
            codexTypesProvider.overrideWith((ref, game) async => realCodex),
          ],
          initialThemeProvider
              .overrideWithValue(dark ? AppTheme.ark : AppTheme.endfield),
          storyArtPackProvider.overrideWith((ref) async => pack),
          storyArtGalleryProvider.overrideWith(
            (ref) async => empty ? const StoryArtGallery() : gallery,
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

  testWidgets(
    'segments, whole-kind viewer, initial page, portrait sheet and search',
    (tester) async {
      await pump(tester, const StoryArtGalleryPage());
      for (final label in ['立绘', '背景', 'CG']) {
        expect(find.text(label), findsOneWidget);
      }
      await tester.tap(find.byType(ArtThumbnail).at(2));
      await settle(tester);
      var viewer = tester.widget<StoryArtViewer>(find.byType(StoryArtViewer));
      expect(viewer.initial, 2);
      expect(viewer.pages.length, 6);
      expect(viewer.pages[2].storyId, 'first');
      expect(viewer.pages[2].shot!.number, 3);
      expect(viewer.pages[2].shot!.total, 6);
      expect(find.text('Title'), findsOneWidget);
      expect(viewer.pages.every((p) => p.shot!.kind == 'cg'), isTrue);
      await tester.tap(find.byTooltip('关闭'));
      await settle(tester);
      await tester.tap(find.widgetWithText(AppButton, 'second'));
      await settle(tester);
      expect(tester.getTopLeft(find.text('second').last).dy, lessThan(250));
      await tester.tap(find.text('背景'));
      await settle(tester);
      await tester.tap(find.byType(ArtThumbnail).at(1));
      await settle(tester);
      viewer = tester.widget<StoryArtViewer>(find.byType(StoryArtViewer));
      expect(viewer.initial, 1);
      expect(viewer.pages.length, 2);
      expect(viewer.pages[1].shot!.at, 8);
      await tester.tap(find.byTooltip('关闭'));
      await settle(tester);
      await tester.tap(find.text('立绘'));
      await settle(tester);
      await tester.enterText(find.byType(TextField), 'Alias');
      await settle(tester);
      expect(find.text('Alpha'), findsOneWidget);
      expect(find.text('Beta'), findsNothing);
      await tester.tap(find.text('Alpha'));
      await settle(tester);
      final sheet = tester.widget<PortraitSheet>(find.byType(PortraitSheet));
      expect(sheet.sprite, 'same');
      expect(sheet.listSpeaker, 'Alpha');
      expect(sheet.origin, PortraitOrigin.materials);
      expect(tester.takeException(), isNull);
    },
    skip: real,
  );

  testWidgets('empty category and missing-pack shelf', (tester) async {
    await pump(tester, const StoryArtGalleryPage(), empty: true);
    expect(find.text('没有符合条件的图片'), findsOneWidget);
    await pump(tester, const MaterialsPage(), empty: true);
    expect(find.byKey(const ValueKey('shelf-art-gallery')), findsNothing);
    await pump(tester, const MaterialsPage());
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('shelf-art-gallery')),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('剧情美术'), findsOneWidget);
    await settle(tester);
    await tester.ensureVisible(find.byKey(const ValueKey('shelf-art-gallery')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('shelf-art-gallery')));
    await settle(tester);
    expect(find.byType(StoryArtGalleryPage), findsOneWidget);
  });

  for (final dark in [false, true]) {
    final mode = dark ? 'dark' : 'light';
    testWidgets(
      'real gallery screenshots $mode',
      (tester) async {
        await pump(tester, const MaterialsPage(), dark: dark);
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('shelf-art-gallery')),
          250,
          scrollable: find.byType(Scrollable).first,
        );
        await settle(tester);
        await shoot(tester, 'shelves_$mode');
        await pump(tester, const StoryArtGalleryPage(), dark: dark);
        await shoot(tester, 'cg_$mode');
        await tester.tap(find.byType(ArtThumbnail).first);
        await settle(tester);
        await shoot(tester, 'viewer_$mode');
        await tester.tap(find.byTooltip('关闭'));
        await settle(tester);
        await tester.tap(find.text('背景'));
        await settle(tester);
        await shoot(tester, 'backgrounds_$mode');
        await tester.tap(find.text('立绘'));
        await settle(tester);
        await shoot(tester, 'portraits_$mode');
        expect(tester.takeException(), isNull);
      },
      skip: !real,
    );
  }
}
