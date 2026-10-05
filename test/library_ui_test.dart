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

import 'support/memory_user_store.dart';
import 'support/screenshot.dart';

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
      shelfSummariesProvider.overrideWith(
        (ref) async => const [
          ShelfSummary(kind: 'main', collections: 18, stories: 463),
          ShelfSummary(kind: 'activity', collections: 327, stories: 1963),
          ShelfSummary(kind: 'memory', collections: 387, stories: 390),
          ShelfSummary(kind: 'roguelike', collections: 6, stories: 260),
          ShelfSummary(kind: 'sandbox', collections: 2, stories: 251),
        ],
      ),
      codexTypesProvider.overrideWith(
        (ref) async => const [
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
      collectionStoriesProvider.overrideWith((ref, id) async => _stories),
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
        (ref, id) async => id == 'roguelike_ending:rogue_x/e1' ? _stories : const [],
      ),
      entryProvider.overrideWith(
        (ref, id) async => switch (id) {
          'roguelike_ending:rogue_x/e1' => const LibraryEntry(
              id: 'roguelike_ending:rogue_x/e1',
              type: 'roguelike_ending',
              name: '某结局',
            ),
          'enemy:e1' => _enemy,
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
        (ref, id) async => [
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
        (ref, q) async => (
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

    expect(find.text('阅读'), findsOneWidget);
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
    expect(find.text('活动'), findsWidgets);
    expect(find.byKey(const ValueKey('collection-activity_0')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('collection-activity_0')));
    await tester.pumpAndSettle();
    await shoot(tester, 'library_collection');
    expect(find.text('风暴瞭望'), findsWidgets);
    expect(find.byKey(const ValueKey('story-row-story:a/1_beg.txt')), findsOneWidget);
    expect(find.textContaining('官方梗概'), findsOneWidget);
    expect(find.byKey(const ValueKey('collection-type-stage')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('story-row-story:a/1_beg.txt')));
    await tester.pumpAndSettle();
    expect(find.byType(StoryReaderPage), findsOneWidget);
    // Opened from the library: nothing is highlighted, the end offers the
    // previous and the next chapter.
    expect(find.byKey(const ValueKey('story-line-target-0')), findsNothing);
    await tester.drag(
      find.byKey(const ValueKey('story-reader-scroll')),
      const Offset(0, -20000),
    );
    await tester.pumpAndSettle();
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

  testWidgets('a long grouped list opens as a menu of named groups',
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
    expect(find.byKey(const ValueKey('group-铜钱')), findsOneWidget);
    expect(find.byKey(const ValueKey('group-铜钱效果')), findsOneWidget);
    expect(find.byKey(const ValueKey('group-其他')), findsOneWidget);
    expect(find.byKey(const ValueKey('group-all')), findsOneWidget);
    expect(find.textContaining('copper'), findsNothing);
    expect(find.textContaining('wrath'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('group-藏品')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('entry-row-enemy:e1')), findsOneWidget);
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
    expect(find.text('相关资料'), findsNothing);
    await tester.drag(find.byType(ListView).first, const Offset(0, -2000));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('collection-type-stage')), findsOneWidget);
    await tester.drag(find.byType(ListView).first, const Offset(0, 2000));
    await tester.pumpAndSettle();
    // An ending's page: its stories, in order.
    await tester.tap(find.byKey(const ValueKey('part-roguelike_ending:rogue_x/e1')));
    await tester.pumpAndSettle();
    expect(find.text('包含的故事'), findsWidgets);
    expect(find.byKey(const ValueKey('story-row-story:a/1_beg.txt')), findsOneWidget);
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
      (LibraryStatus.notInstalled, '还没有知识库'),
      (LibraryStatus.oldSchema, '知识库需要更新'),
    ]) {
      await tester.pumpWidget(
        ProviderScope(
          key: UniqueKey(),
          overrides: [
            ...overrides(store),
            libraryStatusProvider.overrideWith((ref) async => status),
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
