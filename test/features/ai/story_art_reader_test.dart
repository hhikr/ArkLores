import 'dart:io';

import 'package:arklores/core/gamedata/story_art_pack.dart';
import 'package:arklores/core/gamedata/story_art_pack_provider.dart';
import 'package:arklores/core/gamedata/story_coverage_models.dart';
import 'package:arklores/core/library/story_art.dart';
import 'package:arklores/features/ai/reader_story_art.dart';
import 'package:arklores/features/ai/story_labels_provider.dart';
import 'package:arklores/features/ai/story_reader_page.dart';
import 'package:arklores/shared/l10n/generated/app_localizations.dart';
import 'package:arklores/shared/providers/settings_provider.dart';
import 'package:arklores/shared/widgets/ef_widgets.dart';
import 'package:arklores/shared/widgets/story_art_composite.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/memory_user_store.dart';
import '../../support/sqlite.dart';
import '../../support/story_art_pack_fixture.dart';
import '../../support/temp_dir.dart';
import '../library/library_ui_test.dart' as fixtures;
import '../library/story_art_viewer_test.dart' as viewer;

void main() {
  late Directory dir;
  late StoryArtPack pack;
  setUpAll(useSqfliteFfi);
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('reader-art');
    final file = await createStoryArtPack(dir);
    pack = await viewer.memoryPack(file.path, [
      ('scene', 'scene'),
      ('cg', 'cg'),
      ('item', 'item'),
    ]);
  });
  tearDown(() async => deleteTempDir(dir));

  testWidgets('art items preserve line count and open the viewer',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final lines = [
      for (var i = 0; i < 30; i++)
        StoryLineEntry(lineIndex: i, content: 'Line $i'),
    ];
    final shots = [
      const StoryArtShot(
          kind: 'scene', image: 'scene', at: 0, number: 1, total: 1,),
      const StoryArtShot(
          kind: 'cg',
          image: 'cg',
          at: 2,
          until: 10,
          segment: 1,
          number: 1,
          total: 1,),
      const StoryArtShot(kind: 'cg', image: 'cg', at: 3, segment: 1, until:10, number:1,total:1, layers:[StoryArtLayer(image:'item')]),
    ];
    final info = {
      ('scene', 'background'): const StoryArtInfo(4, 4, 'background', false),
      ('cg', 'cg'): const StoryArtInfo(4, 4, 'illustration', false),
      ('item', 'item'): const StoryArtInfo(4, 4, 'item', false),
    };
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...fixtures.overrides(MemoryUserStore()),
          storyArtPackProvider.overrideWith((ref) async => pack),
          storyFullLinesProvider.overrideWith((ref, id) async => lines),
          readerStoryArtProvider.overrideWith(
            (ref, key) async => ReaderStoryArt(shots, info, {
              'cg': const StoryArtTitle('Title', 'Description', 'group'),
            }),
          ),
        ],
        child: const MaterialApp(
          locale: Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: StoryReaderPage(storyId: 'fixture.txt'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('story-art-scene-1')), findsOneWidget);
    expect(find.text('1 / 30'), findsOneWidget);
    expect(find.text('CG 01 / 01'), findsNWidgets(2));
    await tester.tap(find.byKey(const ValueKey('story-art-scene-1')));
    await tester.pumpAndSettle();
    expect(find.text('回到剧情这里'), findsOneWidget);
    await tester.tap(find.text('回到剧情这里'));
    await tester.pumpAndSettle();
    expect(find.text('Line 0'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('CG frames stay lazy and empty segments close independently',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final lines = [
      for (var i = 0; i < 58; i++)
        StoryLineEntry(lineIndex: i, content: 'Line $i'),
    ];
    const shots = [
      StoryArtShot(
          kind: 'cg',
          image: 'cg',
          at: 0,
          until: 0,
          segment: 1,
          number: 1,
          total: 1,),
      StoryArtShot(
          kind: 'cg',
          image: 'cg',
          at: 0,
          until: 58,
          segment: 2,
          number: 1,
          total: 1,),
    ];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...fixtures.overrides(MemoryUserStore()),
          storyArtPackProvider.overrideWith((ref) async => pack),
          storyFullLinesProvider.overrideWith((ref, id) async => lines),
          readerStoryArtProvider.overrideWith(
            (ref, key) async => ReaderStoryArt(
              shots,
              {
                ('cg', 'cg'): const StoryArtInfo(4, 4, 'illustration', false),
              },
              {},
            ),
          ),
        ],
        child: const MaterialApp(
          locale: Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: StoryReaderPage(storyId: 'fixture.txt'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('story-art-cg-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('story-art-cg-1')), findsOneWidget);
    final frames = tester.widgetList<CgFrameSlice>(find.byType(CgFrameSlice));
    expect(frames.where((f) => f.end), hasLength(1));
    expect(frames.where((f) => f.top), hasLength(2));
    expect(frames.length, lessThan(58));
    expect(find.text('Line 57'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  List<StoryLineEntry> numbered(int n) => [
        for (var i = 0; i < n; i++)
          StoryLineEntry(lineIndex: i, content: 'Line $i'),
      ];
  const cgInfo = {
    ('cg', 'cg'): StoryArtInfo(16, 4, 'illustration', false),
    ('scene', 'background'): StoryArtInfo(4, 4, 'background', false),
  };

  Future<void> open(
    WidgetTester tester, {
    required List<StoryLineEntry> lines,
    ReaderStoryArt? art,
    StoryArtMode mode = StoryArtMode.images,
    int? highlightStart,
    int? highlightEnd,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...fixtures.overrides(MemoryUserStore()),
          initialStoryArtModeProvider.overrideWithValue(mode),
          storyArtPackProvider.overrideWith((ref) async => pack),
          storyFullLinesProvider.overrideWith((ref, id) async => lines),
          readerStoryArtProvider.overrideWith((ref, key) async => art),
        ],
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: StoryReaderPage(
            storyId: 'fixture.txt',
            highlightStart: highlightStart,
            highlightEnd: highlightEnd,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 400));
  }

  bool inFrame(WidgetTester tester, String text) => find
      .ancestor(of: find.text(text), matching: find.byType(CgFrameSlice))
      .evaluate()
      .isNotEmpty;

  testWidgets('without art the reader has no art items', (tester) async {
    await open(tester, lines: numbered(30));
    expect(find.byType(CgFrameSlice), findsNothing);
    expect(find.byKey(const ValueKey('story-art-scene-1')), findsNothing);
    expect(find.text('1 / 30'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a CG segment: top, lines, change, end; an empty one closes',
      (tester) async {
    await open(
      tester,
      lines: numbered(30),
      art: const ReaderStoryArt(
        [
          StoryArtShot(
              kind: 'cg', image: 'cg', at: 2, until: 8, segment: 1,
              number: 1, total: 2,),
          StoryArtShot(
              kind: 'cg', image: 'cg', at: 5, until: 8, segment: 1,
              number: 2, total: 2,),
          StoryArtShot(
              kind: 'cg', image: 'cg', at: 10, until: 10, segment: 2,
              number: 1, total: 2,),
        ],
        cgInfo,
        {},
      ),
    );
    final first = tester.widget<CgFrameSlice>(
        find.byKey(const ValueKey('story-art-cg-0')),);
    final change = tester.widget<CgFrameSlice>(
        find.byKey(const ValueKey('story-art-cg-1')),);
    final empty = tester.widget<CgFrameSlice>(
        find.byKey(const ValueKey('story-art-cg-2')),);
    expect(first.top, isTrue);
    expect(change.top, isFalse, reason: 'a change inside the frame');
    expect(empty.top, isTrue);
    expect(
      tester
          .widgetList<CgFrameSlice>(
            find.byType(CgFrameSlice, skipOffstage: false),
          )
          .where((f) => f.end),
      hasLength(2),
    );
    expect(inFrame(tester, 'Line 1'), isFalse);
    expect(inFrame(tester, 'Line 2'), isTrue);
    expect(inFrame(tester, 'Line 7'), isTrue);
    expect(inFrame(tester, 'Line 8'), isFalse);
    // Top to bottom: the CG's top, its lines, the change, the end.
    double y(Finder f) => tester.getTopLeft(f).dy;
    expect(y(find.byKey(const ValueKey('story-art-cg-0'))),
        lessThan(y(find.text('Line 2'))),);
    expect(y(find.text('Line 4')),
        lessThan(y(find.byKey(const ValueKey('story-art-cg-1')))),);
    expect(y(find.byKey(const ValueKey('story-art-cg-1'))),
        lessThan(y(find.text('Line 5'))),);
    expect(tester.takeException(), isNull);
  });

  testWidgets('scenes joined on one line: one label, each picture opens',
      (tester) async {
    StoryArtShot scene(int n, {bool joined = false}) => StoryArtShot(
          kind: 'scene',
          image: 'scene',
          at: n == 1 ? 0 : 3,
          number: n,
          total: 5,
          joined: joined,
        );
    await open(
      tester,
      lines: numbered(30),
      art: ReaderStoryArt(
        [
          scene(1),
          scene(2),
          scene(3, joined: true),
          scene(4, joined: true),
          scene(5, joined: true),
        ],
        cgInfo,
        {},
      ),
    );
    expect(find.byKey(const ValueKey('story-art-scenes-2-5')), findsOneWidget);
    expect(find.text('场景 02–05'), findsOneWidget);
    expect(find.byKey(const ValueKey('story-art-scene-1')), findsOneWidget);
    double top(int n) =>
        tester.getTopLeft(find.byKey(ValueKey('story-art-scene-$n'))).dy;
    double width(int n) =>
        tester.getSize(find.byKey(ValueKey('story-art-scene-$n'))).width;
    expect(top(2), top(4), reason: 'three a row');
    expect(top(5), greaterThan(top(2)));
    expect(width(5), width(2), reason: 'the same width in a short row');
    await tester.tap(find.byKey(const ValueKey('story-art-scene-3')));
    await tester.pumpAndSettle();
    expect(find.text('场景 03 / 05'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a cited block breaks at the edges of a CG', (tester) async {
    await open(
      tester,
      lines: numbered(30),
      highlightStart: 0,
      highlightEnd: 12,
      art: const ReaderStoryArt(
        [
          StoryArtShot(
              kind: 'cg', image: 'cg', at: 3, until: 8, segment: 1,
              number: 1, total: 1,),
        ],
        cgInfo,
        {},
      ),
    );
    Element block(String text) => find
        .ancestor(of: find.text(text), matching: find.byType(AnimatedBuilder))
        .evaluate()
        .first;
    expect(block('Line 1'), same(block('Line 2')));
    expect(block('Line 4'), same(block('Line 5')), reason: 'one block in it');
    expect(block('Line 2'), isNot(same(block('Line 4'))));
    expect(block('Line 7'), isNot(same(block('Line 9'))));
    expect(tester.takeException(), isNull);
  });

  testWidgets('art leaves the count and the cited line where they were',
      (tester) async {
    await open(tester, lines: numbered(60), highlightStart: 40, highlightEnd: 40);
    final target = find.byKey(const ValueKey('story-line-target-40'));
    final plain = tester.getTopLeft(target).dy;
    final count = tester
        .widget<Text>(find.byKey(const ValueKey('story-reader-progress')))
        .data;
    await open(
      tester,
      lines: numbered(60),
      highlightStart: 40,
      highlightEnd: 40,
      art: const ReaderStoryArt(
        [
          StoryArtShot(
              kind: 'scene', image: 'scene', at: 0, number: 1, total: 2,),
          StoryArtShot(
              kind: 'cg', image: 'cg', at: 30, until: 39, segment: 1,
              number: 1, total: 1,),
          StoryArtShot(
              kind: 'scene', image: 'scene', at: 39, number: 2, total: 2,),
        ],
        cgInfo,
        {},
      ),
    );
    expect(tester.getTopLeft(target).dy, plain);
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('story-reader-progress')))
          .data,
      count,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('the panel names the picture over the text and opens it',
      (tester) async {
    await open(
      tester,
      lines: numbered(80),
      art: const ReaderStoryArt(
        [
          StoryArtShot(
              kind: 'scene', image: 'scene', at: 40, number: 1, total: 1,),
        ],
        cgInfo,
        {},
      ),
    );
    await tester.tap(find.byKey(const ValueKey('page-title')));
    await tester.pumpAndSettle();
    expect(find.text('还没有出现场景'), findsOneWidget);
    final slider = find.byKey(const ValueKey('story-reader-slider'));
    final track = tester.getRect(slider);
    await tester.tapAt(Offset(track.right - 14, track.center.dy));
    await tester.pumpAndSettle();
    expect(find.text('场景 01 / 01'), findsOneWidget);
    expect(find.text('还没有出现场景'), findsNothing);
    await tester.tapAt(Offset(track.left + 14, track.center.dy));
    await tester.pumpAndSettle();
    expect(find.text('还没有出现场景'), findsOneWidget, reason: 'follows back');
    await tester.tapAt(Offset(track.right - 14, track.center.dy));
    await tester.pumpAndSettle();
    await tester.tap(find.text('场景 01 / 01'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('回到剧情这里'));
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text('Line 40').first).dy,
      lessThan(60),
      reason: 'the first line after the scene sits under the status bar',
    );
    expect(tester.takeException(), isNull);
  });
  const markedArt = ReaderStoryArt(
      [
        StoryArtShot(kind: 'scene', image: 'scene', at: 0, number: 1, total: 1),
        StoryArtShot(
            kind: 'cg',
            image: 'cg',
            at: 1,
            until: 8,
            segment: 1,
            number: 1,
            total: 1,
            layers: [StoryArtLayer(image: 'item')],),
      ],
      cgInfo,
      {'cg': StoryArtTitle('Title', 'Description', 'group')},);

  testWidgets('markers retain labels and titles without pictures or art taps',
      (tester) async {
    await open(tester,
        lines: numbered(30), art: markedArt, mode: StoryArtMode.marks,);
    expect(find.text('场景 01'), findsOneWidget);
    expect(find.text('CG'), findsOneWidget);
    expect(find.text('特写'), findsOneWidget);
    expect(find.text('Title'), findsOneWidget);
    expect(find.text('Description'), findsOneWidget);
    expect(find.byType(StoryArtComposite), findsNothing);
    expect(find.byType(Image), findsNothing);
    final cg = find.byKey(const ValueKey('story-art-mark-1'));
    expect(tester.getSize(cg).height, 24);
    expect(tester.widget(cg), isA<Hatch>());
    await tester.tap(find.text('CG'));
    await tester.pumpAndSettle();
    expect(find.text('回到剧情这里'), findsNothing);
    await tester.tap(find.text('CG'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('page-title')));
    await tester.pumpAndSettle();
    final current = find.byKey(const ValueKey('story-art-current'));
    expect(current, findsOneWidget);
    expect(tester.getSize(current).height, 48);
    expect(find.descendant(of: current, matching: find.byType(Icon)),
        findsNothing,);
    expect(find.ancestor(of: current, matching: find.byType(PressRow)),
        findsNothing,);
    expect(find.byType(StoryArtComposite), findsNothing);
    expect(find.byType(Image), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a close-up change is only a field label in markers mode',
      (tester) async {
    await open(
      tester,
      lines: numbered(30),
      mode: StoryArtMode.marks,
      art: const ReaderStoryArt([
        StoryArtShot(kind: 'scene', image: 'scene', at: 0, number: 1, total: 1),
        StoryArtShot(kind: 'scene', image: 'scene', at: 1, number: 1, total: 1,
            layers: [StoryArtLayer(image: 'item')],),
        StoryArtShot(kind: 'scene', image: 'scene', at: 2, number: 1, total: 1),
      ], cgInfo, {},),
    );
    expect(find.text('场景 01'), findsOneWidget);
    expect(find.text('特写'), findsOneWidget);
    expect(find.byType(StoryArtComposite), findsNothing);
    expect(find.byType(Image), findsNothing);
    expect(find.ancestor(of: find.text('特写'), matching: find.byType(PressRow)),
        findsNothing,);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a close-up without a background has no scene zero marker',
      (tester) async {
    await open(
      tester,
      lines: numbered(30),
      mode: StoryArtMode.marks,
      art: const ReaderStoryArt([
        StoryArtShot(kind: 'scene', image: '', at: 0, number: 0, total: 0,
            layers: [StoryArtLayer(image: 'item')],),
      ], cgInfo, {},),
    );
    expect(find.text('特写'), findsOneWidget);
    expect(find.text('场景 00'), findsNothing);
    expect(find.byType(StoryArtComposite), findsNothing);
    expect(find.byType(Image), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('off skips all inline art', (tester) async {
    await open(tester,
        lines: numbered(30), art: markedArt, mode: StoryArtMode.off,);
    expect(find.byType(CgFrameSlice), findsNothing);
    expect(find.text('场景 01'), findsNothing);
    expect(find.text('特写'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('page-title')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('story-art-current')), findsNothing);
    expect(find.byType(StoryArtComposite), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('changing display mode keeps the reading line and its position',
      (tester) async {
    await open(tester,
        lines: numbered(80),
        art: markedArt,
        highlightStart: 40,
        highlightEnd: 40,);
    final target = find.byKey(const ValueKey('story-line-target-40'));
    final y = tester.getTopLeft(target).dy;
    final progress = tester
        .widget<Text>(
          find.byKey(const ValueKey('story-reader-progress')),
        )
        .data;
    final container =
        ProviderScope.containerOf(tester.element(find.byType(StoryReaderPage)));
    for (final mode in [
      StoryArtMode.marks,
      StoryArtMode.off,
      StoryArtMode.images
    ,]) {
      container.read(storyArtModeProvider.notifier).state = mode;
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(target).dy, closeTo(y, 1));
      expect(
          tester
              .widget<Text>(
                find.byKey(const ValueKey('story-reader-progress')),
              )
              .data,
          progress,);
    }
    expect(tester.takeException(), isNull);
  });

}
