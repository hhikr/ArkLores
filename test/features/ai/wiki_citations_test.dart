import 'package:arklores/core/agent/chat_message.dart';
import 'package:arklores/core/agent/react_event.dart';
import 'package:arklores/core/gamedata/game.dart';
import 'package:arklores/core/wiki/wiki_lookup.dart';
import 'package:arklores/core/wiki/wiki_provider.dart';
import 'package:arklores/features/ai/investigation_ui.dart';
import 'package:arklores/features/ai/widgets/story_answer_body.dart';
import 'package:arklores/features/ai/work_steps.dart';
import 'package:arklores/main.dart';
import 'package:arklores/shared/l10n/generated/app_localizations.dart';
import 'package:arklores/shared/providers/handoff_provider.dart';
import 'package:arklores/shared/providers/theme_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_wiki.dart';

/// 0.13: wiki citations in the answer view and wiki steps in the work
/// timeline. Fictional content only.
void main() {
  group('parsing', () {
    test('a block keeps its wiki citations apart from stories and records',
        () {
      final blocks = splitAnswerBlocks(
        '- 星灯是点灯人 `obt/main/level_main_fx-01.txt:3` '
        '`wiki:prts:101@7:1-2` `wiki:prts:101@7:3` `record:rec_1`。',
      );
      final block = blocks.single;
      expect(block.markdown, '- 星灯是点灯人。');
      expect(block.stories.single.storyId, 'obt/main/level_main_fx-01.txt');
      expect(block.records, ['rec_1']);
      final wiki = block.wikis.single;
      expect(wiki.pageId, 'wiki:prts:101@7');
      // Adjacent paragraph ranges merge.
      expect([for (final r in wiki.ranges) (r.start, r.end)], [(1, 3)]);
      expect(block.hasCitations, isTrue);

      final pages = extractCitedWikiPages(
        '甲 `wiki:warfarin:operators/star-lamp@1a2b3c4d:5` 乙 `wiki:prts:101@7:0`',
      );
      expect([for (final p in pages) p.pageId], [
        'wiki:warfarin:operators/star-lamp@1a2b3c4d',
        'wiki:prts:101@7',
      ]);
      expect(pages.first.parsed!.site.game, Game.endfield);
    });

    test('work steps: wiki searches and reads, with what they found', () {
      final steps = workStepsOf([
        const ReActStep(
          type: ReActEventType.toolCall,
          content: '',
          toolName: 'wiki_search',
          toolArgs: {'query': '星灯', 'game': 'endfield'},
        ),
        const ReActStep(
          type: ReActEventType.toolObservation,
          content: 'Warfarin Wiki 搜索“星灯”，3 个页面（格式：…）：\n…',
          toolName: 'wiki_search',
        ),
        const ReActStep(
          type: ReActEventType.toolCall,
          content: '',
          toolName: 'wiki_read',
          toolArgs: {'page': 'wiki:prts:101'},
        ),
        const ReActStep(
          type: ReActEventType.toolObservation,
          content: '《星灯》 PRTS，共 4 段\n页面 id：wiki:prts:101@7\n## 人物关系\nP1 甲\nP2 乙',
          toolName: 'wiki_read',
        ),
        const ReActStep(
          type: ReActEventType.toolCall,
          content: '',
          toolName: 'wiki_read',
          toolArgs: {'page': 'wiki:warfarin:operators/star-lamp'},
        ),
        const ReActStep(
          type: ReActEventType.toolObservation,
          content: 'Warfarin Wiki 暂时无法访问（超时）。请只用本地知识库作答。',
          toolName: 'wiki_read',
        ),
      ]);
      expect(steps.map((s) => s.kind),
          [WorkKind.wikiSearch, WorkKind.wikiRead, WorkKind.wikiRead],);
      expect(steps[0].wikiPageCount, 3);
      expect(steps[0].game, Game.endfield);
      expect(steps[1].wikiTitle, '星灯');
      expect(steps[1].paragraphRange, (1, 2));
      expect(steps[1].game, isNull);
      expect(steps[2].failed, isTrue);
      expect(steps[2].game, Game.endfield);
      expect(steps[2].wikiTitle, 'star-lamp');
    });
  });

  group('the answer view', () {
    late WikiLookup wiki;

    setUp(() async {
      wiki = fakeWikiLookup();
      // The agent read the page: its version is kept.
      await wiki.read('wiki:prts:101');
    });

    Widget app(Widget child, {List<Override> overrides = const []}) =>
        ProviderScope(
          overrides: [
            wikiLookupProvider.overrideWithValue(wiki),
            ...overrides,
          ],
          child: Consumer(
            builder: (context, ref, _) => MaterialApp(
              theme: buildAppTheme(ref.watch(themeProvider)),
              locale: const Locale('zh'),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: Scaffold(body: SingleChildScrollView(child: child)),
            ),
          ),
        );

    testWidgets('a wiki citation shows the page and its paragraphs; the sheet '
        'shows the kept text and opens the page in the Wiki tab',
        (tester) async {
      await tester.pumpWidget(app(
        StoryAnswerBody(
          content: '据 Wiki 整理，两人早就认识 `wiki:prts:101@7:1-2`。',
          styleSheet: MarkdownStyleSheet(),
          streaming: false,
        ),
      ),);
      await tester.pumpAndSettle();
      // One cited range; the source label names the wiki.
      expect(find.text('出处 1'), findsOneWidget);
      expect(find.text('Wiki'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('evidence-toggle')));
      await tester.pumpAndSettle();
      expect(find.text('PRTS《星灯》'), findsOneWidget);
      // Paragraphs are shown from 1.
      await tester.tap(find.text('第 2–3 段'));
      await tester.pumpAndSettle();
      expect(find.text('星灯与守夜人是旧识。'), findsOneWidget);
      expect(find.text('守夜人 | 旧识'), findsOneWidget);
      expect(find.text('人物关系'), findsOneWidget);
      expect(find.textContaining('二手资料'), findsOneWidget);

      final container = ProviderScope.containerOf(
        tester.element(find.byType(StoryAnswerBody)),
      );
      await tester.tap(find.byKey(const ValueKey('wiki-citation-open')));
      await tester.pumpAndSettle();
      final request = container.read(wikiOpenRequestProvider);
      expect(request!.siteId, 'prts');
      expect(request.url.toString(), 'https://prts.wiki/index.php?curid=101');
      expect(container.read(mainTabRequestProvider), 0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a version not kept on this device says so and still opens',
        (tester) async {
      await tester.pumpWidget(app(
        const WikiCitationSheet(
          pageId: 'wiki:warfarin:operators/star-lamp@1a2b3c4d',
          range: CitedRange(0, 0),
        ),
      ),);
      await tester.pumpAndSettle();
      expect(find.textContaining('没有保存在本机'), findsOneWidget);
      expect(find.byKey(const ValueKey('wiki-citation-open')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
