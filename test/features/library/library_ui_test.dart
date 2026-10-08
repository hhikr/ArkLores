import 'package:arklores/core/gamedata/game.dart';
import 'package:arklores/core/gamedata/story_catalog.dart' show StoryCatalogEntry;
import 'package:arklores/core/gamedata/story_coverage_models.dart';
import 'package:arklores/core/library/library_provider.dart';
import 'package:arklores/core/library/library_queries.dart';
import 'package:arklores/core/userdata/library_ref.dart';
import 'package:arklores/core/userdata/user_data_provider.dart';
import 'package:arklores/features/ai/story_labels_provider.dart';
import 'package:arklores/features/ai/story_reader_page.dart';
import 'package:arklores/features/library/library_pages.dart';
import 'package:arklores/features/library/library_widgets.dart';
import 'package:arklores/features/library/my_materials.dart';
import 'package:arklores/features/materials/materials_page.dart';
import 'package:arklores/shared/l10n/generated/app_localizations.dart';
import 'package:arklores/shared/providers/handoff_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/memory_user_store.dart';
import '../../support/screenshot.dart';

const _stories = [
  LibraryEntry(
    id: 'story:a/1_beg.txt',
    type: 'story',
    name: '风暴突击',
    code: '9-1',
    group: '行动前',
    rawId: 'a/1_beg.txt',
    collectionId: 'main_9',
    synopsis: '官方梗概：队伍抵达前线，面对第一次突击。',
  ),
  LibraryEntry(
    id: 'story:a/1_end.txt',
    type: 'story',
    name: '风暴突击',
    code: '9-1',
    group: '行动后',
    rawId: 'a/1_end.txt',
    collectionId: 'main_9',
  ),
  LibraryEntry(
    id: 'story:a/2_beg.txt',
    type: 'story',
    name: '暗火四起',
    code: '9-2',
    group: '行动前',
    rawId: 'a/2_beg.txt',
    collectionId: 'main_9',
  ),
];

const _operator = LibraryEntry(
  id: 'operator:char_x',
  type: 'operator',
  name: '干员甲',
  entityId: 'char_x',
);

const _enemy = LibraryEntry(
  id: 'enemy:e1',
  type: 'enemy',
  name: '深池侦察犬',
  rawId: 'e1',
);

