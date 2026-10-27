import 'dart:io';

import 'package:arklores/core/gamedata/story_art_pack.dart';
import 'package:arklores/core/gamedata/story_art_pack_provider.dart';
import 'package:arklores/core/library/story_art.dart';
import 'package:arklores/features/library/story_art_viewer.dart';
import 'package:arklores/main.dart' show buildAppTheme;
import 'package:arklores/shared/l10n/generated/app_localizations.dart';
import 'package:arklores/shared/providers/theme_provider.dart';
import 'package:arklores/shared/theme/endfield_theme_tokens.dart';
import 'package:arklores/shared/widgets/ef_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/screenshot.dart';
import '../../support/sqlite.dart';
import '../../support/story_art_pack_fixture.dart';
import '../../support/temp_dir.dart';

class _MemoryPack extends StoryArtPack {
  _MemoryPack(this.images, this.titles) : super('memory');
  final Map<(String, String), StoryArtImage?> images;
  final Map<String, StoryArtTitle?> titles;
  @override
  Future<StoryArtImage?> artImage(String id, String kind) async =>
      images[(id, kind)];
  @override
  Future<Map<(String, String), StoryArtInfo>> artInfo(
    Iterable<(String, String)> keys,
  ) async =>
      {
        for (final key in keys)
          if (images[key] case final image?)
            key: StoryArtInfo(
              image.width,
              image.height,
              image.category,
              image.solid,
            ),
      };
  @override
  Future<StoryArtTitle?> artTitle(String id) async => titles[id];
  @override
  Future<void> close() async {}
}

Future<StoryArtPack> memoryPack(
  String path,
  List<(String, String)> keys,
) async {
  final source = StoryArtPack(path);
  final images = <(String, String), StoryArtImage?>{};
  final titles = <String, StoryArtTitle?>{};
  for (final key in keys) {
    images[key] = await source.artImage(key.$1, key.$2);
    titles[key.$1] = await source.artTitle(key.$1);
  }
  await source.close();
  return _MemoryPack(images, titles);
}

void main() {
  late Directory dir;
  late StoryArtPack pack;
  setUpAll(() async {
    useSqfliteFfi();
    for (final font
        in {'Saira': 'Saira.ttf', 'NotoSansSC': 'NotoSansSC.ttf'}.entries) {
      await (FontLoader(font.key)
            ..addFont(rootBundle.load('assets/fonts/${font.value}')))
          .load();
    }
    await (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
        .load();
  });
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('art-viewer');
    pack = await memoryPack(
      (await createStoryArtPack(dir)).path,
      [('scene', 'scene'), ('cg', 'cg'), ('item', 'item')],
    );
  });
  tearDown(() async {
    await deleteTempDir(dir);
  });
  const shots = [
    StoryArtShot(kind: 'scene', image: 'scene', at: 3, number: 1, total: 1),
    StoryArtShot(kind: 'cg', image: 'cg', at: 7, number: 1, total: 1),
    StoryArtShot(
        kind: 'cg',
        image: 'cg',
        at: 9,
        number: 1,
        total: 1,
        layers: [StoryArtLayer(image: 'item')],),
  ];
  Future<void> start(
    WidgetTester tester,
    List<StoryArtShot> items, {
    int initial = 0,
    void Function(int)? onJump,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          initialThemeProvider.overrideWithValue(AppTheme.endfield),
          storyArtPackProvider.overrideWith((ref) async => pack),
        ],
        child: Shot(
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: buildAppTheme(EndfieldThemeTokens()).copyWith(
              textTheme: buildAppTheme(EndfieldThemeTokens())
                  .textTheme
                  .apply(fontFamily: 'Saira'),
            ),
            locale: const Locale('zh'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: AppButton(
                    'open',
                    onPressed: () => openArtViewer(
                      context,
                      pages: [
                        for (final shot in items)
                          ArtViewerPage.story(
                              storyId: 's',
                              shot: shot,
                              onJump: onJump ?? (_) {},),
                      ],
                      initial: initial,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('page, bars, jump and fixed dark theme', (tester) async {
    int? jumped;
    await start(tester, shots, onJump: (n) => jumped = n);
    expect(find.text('场景 01 / 01'), findsOneWidget);
    final scaffold = tester.widget<Scaffold>(
      find
          .descendant(
            of: find.byType(StoryArtViewer),
            matching: find.byType(Scaffold),
          )
          .first,
    );
    expect(scaffold.backgroundColor, const Color(0xff191919));
    await tester.tapAt(const Offset(195, 400));
    await tester.pumpAndSettle();
    expect(
      tester.widget<AnimatedSlide>(find.byType(AnimatedSlide).first).offset.dy,
      -1,
    );
    await tester.tapAt(const Offset(195, 400));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(PageView), const Offset(-300, 0));
    await tester.pumpAndSettle();
    expect(find.text('CG 01 / 01'), findsOneWidget);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('回到剧情这里'));
    await tester.pumpAndSettle();
    expect(jumped, 7);
    expect(find.byType(StoryArtViewer), findsNothing);
    await tester.runAsync(() => pack.close());
  });
  testWidgets('zoom disables page scrolling and back closes', (tester) async {
    await start(tester, shots);
    final viewer =
        tester.widget<InteractiveViewer>(find.byType(InteractiveViewer).first);
    viewer.transformationController!.value = Matrix4.diagonal3Values(2, 2, 1);
    await tester.pump();
    expect(
      tester.widget<PageView>(find.byType(PageView)).physics,
      isA<NeverScrollableScrollPhysics>(),
    );
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(StoryArtViewer), findsNothing);
    await tester.runAsync(() => pack.close());
  });
  if (shotDir != null) {
    final real = File('build/story_art/arklores_story_art_zh.db').absolute.path;
    for (final entry in [
      (
        'scene',
        StoryArtShot(
          kind: 'scene',
          image: '21_g1_interrogat_room',
          at: 0,
          number: 1,
          total: 1,
        )
      ),
      (
        'cg',
        StoryArtShot(
          kind: 'cg',
          image: '071_mini01',
          at: 0,
          number: 1,
          total: 1,
        )
      ),
      (
        'tall',
        StoryArtShot(kind: 'cg', image: 'ac6_9', at: 0, number: 1, total: 1)
      ),
      (
        'item',
        StoryArtShot(
            kind: 'cg',
            image: '53_i04',
            at: 0,
            layers: [StoryArtLayer(image: 'cgitem_41_i12_1')],)
      ),
    ]) {
      testWidgets('real screenshot ${entry.$1}', (tester) async {
        await pack.close();
        pack = await tester.runAsync(
              () => memoryPack(real, [(entry.$2.image, entry.$2.kind)]),
            ) ??
            (throw StateError('missing pack'));
        await start(tester, [entry.$2]);
        await tester
            .runAsync(() => Future<void>.delayed(const Duration(seconds: 1)));
        await tester.pumpAndSettle();
        await shoot(tester, 'viewer_${entry.$1}', pixelRatio: 1);
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(() => pack.close());
      });
    }
  }
}
