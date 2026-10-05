import 'package:arklores/core/gamedata/story_coverage_models.dart';
import 'package:arklores/core/userdata/library_ref.dart';
import 'package:arklores/core/userdata/user_data_provider.dart';
import 'package:arklores/features/ai/reading_history_page.dart';
import 'package:arklores/features/ai/story_labels_provider.dart';
import 'package:arklores/features/ai/story_reader_page.dart';
import 'package:arklores/shared/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/memory_user_store.dart';

const _story = 'activities/act_fixture/level_fixture_c5.txt';

List<StoryLineEntry> _lines({int shift = 0, bool rewritten = false}) => [
      for (var i = 0; i < 40 + shift; i++)
        StoryLineEntry(
          lineIndex: i,
          speaker: null,
          content: i < shift
              ? '新增$i'
              : rewritten
                  ? '改写$i'
                  : '第${i - shift}句',
        ),
    ];

void main() {
  late MemoryUserStore store;

  setUp(() => store = MemoryUserStore());

  Future<void> settle(WidgetTester tester) async {
    // The reader scrolls to its target over a few frames (the list is lazy).
    await tester.pump();
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
  }

  // A fresh scope per call: the providers cache their first result.
  Widget app(Widget home, List<StoryLineEntry> lines) => ProviderScope(
        key: UniqueKey(),
        overrides: [
          userDataStoreProvider.overrideWith((ref) async => store),
          storyFullLinesProvider.overrideWith((ref, id) async => lines),
          storyCatalogEntryProvider.overrideWith((ref, id) async => null),
        ],
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: home,
        ),
      );

  void tall(WidgetTester tester) {
    tester.view.physicalSize = const Size(640, 1280);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets('opening a story writes the history; the list reopens it',
      (tester) async {
    tall(tester);
    await tester.pumpWidget(app(
      const StoryReaderPage(
        storyId: _story,
        highlightStart: 20,
        highlightEnd: 21,
      ),
      _lines(),
    ),);
    await settle(tester);

    final saved = await store.recent();
    expect(saved, hasLength(1));
    expect(saved.single.ref, const LibraryRef.story(_story).toString());
    // The anchor follows the reader: the first line on screen, which is a few
    // above the cited block.
    final at = saved.single.lineIndex;
    expect(at, inInclusiveRange(10, 20));
    expect(saved.single.snippet, '第$at句');
    expect(saved.single.title, isNotEmpty);

    // The history page lists it; the story gained 3 lines in front meanwhile.
    await tester.pumpWidget(app(const ReadingHistoryPage(), _lines(shift: 3)));
    await settle(tester);
    expect(find.text(saved.single.title), findsOneWidget);
    expect(find.textContaining('第 ${at + 1} 行'), findsOneWidget);
    expect(find.textContaining('第$at句'), findsOneWidget);

    await tester.tap(find.byKey(ValueKey('reading-tile-${saved.single.ref}')));
    await settle(tester);
    expect(find.byType(StoryReaderPage), findsOneWidget);
    // Found again by its text: the line is now three further down.
    expect(find.byKey(ValueKey('story-line-resume-${at + 3}')), findsOneWidget);
    expect(find.byKey(ValueKey('story-line-resume-$at')), findsNothing);
    expect(find.byKey(ValueKey('story-line-target-${at + 3}')), findsNothing);
    expect(find.text('原文有变动，已定位到大致位置'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a rewritten story opens at the approximate place, with a note',
      (tester) async {
    tall(tester);
    await store.recordOpen(
      const LibraryRef.story(_story),
      title: '故事 · 章',
      lineIndex: 12,
      snippet: '已经不存在的句子',
    );
    await tester.pumpWidget(app(const ReadingHistoryPage(), _lines(rewritten: true)));
    await settle(tester);
    await tester.tap(find.text('故事 · 章'));
    await settle(tester);
    expect(find.byKey(const ValueKey('story-line-resume-12')), findsOneWidget);
    // The note is in the header, above the line the reader was taken to.
    await tester.drag(find.byKey(const ValueKey('story-reader-scroll')), const Offset(0, 3000));
    await settle(tester);
    expect(find.text('原文有变动，已定位到大致位置'), findsOneWidget);
  });

  testWidgets('empty history, removing and clearing', (tester) async {
    tall(tester);
    await tester.pumpWidget(app(const ReadingHistoryPage(), const []));
    await settle(tester);
    expect(find.textContaining('还没有阅读记录'), findsOneWidget);
    expect(find.byKey(const ValueKey('reading-history-clear')), findsNothing);

    for (final id in ['a', 'b']) {
      await store.recordOpen(
        LibraryRef.story('s/$id.txt'),
        title: '故事$id',
        lineIndex: 0,
        snippet: '',
      );
    }
    await tester.pumpWidget(app(const ReadingHistoryPage(), const []));
    await settle(tester);
    expect(find.text('故事a'), findsOneWidget);
    expect(find.text('故事b'), findsOneWidget);

    await tester.drag(find.text('故事a'), const Offset(-600, 0));
    await settle(tester);
    expect(find.text('故事a'), findsNothing);
    expect((await store.recent()), hasLength(1));

    await tester.tap(find.byKey(const ValueKey('reading-history-clear')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('reading-history-clear-confirm')));
    await settle(tester);
    expect(find.textContaining('还没有阅读记录'), findsOneWidget);
    expect((await store.recent()), isEmpty);
  });

  testWidgets('a long history is shown a page at a time', (tester) async {
    tall(tester);
    for (var i = 0; i < 20; i++) {
      await store.recordOpen(
        LibraryRef.story('s/$i.txt'),
        title: '故事$i',
        lineIndex: 0,
        snippet: '',
      );
    }
    await tester.pumpWidget(app(const ReadingHistoryPage(), const []));
    await settle(tester);
    // Newest first: 19 … 5 on the first page, 4 … 0 on the second.
    expect(find.text('故事19'), findsOneWidget);
    expect(find.text('故事4'), findsNothing);
    await tester.scrollUntilVisible(find.text('第 1 / 2 页'), 300);
    await tester.tap(find.byKey(const ValueKey('reading-history-next')));
    await settle(tester);
    expect(find.text('故事4'), findsOneWidget);
    expect(find.text('故事19'), findsNothing);
    expect(find.text('第 2 / 2 页'), findsOneWidget);
  });

  testWidgets('narration is italic only between spoken lines; the Doctor '
      'placeholder shows the reader\'s form of address', (tester) async {
    tall(tester);
    TextStyle? styleOf(String text) => tester
        .widget<Text>(find.text(text, findRichText: false).first)
        .style;
    final spoken = [
      const StoryLineEntry(lineIndex: 0, speaker: null, content: '旁白一句。'),
      const StoryLineEntry(lineIndex: 1, speaker: '乙', content: '你好，{@nickname}。'),
    ];
    await tester.pumpWidget(app(const StoryReaderPage(storyId: _story), spoken));
    await settle(tester);
    expect(styleOf('旁白一句。')?.fontStyle, FontStyle.italic);
    expect(styleOf('你好，博士。')?.fontFamily, readingFontFamily);

    // All narration (a month squad's story): plain.
    await tester.pumpWidget(app(
      const StoryReaderPage(storyId: _story),
      const [
        StoryLineEntry(lineIndex: 0, speaker: null, content: '全是叙述。'),
      ],
    ),);
    await settle(tester);
    expect(styleOf('全是叙述。')?.fontStyle, FontStyle.normal);
  });

  testWidgets('a very long story opens, jumps and saves like a short one',
      (tester) async {
    tall(tester);
    final long = [
      for (var i = 0; i < 20000; i++)
        StoryLineEntry(
          lineIndex: i,
          speaker: i % 3 == 0 ? '甲' : null,
          content: '第$i句，${'很长的一句话' * (i % 7)}',
        ),
    ];
    await tester.pumpWidget(app(
      const StoryReaderPage(storyId: _story, resumeLine: 15000, snippet: '第15000句'),
      long,
    ),);
    await settle(tester);
    // Only what is near the screen is built, far down the text.
    expect(find.byType(Text).evaluate().length, lessThan(200));
    expect(find.byKey(const ValueKey('story-line-resume-15000')), findsOneWidget);
    final saved = (await store.recent()).single;
    expect(saved.lineIndex, inInclusiveRange(14990, 15000));
    expect(saved.totalLines, 20000);

    // Scrolling on keeps the position saved.
    await tester.drag(find.byKey(const ValueKey('story-reader-scroll')), const Offset(0, -3000));
    await settle(tester);
    expect((await store.recent()).single.lineIndex, greaterThan(15000));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a cited block deep in a long story is shown, and the jump button '
      'brings it back', (tester) async {
    tall(tester);
    final long = [
      for (var i = 0; i < 20000; i++)
        StoryLineEntry(lineIndex: i, speaker: null, content: '第$i句。'),
    ];
    await tester.pumpWidget(app(
      const StoryReaderPage(
        storyId: _story,
        highlightStart: 12000,
        highlightEnd: 12001,
      ),
      long,
    ),);
    await settle(tester);
    expect(find.byKey(const ValueKey('story-line-target-12000')), findsOneWidget);
    expect(find.byKey(const ValueKey('story-line-target-12001')), findsOneWidget);

    for (var i = 0; i < 8; i++) {
      await tester.drag(
        find.byKey(const ValueKey('story-reader-scroll')),
        const Offset(0, -2000),
      );
    }
    await settle(tester);
    expect(find.byKey(const ValueKey('story-line-target-12000')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('story-reader-jump')));
    await settle(tester);
    expect(find.byKey(const ValueKey('story-line-target-12000')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}