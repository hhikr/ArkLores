import 'package:arklores/core/gamedata/story_coverage_models.dart';
import 'package:arklores/core/library/library_provider.dart'
    show attachedStoriesProvider, storyHostProvider;
import 'package:arklores/core/library/library_queries.dart' show LibraryEntry;
import 'package:arklores/core/userdata/library_ref.dart';
import 'package:arklores/core/userdata/user_data_provider.dart';
import 'package:arklores/core/userdata/user_data_store.dart';
import 'package:arklores/features/ai/reading_history_page.dart';
import 'package:arklores/features/ai/story_labels_provider.dart';
import 'package:arklores/features/ai/story_reader_page.dart';
import 'package:arklores/features/library/library_widgets.dart' show openStory;
import 'package:arklores/shared/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../support/memory_user_store.dart';

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
          storyHostProvider.overrideWith((ref, id) async => null),
          attachedStoriesProvider.overrideWith((ref, id) async => const []),
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

  testWidgets('a long history is paged: page boxes above and below, jump, '
      'first and last', (tester) async {
    // Tall enough that the whole page, both pagers included, is built.
    tester.view.physicalSize = const Size(800, 6000);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (var i = 0; i < 100; i++) {
      await store.recordOpen(
        LibraryRef.story('s/$i.txt'),
        title: '故事$i',
        lineIndex: 0,
        snippet: '',
      );
    }
    await tester.pumpWidget(app(const ReadingHistoryPage(), const []));
    await settle(tester);
    // Newest first: 99 … 85 on the first page; 7 pages of 15.
    expect(find.text('故事99'), findsOneWidget);
    expect(find.text('故事84'), findsNothing);
    expect(find.byKey(const ValueKey('reading-history-pager-top')), findsOneWidget);
    expect(find.byKey(const ValueKey('reading-history-pager-bottom')), findsOneWidget);
    expect(find.text('第 1 / 7 页'), findsNWidgets(2));

    // A page box (the one in the top pager) opens that page.
    await tester.tap(find.byKey(const ValueKey('reading-history-page-box-3')).first);
    await settle(tester);
    expect(find.text('故事69'), findsOneWidget); // 100 - 30 - 1
    expect(find.text('故事99'), findsNothing);
    expect(find.text('第 3 / 7 页'), findsNWidgets(2));

    // The last page holds the oldest ten (100 = 6 × 15 + 10).
    await tester.tap(find.byKey(const ValueKey('reading-history-last')).first);
    await settle(tester);
    expect(find.text('故事0'), findsOneWidget);
    expect(find.text('第 7 / 7 页'), findsNWidgets(2));

    // The label asks for a page number.
    await tester.tap(find.byKey(const ValueKey('reading-history-jump')).first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('reading-history-jump-field')), '2');
    await tester.tap(find.byKey(const ValueKey('reading-history-jump-go')));
    await settle(tester);
    expect(find.text('第 2 / 7 页'), findsNWidgets(2));
    expect(find.text('故事84'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('reading-history-first')).first);
    await settle(tester);
    expect(find.text('故事99'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('the end counts after it stayed in view; leaving at once does '
      'not', (tester) async {
    tall(tester);
    final short = [
      for (var i = 0; i < 3; i++)
        StoryLineEntry(lineIndex: i, speaker: null, content: '短$i'),
    ];
    await tester.pumpWidget(app(const StoryReaderPage(storyId: _story), short));
    await settle(tester);
    // The whole text is in view, but only for a moment so far.
    expect((await store.recent()).single.completedCount, 0);
    await tester.pump(readingEndDwell + const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    var e = (await store.recent()).single;
    expect((e.completedCount, e.finished), (1, true));

    // Opened again from the list, a finished story starts at the top: a new
    // pass, and the read count stays.
    await tester.pumpWidget(app(const SizedBox(), short));
    await tester.pumpWidget(app(
      Builder(
        builder: (context) => TextButton(
          onPressed: () => openStory(context, _story, resume: e),
          child: const Text('open'),
        ),
      ),
      short,
    ),);
    await tester.tap(find.text('open'));
    await settle(tester);
    e = (await store.recent()).single;
    expect((e.completedCount, e.finished), (1, false));
  });

  testWidgets('read counts show as a check, with the number from the second '
      'time on, never wider than a small badge', (tester) async {
    tall(tester);
    var i = 0;
    for (final times in [1, 2, 37, 1500]) {
      await store.recordOpen(
        LibraryRef.story('s/${i++}.txt'),
        title: '故事$times',
        lineIndex: 0,
        snippet: '',
        totalLines: 100,
      );
      await store.updateProgress(
        LibraryRef.story('s/${i - 1}.txt'),
        lineIndex: 0,
        snippet: '',
        totalLines: 100,
        reached: 99,
        atEnd: true,
      );
      store.rows['story:s/${i - 1}.txt'] = ReadingEntry(
        ref: 'story:s/${i - 1}.txt',
        title: '故事$times',
        lineIndex: 0,
        snippet: '',
        openedAt: DateTime(2026, 10, 5, 12, i),
        openCount: 1,
        totalLines: 100,
        furthest: 99,
        completedCount: times,
        passDone: true,
      );
    }
    await tester.pumpWidget(app(const ReadingHistoryPage(), const []));
    await settle(tester);
    expect(find.text('×2'), findsOneWidget);
    expect(find.text('×37'), findsOneWidget);
    expect(find.text('×999+'), findsOneWidget);
    expect(find.text('×1'), findsNothing);
    // The list says it in words, with the whole number.
    expect(find.textContaining('读过 1500 次'), findsOneWidget);
    expect(find.textContaining('读过 1 次'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('dialogue attached to a story is read at its end; a citation of '
      'it opens there', (tester) async {
    tall(tester);
    const host = 'obt/main/level_host.txt';
    const child = 'obt/tutorial/level/host.txt';
    List<StoryLineEntry> text(String tag, int n) => [
          for (var i = 0; i < n; i++)
            StoryLineEntry(lineIndex: i, content: '$tag$i', speaker: i == 0 ? '甲' : null),
        ];
    Widget scoped(Widget home) => ProviderScope(
          key: UniqueKey(),
          overrides: [
            userDataStoreProvider.overrideWith((ref) async => store),
            storyFullLinesProvider.overrideWith(
              (ref, id) async => id == host ? text('正文', 6) : text('战斗', 4),
            ),
            storyHostProvider.overrideWith(
              (ref, id) async => id == child ? host : null,
            ),
            attachedStoriesProvider.overrideWith(
              (ref, id) async => id == 'story:$host'
                  ? const [
                      LibraryEntry(
                        id: 'story:$child',
                        type: 'story',
                        name: '教程',
                        rawId: child,
                      ),
                    ]
                  : const [],
            ),
            storyCatalogEntryProvider.overrideWith((ref, id) async => null),
          ],
          child: MaterialApp(
            locale: const Locale('zh'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: home,
          ),
        );

    await tester.pumpWidget(scoped(const StoryReaderPage(storyId: host)));
    await settle(tester);
    expect(find.text('正文5'), findsOneWidget);
    expect(find.byKey(const ValueKey('story-reader-battle-dialogue')), findsOneWidget);
    expect(find.text('关卡内对话'), findsOneWidget);
    expect(find.text('战斗3'), findsOneWidget);
    // The attached lines keep their own numbers (1–4), not their place.
    expect(find.text('4'), findsWidgets);
    expect(find.text('11'), findsNothing);
    // History is kept under the story, with the whole text counted.
    var saved = (await store.recent()).single;
    expect(saved.ref, const LibraryRef.story(host).toString());
    expect(saved.totalLines, 6 + 1 + 4);

    // A citation of the attached dialogue's own lines opens the story it is
    // read in, at those lines.
    await store.clearHistory();
    await tester.pumpWidget(
      scoped(
        const StoryReaderPage(
          storyId: child,
          highlightStart: 1,
          highlightEnd: 2,
        ),
      ),
    );
    await settle(tester);
    expect(find.byKey(const ValueKey('story-line-target-8')), findsOneWidget);
    expect(find.byKey(const ValueKey('story-line-target-9')), findsOneWidget);
    // The header says the lines by their own numbers.
    await tester.drag(find.byKey(const ValueKey('story-reader-scroll')), const Offset(0, 3000));
    await settle(tester);
    expect(find.textContaining('第 2–3 行'), findsOneWidget);
    expect(find.textContaining('第 9–10 行'), findsNothing);
    saved = (await store.recent()).single;
    expect(saved.ref, const LibraryRef.story(host).toString());
    expect(tester.takeException(), isNull);
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