List<Override> overrides(MemoryUserStore store) => [
      userDataStoreProvider.overrideWith((ref) async => store),
      libraryStatusProvider.overrideWith((ref) async => LibraryStatus.ready),
      gameLibraryStatusProvider.overrideWith(
        (ref, game) async => game == Game.arknights
            ? LibraryStatus.ready
            : LibraryStatus.notInstalled,
      ),
      shelfSummariesProvider.overrideWith(
        (ref, game) async => const [
          ShelfSummary(kind: 'main', collections: 18, stories: 463),
          ShelfSummary(kind: 'activity', collections: 327, stories: 1963),
          ShelfSummary(kind: 'memory', collections: 387, stories: 390),
          ShelfSummary(kind: 'roguelike', collections: 6, stories: 260),
          ShelfSummary(kind: 'sandbox', collections: 2, stories: 251),
        ],
      ),
      codexTypesProvider.overrideWith(
        (ref, game) async => const [
          (type: 'enemy', count: 1747),
        ],
      ),
      collectionsOfKindProvider.overrideWith(
        (ref, kind) async => [
          for (var i = 0; i < 30; i++)
            LibraryCollection(
              id: '${kind}_$i',
              kind: kind,
              name: '$kind 集合 $i',
              stories: 3,
              others: i.isEven ? 4 : 0,
              startTime: kind == 'activity' ? 1700000000 - i * 9000000 : null,
              sortKey: i,
            ),
        ],
      ),
      collectionProvider.overrideWith(
        (ref, id) async => const LibraryCollection(
          id: 'main_9',
          kind: 'main',
          name: '风暴瞭望',
          stories: 3,
          others: 12,
        ),
      ),
      collectionStoriesProvider.overrideWith(
        (ref, id) async => id == 'rogue_x'
            ? const [
                LibraryEntry(
                  id: 'story:ro/entry.txt',
                  type: 'story',
                  name: '开局剧情',
                  group: '开局剧情',
                  rawId: 'ro/entry.txt',
                  collectionId: 'rogue_x',
                ),
              ]
            : _stories,
      ),
      collectionTypesProvider.overrideWith(
        (ref, id) async => const [
          (type: 'stage', count: 12),
          (type: 'enemy', count: 25),
        ],
      ),
      entriesOfTypeProvider.overrideWith(
        (ref, key) async => [
          _enemy,
          LibraryEntry(
            id: 'enemy:e2',
            type: 'enemy',
            name: key.query.isEmpty ? '深池侦察兵' : '过滤结果',
            code: 'E2',
          ),
        ],
      ),
      entryGroupsProvider.overrideWith(
        (ref, key) async => key.type == 'roguelike_item'
            ? const [
                (group: 'relic', count: 20),
                (group: 'copper', count: 15),
                (group: 'copper_buff', count: 5),
                (group: 'wrath', count: 2),
              ]
            : const [],
      ),
      collectionIntroProvider.overrideWith(
        (ref, id) async => id == 'rogue_x' ? '这是一个主题的小小介绍。' : null,
      ),
      collectionInlineProvider.overrideWith(
        (ref, id) async => id == 'rogue_x'
            ? const [
                LibraryEntry(
                  id: 'roguelike_tip:rogue_x/0',
                  type: 'roguelike_tip',
                  name: '词语',
                  synopsis: '词语——一个词语的解释。',
                ),
                LibraryEntry(
                  id: 'roguelike_ending:rogue_x/e1',
                  type: 'roguelike_ending',
                  name: '某结局',
                  synopsis: '结局的一句话。',
                ),
                LibraryEntry(
                  id: 'roguelike_squad:rogue_x/s1',
                  type: 'roguelike_squad',
                  name: '小队甲',
                  group: '2026年7月',
                  synopsis: '小队的一句话。',
                ),
              ]
            : const [],
      ),
      entryPartsProvider.overrideWith(
        (ref, id) async =>
            id.startsWith('roguelike_') || id.startsWith('sandbox_act')
                ? _stories
                : const [],
      ),
      entryProvider.overrideWith(
        (ref, id) async => switch (id) {
          'roguelike_ending:rogue_x/e1' => const LibraryEntry(
              id: 'roguelike_ending:rogue_x/e1',
              type: 'roguelike_ending',
              name: '暗火四起',
            ),
          'roguelike_squad:rogue_x/s1' => const LibraryEntry(
              id: 'roguelike_squad:rogue_x/s1',
              type: 'roguelike_squad',
              name: '小队甲',
            ),
          'enemy:e1' => _enemy,
          'stage:fx' => const LibraryEntry(id: 'stage:fx', type: 'stage', name: '某关'),
          'sandbox_act:s/1' => const LibraryEntry(
              id: 'sandbox_act:s/1',
              type: 'sandbox_act',
              name: '第一幕',
            ),
          'operator:char_x' => _operator,
          _ => null,
        },
      ),
      operatorMemoriesProvider.overrideWith(
        (ref, id) async => const [
          LibraryCollection(
            id: 'story_x_set_1',
            kind: 'memory',
            name: '苹果',
            stories: 2,
            others: 0,
          ),
        ],
      ),
      operatorOwnedProvider.overrideWith(
        (ref, id) async => const [
          LibraryEntry(id: 'module:m1', type: 'module', name: '模组甲', code: 'X-A'),
          LibraryEntry(id: 'skin:s1', type: 'skin', name: '皮肤甲'),
          LibraryEntry(id: 'operator_stage:p1', type: 'operator_stage', name: '模拟场景', code: 'EX'),
        ],
      ),
      entryTextsProvider.overrideWith(
        (ref, entry) async => const [
          EntryTextBlock(
            title: '深池侦察犬',
            content: '深池里训练出来的猎犬，嗅觉敏锐，常被放出来探路。'
                '<@ba.kw>关键词</>需要清理。',
          ),
        ],
      ),
      entryBindingsProvider.overrideWith(
        (ref, id) async => id.startsWith('roguelike_squad')
            ? [
                const EntryBinding(
                  relation: 'features',
                  outgoing: true,
                  entry: LibraryEntry(
                    id: 'operator:char_x',
                    type: 'operator',
                    name: '干员甲',
                  ),
                ),
              ]
            : [
          for (var i = 0; i < 6; i++)
            EntryBinding(
              relation: 'appears_in',
              outgoing: true,
              entry: LibraryEntry(
                id: 'stage:s$i',
                type: 'stage',
                name: '关卡$i',
                code: '9-$i',
              ),
            ),
        ],
      ),
      storyPlaceProvider.overrideWith(
        (ref, id) async => StoryPlace(
          entry: _stories[1],
          previous: _stories[0],
          next: _stories[2],
        ),
      ),
      librarySearchProvider.overrideWith(
        (ref, key) async => key.query == '无此名'
            // No name has it: a close name and a story whose text has it.
            ? LibrarySearchResult(
                similar: [_enemy],
                mentions: [
                  LibraryTextHit(
                    entry: _stories[0],
                    count: 2,
                    line: 4,
                    snippet: '…提到无此名的一行…',
                  ),
                ],
                searchedText: true,
              )
            : LibrarySearchResult(
                collections: const [
                  LibraryCollection(
                    id: 'main_9',
                    kind: 'main',
                    name: '风暴瞭望',
                    stories: 3,
                    others: 0,
                  ),
                ],
                entries: [..._stories, _enemy],
              ),
      ),
      storyHostProvider.overrideWith((ref, id) async => null),
      attachedStoriesProvider.overrideWith(
        (ref, id) async => id == 'stage:fx'
            ? const [
                LibraryEntry(
                  id: 'story:t/battle.txt',
                  type: 'story',
                  name: '教程',
                  rawId: 't/battle.txt',
                ),
              ]
            : const [],
      ),
      storyFullLinesProvider.overrideWith(
        (ref, id) async => [
          for (var i = 0; i < 80; i++)
            StoryLineEntry(
              lineIndex: i,
              speaker: i % 3 == 0 ? '甲' : null,
              content: '第$i句。' * 4,
            ),
        ],
      ),
      storyCatalogEntryProvider.overrideWith((ref, id) async => null),
    ];

void _noop() {}

void main() {
  late MemoryUserStore store;

  setUp(() => store = MemoryUserStore());

  Future<void> pumpApp(WidgetTester tester, Widget home) async {
    tester.view.physicalSize = const Size(1080, 2160);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        key: UniqueKey(),
        overrides: overrides(store),
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => Shot(child: child!),
          home: home,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('home: shelves, continue card and recent reads', (tester) async {
    for (final (i, id) in ['a/1_beg.txt', 'b.txt', 'c.txt'].indexed) {
      await store.recordOpen(
        LibraryRef.story(id),
        title: '风暴瞭望 9-${i + 1} 行动前《风暴突击》',
        lineIndex: 12,
        snippet: '这是读到的那一行的开头文字',
        totalLines: 100,
      );
      await store.updateProgress(
        LibraryRef.story(id),
        lineIndex: 12,
        snippet: '这是读到的那一行的开头文字',
        totalLines: 100,
        reached: i == 1 ? 99 : 40,
      );
    }
    await pumpApp(tester, const MaterialsPage());
    await shoot(tester, 'library_home');

    // One tab per game and one for the user's texts, not a "read" tab.
    expect(find.text('明日方舟'), findsOneWidget);
    expect(find.text('终末地'), findsOneWidget);
    expect(find.text('我的资料'), findsOneWidget);
    expect(find.byKey(const ValueKey('library-continue')), findsOneWidget);
    for (final k in ['main', 'activity', 'memory', 'roguelike', 'sandbox', 'codex']) {
      expect(find.byKey(ValueKey('shelf-$k')), findsOneWidget, reason: k);
    }
    expect(find.text('18 项 · 463 个故事'), findsOneWidget);
    expect(find.text('1747 条'), findsOneWidget);
    await tester.drag(find.byType(ListView).first, const Offset(0, -1500));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('library-all-recent')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('both games installed: a section of shelves per game', (tester) async {
    tester.view.physicalSize = const Size(1080, 3200);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...overrides(store),
          gameLibraryStatusProvider
              .overrideWith((ref, game) async => LibraryStatus.ready),
          shelfSummariesProvider.overrideWith(
            (ref, game) async => game == Game.endfield
                ? const [
                    ShelfSummary(kind: 'ef/main', collections: 64, stories: 1656),
                    ShelfSummary(kind: 'ef/archive', collections: 23, stories: 0),
                    ShelfSummary(kind: 'ef/memory', collections: 80, stories: 1476),
                  ]
                : const [
                    ShelfSummary(kind: 'main', collections: 18, stories: 463),
                  ],
          ),
          codexTypesProvider.overrideWith(
            (ref, game) async => const [(type: 'enemy', count: 92)],
          ),
        ],
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => Shot(child: child!),
          home: const MaterialsPage(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    // Arknights first: only its shelves are on the page.
    for (final k in ['main', 'codex']) {
      expect(find.byKey(ValueKey('shelf-$k')), findsOneWidget, reason: k);
    }
    expect(find.byKey(const ValueKey('shelf-ef/main')), findsNothing);

    // A sideways drag does not change the game.
    await tester.drag(
      find.byKey(const ValueKey('library-game-arknights')),
      const Offset(-600, 0),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('shelf-main')), findsOneWidget);
    expect(find.byKey(const ValueKey('shelf-ef/main')), findsNothing);

    // The Endfield tab is its own page.
    await tester.tap(find.byKey(const ValueKey('library-tab-1')));
    await tester.pumpAndSettle();
    await shoot(tester, 'library_endfield_home');
    for (final k in ['ef/main', 'ef/archive', 'ef/memory', 'ef/codex']) {
      expect(find.byKey(ValueKey('shelf-$k')), findsOneWidget, reason: k);
    }
    expect(find.byKey(const ValueKey('shelf-main')), findsNothing);
    expect(find.text('主线任务'), findsOneWidget);
    expect(find.text('情报档案库'), findsOneWidget);
    expect(find.byKey(const ValueKey('library-missing-endfield')), findsNothing);

    // Back to Arknights: the page is as it was.
    await tester.tap(find.byKey(const ValueKey('library-tab-0')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('shelf-main')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an Endfield shelf lists missions by region with their descriptions; '
      'a mission reads as one text, its conversations set off by kind', (tester) async {
    tester.view.physicalSize = const Size(1080, 2160);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    LibraryCollection mission(int i, String? region) => LibraryCollection(
          id: 'ef/mission_m$i',
          kind: 'ef/main',
          name: '任务$i',
          stories: 1,
          others: 0,
          sortKey: i,
          intro: '任务$i的简介：一行说明。',
          group: region,
          firstStory: 'ef/m$i.txt',
        );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...overrides(store),
          collectionsOfKindProvider.overrideWith(
            (ref, kind) async => [
              mission(0, null),
              mission(1, '甲地'),
              mission(2, '乙地'),
              mission(3, '甲地'),
            ],
          ),
          storyFullLinesProvider.overrideWith(
            (ref, id) async => const [
              StoryLineEntry(lineIndex: 0, content: '对话', kind: 'section'),
              StoryLineEntry(lineIndex: 1, speaker: '甲', content: '第一段。'),
              StoryLineEntry(lineIndex: 2, content: '对话', kind: 'section'),
              StoryLineEntry(lineIndex: 3, speaker: '乙', content: '第二段。'),
              StoryLineEntry(lineIndex: 4, content: '通讯', kind: 'section'),
              StoryLineEntry(lineIndex: 5, speaker: '甲', content: '通讯里的一句。'),
            ],
          ),
        ],
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => Shot(child: child!),
          home: const ShelfPage(kind: 'ef/main'),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await shoot(tester, 'library_endfield_shelf');
    // Regions in the order they first come up, a mission without one last.
    final headings = [
      for (final h in ['甲地', '乙地', '其他'])
        tester.getTopLeft(find.byKey(ValueKey('shelf-heading-$h'))).dy,
    ];
    expect(headings, orderedEquals([...headings]..sort()));
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('collection-ef/mission_m3'))).dy,
      lessThan(headings[1]),
    );
    expect(find.text('任务1的简介：一行说明。'), findsOneWidget);
    // A mission that is one story opens it: no page with a single row.
    await tester.tap(find.byKey(const ValueKey('collection-ef/mission_m1')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(StoryReaderPage), findsOneWidget);
    expect(find.byType(CollectionPage), findsNothing);

    await tester.pumpWidget(
      ProviderScope(
        key: UniqueKey(),
        overrides: [
          ...overrides(store),
          storyFullLinesProvider.overrideWith(
            (ref, id) async => const [
              StoryLineEntry(lineIndex: 0, content: '对话', kind: 'section'),
              StoryLineEntry(lineIndex: 1, speaker: '甲', content: '第一段。'),
              StoryLineEntry(lineIndex: 2, content: '对话', kind: 'section'),
              StoryLineEntry(lineIndex: 3, speaker: '乙', content: '第二段。'),
              StoryLineEntry(lineIndex: 4, content: '通讯', kind: 'section'),
              StoryLineEntry(lineIndex: 5, speaker: '甲', content: '通讯里的一句。'),
            ],
          ),
          storyCatalogEntryProvider.overrideWith(
            (ref, id) async => const StoryCatalogEntry(
              storyId: 'ef/m1.txt',
              collectionId: 'ef/mission_m1',
              collectionName: '任务1',
              collectionType: 'EF_MAIN',
              storySort: 0,
              storyName: '任务1',
              synopsis: '甲与乙在谷地相遇。\n乙独自离开。',
            ),
          ),
          collectionIntroProvider.overrideWith((ref, id) async => '任务1的简介。'),
        ],
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => Shot(child: child!),
          home: const StoryReaderPage(storyId: 'ef/m1.txt'),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await shoot(tester, 'library_endfield_reader');
    // The kind is named where it changes; the next part of the same kind is
    // set off by a rule alone.
    expect(find.byKey(const ValueKey('story-reader-section-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('story-reader-section-2')), findsOneWidget);
    expect(find.text('对话'), findsOneWidget);
    expect(find.text('通讯'), findsOneWidget);
    expect(find.text('第二段。'), findsOneWidget);
    // The mission's description heads the story; the official synopsis
    // (the whole story told short) is folded until it is asked for.
    // (The description is asked for once the story's mission is known.)
    await tester.pump();
    expect(find.byKey(const ValueKey('story-reader-synopsis')), findsOneWidget);
    expect(find.text('任务1的简介。'), findsOneWidget);
    expect(find.text('甲与乙在谷地相遇。'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('fold-官方梗概')));
    await tester.pumpAndSettle();
    // One paragraph per line of the synopsis.
    expect(find.text('甲与乙在谷地相遇。'), findsOneWidget);
    expect(find.text('乙独自离开。'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Endfield not installed: its page has a note instead of shelves', (tester) async {
    await pumpApp(tester, const MaterialsPage());
    expect(find.byKey(const ValueKey('library-missing-endfield')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('library-tab-1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('library-missing-endfield')), findsOneWidget);
    expect(find.byKey(const ValueKey('shelf-ef/main')), findsNothing);
  });

  testWidgets('home without history shows only the shelves', (tester) async {
    await pumpApp(tester, const MaterialsPage());
    expect(find.byKey(const ValueKey('library-continue')), findsNothing);
    expect(find.byKey(const ValueKey('shelf-main')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shelf → collection → story', (tester) async {
    await pumpApp(tester, const MaterialsPage());
    await tester.tap(find.byKey(const ValueKey('shelf-activity')));
    await tester.pumpAndSettle();
    await shoot(tester, 'library_shelf');
    expect(find.text('其他活动'), findsWidgets);
    expect(find.byKey(const ValueKey('collection-activity_0')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('collection-activity_0')));
    await tester.pumpAndSettle();
    await shoot(tester, 'library_collection');
    expect(find.text('风暴瞭望'), findsWidgets);
    expect(find.byKey(const ValueKey('story-row-story:a/1_beg.txt')), findsOneWidget);
    expect(find.textContaining('官方梗概'), findsOneWidget);
    // A short list of one kind is listed in place, not behind a row.
    expect(find.byKey(const ValueKey('collection-inline-stage')), findsOneWidget);
    expect(find.byKey(const ValueKey('collection-type-stage')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('story-row-story:a/1_beg.txt')));
    await tester.pumpAndSettle();
    expect(find.byType(StoryReaderPage), findsOneWidget);
    // Opened from the library: nothing is highlighted, the end offers the
    // previous and the next chapter.
    expect(find.byKey(const ValueKey('story-line-target-0')), findsNothing);
    // The list is lazy: each drag reaches as far as what is built so far.
    for (var i = 0; i < 30; i++) {
      await tester.drag(
        find.byKey(const ValueKey('story-reader-scroll')),
        const Offset(0, -20000),
      );
      await tester.pumpAndSettle();
      if (find.byKey(const ValueKey('story-reader-previous')).evaluate().isNotEmpty) {
        break;
      }
    }
    await shoot(tester, 'library_reader_end');
    expect(find.byKey(const ValueKey('story-reader-previous')), findsOneWidget);
    expect(find.byKey(const ValueKey('story-reader-next')), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    // The visit and how far it was read are in the history.
    final saved = await store.recent();
    expect(saved, hasLength(1));
    expect(saved.single.totalLines, 80);
    expect(saved.single.furthest, greaterThan(60));
    expect(tester.takeException(), isNull);
  });

  testWidgets('codex lists entry types; entries open the entry page',
      (tester) async {
    await pumpApp(tester, const MaterialsPage());
    await tester.tap(find.byKey(const ValueKey('shelf-codex')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('codex-type-enemy')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('codex-type-enemy')));
    await tester.pumpAndSettle();
    await shoot(tester, 'library_entries');
    await tester.tap(find.byKey(const ValueKey('entry-row-enemy:e1')));
    await tester.pumpAndSettle();
    await shoot(tester, 'library_entry');
    expect(find.textContaining('嗅觉敏锐'), findsOneWidget);
    // Rich-text markup is cleaned.
    expect(find.textContaining('<@'), findsNothing);
    expect(find.byKey(const ValueKey('binding-stage:s0')), findsOneWidget);
    expect(find.textContaining('出现在'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the operator shelf lists operators; their page holds it all',
      (tester) async {
    await pumpApp(tester, const MaterialsPage());
    expect(find.byKey(const ValueKey('shelf-retro')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('shelf-memory')));
    await tester.pumpAndSettle();
    expect(find.text('干员'), findsWidgets);
    expect(find.byKey(const ValueKey('codex-type-operator')), findsNothing);

    await pumpApp(tester, const OperatorPage(entryId: 'operator:char_x'));
    await shoot(tester, 'library_operator');
    expect(find.text('干员甲'), findsWidgets);
    expect(find.text('干员密录'), findsWidgets);
    expect(find.byKey(const ValueKey('operator-record-story_x_set_1')), findsOneWidget);
    await tester.drag(find.byType(ListView).first, const Offset(0, -2000));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('operator-owned-module:m1')), findsOneWidget);
    expect(find.byKey(const ValueKey('operator-owned-skin:s1')), findsOneWidget);
    // The simulation stages carry their own name, not "密录关卡".
    expect(find.text('悖论模拟'), findsWidgets);
    expect(find.byKey(const ValueKey('operator-owned-operator_stage:p1')), findsOneWidget);
    expect(find.textContaining('嗅觉敏锐'), findsOneWidget); // the profile text
    // The ids of the paradox simulation / module codes are not shown, and
    // the profile is the first section under the card.
    expect(find.textContaining('模组甲'), findsOneWidget);
    expect(find.text('EX'), findsNothing);
    expect(find.text('X-A'), findsNothing);
    await tester.drag(find.byType(ListView).first, const Offset(0, 2000));
    await tester.pumpAndSettle();
    final profileAt = tester.getTopLeft(find.text('干员档案').first).dy;
    final recordsAt = tester.getTopLeft(find.text('干员密录').last).dy;
    expect(profileAt, lessThan(recordsAt));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a long grouped list is shown by named group; a chip picks one in place',
      (tester) async {
    await pumpApp(
      tester,
      const EntryListPage(
        type: 'roguelike_item',
        collectionId: 'rogue_5',
        collectionName: '主题',
      ),
    );
    // Game codes are named; one without a name is "其他", never raw.
    expect(find.byKey(const ValueKey('group-藏品')), findsOneWidget);
    expect(find.byKey(const ValueKey('group-通宝')), findsOneWidget);
    expect(find.byKey(const ValueKey('group-其他')), findsOneWidget);
    expect(find.byKey(const ValueKey('group-all')), findsOneWidget);
    expect(find.textContaining('copper'), findsNothing);
    expect(find.textContaining('wrath'), findsNothing);
    // The whole list carries the group headings; no page of groups first.
    expect(find.byKey(const ValueKey('group-heading-其他')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('group-藏品')));
    await tester.pumpAndSettle();
    expect(find.byType(EntryListPage), findsOneWidget);
    expect(find.byKey(const ValueKey('group-heading-其他')), findsNothing);
    expect(find.byKey(const ValueKey('entry-row-enemy:e1')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a profile reads in parts that fold, open; voice lines are quotes, '
      'numbered ones under one heading', (tester) async {
    await pumpApp(
      tester,
      Scaffold(
        body: ListView(
          children: const [
            ProfileText(
              '## 干员情报\n阵营：某工业\n种族：某族\n'
              '## 基础档案\n【代号】甲\n【矿石病感染情况】\n确认为非感染者。\n'
              '## 语音记录\n问候：你好，管理员。\n信赖对话1：第一次。\n信赖对话2：第二次。',
            ),
          ],
        ),
      ),
    );
    await shoot(tester, 'library_profile');
    // Every part is open; a fact list and 【】 fields set off their labels.
    expect(find.text('某工业'), findsOneWidget);
    expect(find.text('阵营'), findsOneWidget);
    expect(find.text('代号'), findsOneWidget);
    expect(find.text('确认为非感染者。'), findsOneWidget);
    // Voice lines: the title over the line; numbered titles of one kind
    // under one heading, each by its number.
    expect(find.text('问候'), findsOneWidget);
    expect(find.text('你好，管理员。'), findsOneWidget);
    expect(find.text('信赖对话'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(find.text('第二次。'), findsOneWidget);
    // A part folds when its head is tapped.
    await tester.tap(find.byKey(const ValueKey('fold-基础档案')));
    await tester.pumpAndSettle();
    expect(find.text('确认为非感染者。'), findsNothing);
    expect(find.text('某工业'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a character shows its number after the name, not as a code',
      (tester) async {
    await pumpApp(
      tester,
      const Scaffold(
        body: EntryRow(
          entry: LibraryEntry(
            id: 'operator:char_y',
            type: 'operator',
            name: '干员乙',
            code: 'RCX7',
          ),
          onTap: _noop,
        ),
      ),
    );
    expect(find.textContaining('编号 RCX7'), findsOneWidget);
    expect(find.text('RCX7'), findsNothing);
  });

  testWidgets('a topic opens with its introduction and its own parts',
      (tester) async {
    await pumpApp(tester, const CollectionPage(collectionId: 'rogue_x'));
    expect(find.byKey(const ValueKey('collection-intro')), findsOneWidget);
    expect(find.text('这是一个主题的小小介绍。'), findsOneWidget);
    expect(find.byKey(const ValueKey('part-roguelike_ending:rogue_x/e1')), findsOneWidget);
    expect(find.text('结局的一句话。'), findsOneWidget);
    expect(find.textContaining('2026年7月'), findsOneWidget);
    // The headings that split the page into stories and related texts are
    // gone; the kinds of texts are plain rows.
    expect(find.text('剧情'), findsNothing);
    // The opening story has its own place, above the endings; nothing is
    // left under \
    // Notes first, then the opening story, the endings and squads; the kinds
    // of texts (zones to medals) are under one heading.
    // The notes are one folding row; opening it lists them.
    expect(find.text('注释'), findsOneWidget);
    expect(find.text('相关资料'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('notes-group')));
    await tester.pumpAndSettle();
    double rowTop(String key) => tester.getTopLeft(find.byKey(ValueKey(key))).dy;
    expect(
      rowTop('part-roguelike_tip:rogue_x/0'),
      lessThan(rowTop('story-row-story:ro/entry.txt')),
    );
    await tester.drag(find.byType(ListView).first, const Offset(0, -2000));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('collection-inline-stage')), findsOneWidget);
    await tester.drag(find.byType(ListView).first, const Offset(0, 2000));
    await tester.pumpAndSettle();
    // An ending's page: its stories, in order.
    await tester.tap(find.byKey(const ValueKey('part-roguelike_ending:rogue_x/e1')));
    await tester.pumpAndSettle();
    expect(find.text('解锁的故事'), findsWidgets);
    expect(find.text('包含的故事'), findsNothing);
    // The story named like the ending comes first, right under its page's
    // top; what it unlocks follows the heading.
    double top(String id) =>
        tester.getTopLeft(find.byKey(ValueKey('story-row-story:$id'))).dy;
    final heading = tester.getTopLeft(find.text('解锁的故事').first).dy;
    expect(top('a/2_beg.txt'), lessThan(heading));
    expect(top('a/1_beg.txt'), greaterThan(heading));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a month squad shows its protagonist above its stories',
      (tester) async {
    await pumpApp(
      tester,
      const EntryPage(entryId: 'roguelike_squad:rogue_x/s1'),
    );
    expect(find.text('主角'), findsWidgets);
    expect(find.text('关联'), findsNothing);
    final chat = tester.getTopLeft(find.byKey(const ValueKey('binding-operator:char_x'))).dy;
    final heading = tester.getTopLeft(find.text('解锁的故事').first).dy;
    expect(chat, lessThan(heading));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a stage page reads the dialogue played in its battle',
      (tester) async {
    await pumpApp(tester, const EntryPage(entryId: 'stage:fx'));
    await tester.pumpAndSettle();
    expect(find.text('关卡内对话'), findsOneWidget);
    expect(find.textContaining('第0句。'), findsWidgets);
    // Not a row to open: the dialogue is on the page.
    expect(find.byKey(const ValueKey('part-story-story:t/battle.txt')), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('an act of a sandbox plot holds its stories in order, with no '
      '"unlocked" heading', (tester) async {
    await pumpApp(tester, const EntryPage(entryId: 'sandbox_act:s/1'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('part-story-story:a/1_beg.txt')), findsOneWidget);
    expect(find.byKey(const ValueKey('part-story-story:a/2_beg.txt')), findsOneWidget);
    expect(find.text('解锁的故事'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('search offers collections and entries', (tester) async {
    await pumpApp(tester, const MaterialsPage());
    await tester.tap(find.byKey(const ValueKey('library-search')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '风暴');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    await shoot(tester, 'library_search');
    expect(find.byKey(const ValueKey('hit-collection-main_9')), findsOneWidget);
    expect(find.byKey(const ValueKey('story-row-story:a/1_beg.txt')), findsOneWidget);
    expect(find.byKey(const ValueKey('entry-row-enemy:e1')), findsOneWidget);
    // Names matched: the texts are searched only on request.
    expect(find.byKey(const ValueKey('search-text')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a search no name matches shows close names and the texts',
      (tester) async {
    await pumpApp(tester, const MaterialsPage());
    await tester.tap(find.byKey(const ValueKey('library-search')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '无此名');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    await shoot(tester, 'library_search_fallback');
    expect(find.textContaining('没有名字含「无此名」'), findsOneWidget);
    expect(find.text('相近的名字'), findsOneWidget);
    expect(find.byKey(const ValueKey('entry-row-enemy:e1')), findsOneWidget);
    expect(find.text('正文提到'), findsOneWidget);
    expect(find.byKey(const ValueKey('hit-text-story:a/1_beg.txt')), findsOneWidget);
    expect(find.textContaining('…提到无此名的一行…'), findsOneWidget);
    expect(find.byKey(const ValueKey('search-text')), findsNothing);
    // No embedding service configured: no semantic button.
    expect(find.byKey(const ValueKey('search-semantic')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets("a page's search looks in the page until widened",
      (tester) async {
    await pumpApp(tester, const CollectionPage(collectionId: 'rogue_x'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('library-search')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('search-scope')), findsOneWidget);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(LibrarySearchPage)),
    );
    await tester.enterText(find.byType(TextField), '风暴');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(
      container.exists(librarySearchProvider(
        (query: '风暴', scope: listScope(collectionId: 'rogue_x'), text: false),
      ),),
      isTrue,
    );
    await tester.tap(find.byIcon(Icons.close_sharp));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('search-scope')), findsNothing);
    expect(
      container.exists(librarySearchProvider(
        (query: '风暴', scope: everywhere, text: false),
      ),),
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('my texts: create, read, edit, ask about it, delete',
      (tester) async {
    await pumpApp(tester, const MaterialsPage());
    await tester.tap(find.text('我的资料'));
    await tester.pumpAndSettle();
    expect(find.text('还没有自己的资料'), findsOneWidget);
    await shoot(tester, 'materials_empty');

    await tester.tap(find.byKey(const ValueKey('materials-new')));
    await tester.pumpAndSettle();
    // Nothing to save yet.
    expect(
      tester
          .widget<TextButton>(find.byKey(const ValueKey('material-save')))
          .onPressed,
      isNull,
    );
    await tester.enterText(find.byKey(const ValueKey('material-body')), '一段设定摘录\n第二行');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('material-save')));
    await tester.pumpAndSettle();
    expect(find.text('一段设定摘录'), findsWidgets);
    await shoot(tester, 'materials_list');

    await tester.tap(find.byKey(const ValueKey('material-m1')));
    await tester.pumpAndSettle();
    await shoot(tester, 'materials_read');
    expect(find.textContaining('第二行'), findsOneWidget);

    // Edit.
    await tester.tap(find.byKey(const ValueKey('material-edit')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('material-title')), '改过的标题');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('material-save')));
    await tester.pumpAndSettle();
    expect(find.text('改过的标题'), findsWidgets);
    expect(store.items['m1']!.title, '改过的标题');

    // Ask about it: the text goes to the question box draft, the Ask tab is
    // requested; nothing is sent.
    final container = ProviderScope.containerOf(
      tester.element(find.byType(MyMaterialPage)),
    );
    await tester.tap(find.byKey(const ValueKey('material-ask')));
    await tester.pumpAndSettle();
    expect(container.read(askDraftProvider), startsWith('「一段设定摘录'));
    expect(container.read(askDraftProvider), endsWith('」\n\n'));
    expect(container.read(mainTabRequestProvider), 1);
  });

  testWidgets('deleting a material asks first', (tester) async {
    await store.saveMaterial(title: '待删', body: '内容');
    await pumpApp(tester, const MyMaterialPage(id: 'm1'));
    await tester.tap(find.byKey(const ValueKey('material-delete')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('material-delete-confirm')));
    await tester.pumpAndSettle();
    expect(store.items, isEmpty);
  });

  testWidgets('leaving the editor with changes asks first', (tester) async {
    await pumpApp(tester, const MaterialsPage());
    await tester.tap(find.text('我的资料'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('materials-new')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('material-body')), '没存的内容');
    await tester.pump();
    final NavigatorState nav = tester.state(find.byType(Navigator).last);
    await nav.maybePop();
    await tester.pumpAndSettle();
    expect(find.text('放弃未保存的修改？'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('material-discard-confirm')));
    await tester.pumpAndSettle();
    expect(store.items, isEmpty);
    expect(find.byKey(const ValueKey('material-body')), findsNothing);
  });

  testWidgets('a missing or old knowledge base is explained', (tester) async {
    tester.view.physicalSize = const Size(1080, 2160);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final (status, text) in [
      (LibraryStatus.notInstalled, '明日方舟知识库未安装'),
      (LibraryStatus.oldSchema, '知识库需要更新'),
    ]) {
      await tester.pumpWidget(
        ProviderScope(
          key: UniqueKey(),
          overrides: [
            ...overrides(store),
            libraryStatusProvider.overrideWith((ref) async => status),
            gameLibraryStatusProvider.overrideWith(
              (ref, game) async => game == Game.arknights
                  ? status
                  : LibraryStatus.notInstalled,
            ),
          ],
          child: MaterialApp(
            locale: const Locale('zh'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            builder: (context, child) => Shot(child: child!),
            home: const MaterialsPage(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text(text), findsOneWidget);
      expect(find.byKey(const ValueKey('shelf-main')), findsNothing);
    }
  });
}
