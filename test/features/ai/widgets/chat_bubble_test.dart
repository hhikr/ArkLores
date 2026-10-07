// One answer in the Ask list: the status line, the text with its folded
// sources per point, the summary tree, staged answers, opening a cited line,
// the live (streaming) state, the usage line and old sessions' formats.
import 'package:arklores/core/agent/agent_provider.dart';
import 'package:arklores/core/agent/react_event.dart';
import 'package:arklores/core/agent/story_answer.dart';
import 'package:arklores/core/agent/turn_stats.dart';
import 'package:arklores/core/gamedata/story_coverage_models.dart';
import 'package:arklores/core/library/library_provider.dart'
    show attachedStoriesProvider, storyHostProvider;
import 'package:arklores/core/llm/llm_client.dart' show MessageRole;
import 'package:arklores/features/ai/story_labels_provider.dart';
import 'package:arklores/features/ai/story_reader_page.dart';
import 'package:arklores/features/ai/widgets/chat_bubble.dart';
import 'package:arklores/shared/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _c5 = 'activities/act_fixture/level_fixture_c5.txt';
const _c6 = 'activities/act_fixture/level_fixture_c6.txt';
const _other = 'activities/act_other/level_other_c1.txt';

ChatMessage _answer(
  String content, {
  bool streaming = false,
  String liveStatus = '',
  String reasoning = '',
  TurnStats? stats,
}) =>
    ChatMessage(
      id: 'a',
      role: MessageRole.assistant,
      content: content,
      isStreaming: streaming,
      liveStatus: liveStatus,
      reasoning: reasoning,
      stats: stats,
      timestamp: DateTime(2026),
    );

String _answered(String body, {String? confidence}) =>
    '${formatStoryAnswerEnvelope(StoryAnswerStatus.answered, confidence: confidence)}\n$body';

/// Shows [message] alone on a page. [phone] sets a 320×640 dp screen;
/// [settle] waits for animations (not possible while a message streams).
Future<void> _pump(
  WidgetTester tester,
  ChatMessage message, {
  bool phone = true,
  bool scroll = true,
  bool settle = true,
  double textScale = 1,
  Locale locale = const Locale('zh'),
  List<Override> overrides = const [],
}) async {
  if (phone) {
    tester.view.physicalSize = const Size(640, 1280);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }
  final bubble = ChatBubble(message: message);
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(
          body: scroll ? SingleChildScrollView(child: bubble) : bubble,
        ),
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

Future<void> _openSources(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('evidence-toggle')));
  await tester.pumpAndSettle();
}

void main() {
  group('story answer', () {
    testWidgets('status, confidence and the cited line', (tester) async {
      await _pump(tester,
          _answer(_answered('答案正文。证据：$_c5:0。', confidence: '0.8')),
          scroll: false,);
      // R15: status and confidence share one line; no avatars.
      expect(find.text('已作答 · 置信度 0.8'), findsOneWidget);
      expect(find.byIcon(Icons.psychology_rounded), findsNothing);
      expect(find.byIcon(Icons.person_rounded), findsNothing);
      // R18b: the sources under the point are one pill (count + collection,
      // named from the path without a catalog) until tapped.
      expect(find.text('出处 1'), findsOneWidget);
      expect(find.text('活动 act_fixture'), findsOneWidget);
      expect(find.text('第 1 行'), findsNothing);
      await _openSources(tester);
      expect(find.textContaining('level_fixture_c5'), findsOneWidget);
      expect(find.text('第 1 行'), findsOneWidget);
      // R15: the summary tree is one folded line until tapped.
      await tester.tap(find.text('证据 1 处 · 来自 1 个故事'));
      await tester.pumpAndSettle();
      expect(find.text('活动 act_fixture · 1 处'), findsOneWidget);
      expect(find.text('level_fixture_c5 · 1 处'), findsOneWidget);
      expect(find.text('第 1 行'), findsNWidgets(2));
      // R14: readable names and 1-based lines; no paths, no envelope.
      expect(find.textContaining(_c5), findsNothing);
      expect(find.textContaining('STORY_ANSWER'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    // R18: the reorganised paragraphs are shown; the detailed answer below
    // the marker is one folded row. Evidence is counted once.
    testWidgets('a staged answer folds its details', (tester) async {
      await _pump(
        tester,
        _answer(_answered('## 第一阶段\n\n阶段概括。 `$_c5:0-1` `$_c5:3`\n\n[DETAILS]\n\n'
            '细节甲。 `$_c5:0-1`\n\n## 小节\n\n- 细节乙。 `$_c5:3`'),),
        scroll: false,
      );
      expect(find.text('阶段概括。'), findsOneWidget);
      expect(find.text('出处 2'), findsOneWidget);
      await _openSources(tester);
      expect(find.text('第 1–2 行'), findsOneWidget);
      expect(find.text('第 4 行'), findsOneWidget);
      expect(find.text('详细经过 · 2 条'), findsOneWidget);
      expect(find.text('细节甲。'), findsNothing);
      expect(find.textContaining('DETAILS'), findsNothing);
      expect(find.text('证据 2 处 · 来自 1 个故事'), findsOneWidget);
      await tester.tap(find.text('详细经过 · 2 条'));
      await tester.pumpAndSettle();
      expect(find.text('细节甲。'), findsOneWidget);
      expect(find.text('细节乙。'), findsOneWidget);
      // Each detailed point has its own folded sources.
      expect(find.byKey(const ValueKey('evidence-toggle')), findsNWidgets(3));
      expect(tester.takeException(), isNull);
    });

    testWidgets('a line chip opens the story at the cited lines',
        (tester) async {
      await _pump(
        tester,
        _answer(_answered('- 第一件事 `$_c5:60-61`\n- 第二件事')),
        scroll: false,
        overrides: [
          storyHostProvider.overrideWith((ref, id) async => null),
          attachedStoriesProvider.overrideWith((ref, id) async => const []),
          storyFullLinesProvider.overrideWith((ref, id) async => [
                for (var i = 0; i < 120; i++)
                  StoryLineEntry(
                    lineIndex: i,
                    speaker: i.isEven ? '甲' : null,
                    content: '第$i句',
                  ),
              ],),
        ],
      );
      // The chain follows the first item only; the citation left the text.
      expect(find.byKey(const ValueKey('evidence-toggle')), findsOneWidget);
      await _openSources(tester);
      expect(find.text('第 61–62 行'), findsOneWidget);
      expect(find.textContaining(_c5), findsNothing);

      await tester.tap(find.text('第 61–62 行'));
      await tester.pumpAndSettle();
      expect(find.byType(StoryReaderPage), findsOneWidget);
      // Only the cited lines are highlighted, and they were scrolled to.
      expect(find.byKey(const ValueKey('story-line-target-60')), findsOneWidget);
      expect(find.byKey(const ValueKey('story-line-target-61')), findsOneWidget);
      expect(find.byKey(const ValueKey('story-line-target-62')), findsNothing);
      expect(find.text('甲'), findsWidgets);
      expect(find.byKey(const ValueKey('story-reader-jump')), findsOneWidget);
      final top = tester
          .getTopLeft(find.byKey(const ValueKey('story-line-target-60')))
          .dy;
      expect(top, inExclusiveRange(0, 640));
      expect(tester.takeException(), isNull);
    });

    testWidgets('not covered', (tester) async {
      await _pump(
        tester,
        _answer('${formatStoryAnswerEnvelope(StoryAnswerStatus.notCovered, confidence: '0')}\n'
            '知识库未找到相关内容。'),
        phone: false,
        scroll: false,
      );
      expect(find.textContaining('知识库未覆盖'), findsWidgets);
    });
  });

  group('sources of one point, opened', () {
    testWidgets('chapters of one collection share a header and are indented',
        (tester) async {
      await _pump(tester, _answer(_answered('一件事。 `$_c5:0-1` `$_c5:9` `$_c6:3`')));
      await _openSources(tester);
      // The collection name: once in the pill, once as the group header.
      expect(find.text('活动 act_fixture'), findsNWidgets(2));
      final c5 = find.text('level_fixture_c5');
      expect(c5, findsOneWidget);
      expect(find.text('level_fixture_c6'), findsOneWidget);
      final header = find.text('活动 act_fixture').last;
      expect(tester.getTopLeft(c5).dx,
          greaterThan(tester.getTopLeft(header).dx + 6),);
      // Both ranges of the first chapter sit together (the test font is as
      // wide as it is tall, so a long name may push them onto its next line).
      final chip1 = find.byKey(const ValueKey('chain:$_c5:0-1'));
      final chip2 = find.byKey(const ValueKey('chain:$_c5:9'));
      expect(tester.getCenter(chip1).dy, tester.getCenter(chip2).dy);
      expect(tester.getCenter(chip1).dy - tester.getCenter(c5).dy, lessThan(30));
      // The second chapter follows close below (a compact card).
      final gap =
          tester.getCenter(find.byKey(const ValueKey('chain:$_c6:3'))).dy -
              tester.getCenter(chip1).dy;
      expect(gap, inInclusiveRange(18, 60));
      expect(tester.takeException(), isNull);
    });

    testWidgets('a single chapter is one line: collection · chapter and chips',
        (tester) async {
      await _pump(tester, _answer(_answered('一件事。 `$_c5:0-1`')));
      await _openSources(tester);
      final chip = find.byKey(const ValueKey('chain:$_c5:0-1'));
      final label = find.textContaining('level_fixture_c5');
      expect(label, findsOneWidget);
      expect(tester.getCenter(chip).dy - tester.getCenter(label).dy, lessThan(40));
    });

    testWidgets('different collections each get their own header',
        (tester) async {
      await _pump(tester, _answer(_answered('一件事。 `$_c5:0` `$_other:2`')));
      await _openSources(tester);
      expect(find.textContaining('活动 act_fixture'), findsWidgets);
      expect(find.textContaining('act_other'), findsWidgets);
      expect(find.textContaining('level_fixture_c5'), findsOneWidget);
      expect(find.textContaining('level_other_c1'), findsOneWidget);
      expect(find.byKey(const ValueKey('chain:$_c5:0')), findsOneWidget);
      expect(find.byKey(const ValueKey('chain:$_other:2')), findsOneWidget);
    });
  });

  group('while streaming', () {
    ChatMessage thinking(String reasoning, {bool streaming = true}) => _answer(
          '结论',
          streaming: streaming,
          liveStatus: streaming ? '正在撰写答案' : '',
          reasoning: reasoning,
        );

    testWidgets('the step, the thinking and the text without citations',
        (tester) async {
      await _pump(
        tester,
        _answer('结论（$_c5:0）\n[COVERAGE: fu',
            streaming: true, liveStatus: '正在撰写答案', reasoning: '先比较两段原文',),
        phone: false,
        scroll: false,
        settle: false,
      );
      expect(find.text('正在撰写答案'), findsOneWidget);
      expect(find.text('思考过程'), findsOneWidget);
      expect(find.text('先比较两段原文'), findsOneWidget);
      expect(find.textContaining('COVERAGE'), findsNothing);
      expect(find.textContaining('.txt'), findsNothing);
      // R17b: the citation leaves the text and the chain waits for the
      // finished answer, so nothing jumps.
      expect(find.text('结论'), findsOneWidget);
      expect(find.textContaining('第 1 行'), findsNothing);
      // The thinking folds away on tap.
      await tester.tap(find.text('思考过程'));
      await tester.pump();
      expect(find.text('先比较两段原文'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'R17d: the thinking window has one fixed height, holds the whole text '
        'and does not follow new thinking', (tester) async {
      Future<void> show(ChatMessage m) =>
          _pump(tester, m, phone: false, scroll: false, settle: false);
      await show(thinking('短'));
      final window = find.byKey(const ValueKey('reasoning-text'));
      final shortSize = tester.getSize(window);

      final long = [for (var i = 0; i < 80; i++) '第$i段思考'].join('\n');
      await show(thinking(long));
      expect(tester.getSize(window), shortSize);
      expect(find.textContaining('第0段思考'), findsOneWidget);
      expect(find.textContaining('第79段思考'), findsOneWidget);
      final scroll = tester.state<ScrollableState>(find.descendant(
        of: find.byKey(const ValueKey('reasoning-scroll')),
        matching: find.byType(Scrollable),
      ),);
      expect(scroll.position.maxScrollExtent, greaterThan(0));
      expect(scroll.position.pixels, 0);

      // More thinking arrives: the window stays where the reader left it.
      await show(thinking('$long\n更多思考'));
      expect(scroll.position.pixels, 0);
      expect(tester.getSize(window), shortSize);
      expect(tester.takeException(), isNull);
    });

    testWidgets('R17d: the thinking stays after the answer is complete',
        (tester) async {
      await _pump(tester, thinking('先比较两段原文', streaming: false),
          phone: false, scroll: false, settle: false,);
      expect(find.text('思考过程'), findsOneWidget);
      expect(find.text('先比较两段原文'), findsOneWidget);
    });

    testWidgets(
        'R17d: finished points already show their sources; the point being '
        'written does not', (tester) async {
      await _pump(
        tester,
        _answer('- 第一条 `$_c5:3-4`\n- 第二条 `$_c5:7`',
            streaming: true, liveStatus: '正在撰写答案',),
        phone: false,
        scroll: false,
        settle: false,
      );
      expect(find.byKey(const ValueKey('evidence-toggle')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('evidence-toggle')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('第 4–5 行'), findsOneWidget);
      expect(find.text('第 8 行'), findsNothing);
      expect(find.textContaining('.txt'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('usage line', () {
    Future<void> show(WidgetTester tester, TurnStats? stats,
            {Locale locale = const Locale('zh'),}) =>
        _pump(tester, _answer('一段回答。', stats: stats),
            phone: false, locale: locale, settle: false,);

    testWidgets('tokens, cache share, calls and time', (tester) async {
      await show(
        tester,
        const TurnStats(
          calls: 14,
          promptTokens: 381562,
          cachedPromptTokens: 332736,
          completionTokens: 11665,
          elapsed: Duration(seconds: 262),
        ),
      );
      expect(find.text('in 382k · out 11.7k · cache 87% · 14 calls · 4m22s'),
          findsOneWidget,);
    });

    testWidgets('a provider without usage shows what it has', (tester) async {
      await show(tester, const TurnStats(calls: 3, elapsed: Duration(seconds: 9)));
      expect(find.text('3 calls · 9s'), findsOneWidget);
    });

    testWidgets('in English', (tester) async {
      await show(
        tester,
        const TurnStats(
          calls: 2,
          promptTokens: 1200,
          completionTokens: 300,
          elapsed: Duration(seconds: 65),
        ),
        locale: const Locale('en'),
      );
      expect(find.text('in 1.2k · out 300 · 2 calls · 1m05s'), findsOneWidget);
    });

    testWidgets('no stats, no line', (tester) async {
      await show(tester, null);
      expect(find.byKey(const ValueKey('usage-line')), findsNothing);
    });
  });

  // Conversations saved before R13 / v0.10.7 still open.
  group('older sessions', () {
    testWidgets('the investigation verdict and its coverage line',
        (tester) async {
      await _pump(
        tester,
        _answer('[INVESTIGATION_VERDICT: culprit=unresolved | confidence=0 | '
            'basis=insufficient_evidence]\n证据不足。\n\n'
            'Coverage: read=1 | mapped=1 | skipped=0'),
        phone: false,
        scroll: false,
      );
      expect(find.textContaining('部分作答'), findsOneWidget);
      expect(find.textContaining('精读=1'), findsOneWidget);
      expect(find.textContaining('INVESTIGATION_VERDICT'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a fact-check verdict with GameData evidence, large text',
        (tester) async {
      final message = ChatMessage(
        id: 'answer',
        role: MessageRole.assistant,
        content: '[FACT_CHECK_VERDICT:supported]\n## 核查结论\nGameData 支持该说法。',
        factCheckVerdict: FactCheckVerdict.supported,
        steps: const [
          ReActStep(
            type: ReActEventType.toolObservation,
            content: '=== Result #1 ===\nSource Kind: GameData\n'
                'Retrieval Type: structured_entity\n'
                'Ranking Reason: exact entity match\n'
                'Content Type: operator_profile\n'
                'Title: 阿米娅\nSection: 档案资料\n'
                'Source Path: character_table.json\nRaw ID: char_002_amiya\n'
                'Trust: GameData / game original text (highest).\n'
                'Content Excerpt:\n罗德岛公开领袖。',
          ),
        ],
        timestamp: DateTime(2026),
      );
      await _pump(tester, message, textScale: 2, settle: false);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('支持'), findsOneWidget);
      expect(find.text('GameData 证据（1）'), findsOneWidget);

      await tester.tap(find.text('GameData 证据（1）'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.textContaining('character_table.json'), findsOneWidget);
      expect(find.text('直接候选证据'), findsNothing);
      expect(find.text('检索上下文'), findsOneWidget);
      expect(find.textContaining('exact entity match'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('work timeline', () {
    testWidgets('the steps read as what was searched and read, with what '
        'they found; raw output on tap', (tester) async {
      final message = ChatMessage(
        id: 'a',
        role: MessageRole.assistant,
        content: _answered('回答正文。'),
        timestamp: DateTime(2026),
        steps: const [
          ReActStep(type: ReActEventType.thought, content: '先找故事集。'),
          ReActStep(
            type: ReActEventType.toolCall,
            content: 'Executing tool "grep"',
            toolName: 'grep',
            toolArgs: {'pattern': '甲|乙', 'collection': 'act_fixture'},
          ),
          ReActStep(
            type: ReActEventType.toolObservation,
            content: '## 《第一章》 $_c5（3 处）\n  L4 [甲] 你好\n'
                '## 《第二章》 $_c6（2 处）\n  L9 [乙] 再见',
            toolName: 'grep',
          ),
          ReActStep(
            type: ReActEventType.toolCall,
            content: 'Executing tool "read_story"',
            toolName: 'read_story',
            toolArgs: {'story_id': _c5, 'start': 0},
          ),
          ReActStep(
            type: ReActEventType.toolObservation,
            content: '【第一章】 $_c5\nL0 [甲] 一\nL1 [乙] 二\nL40 [甲] 三',
            toolName: 'read_story',
          ),
        ],
      );
      await _pump(tester, message);
      expect(find.text('已作答 · 查阅 2 次 · 读了 1 篇原文'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('answer-header')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('work-timeline')), findsOneWidget);
      expect(find.text('先找故事集。'), findsOneWidget);
      expect(find.text('在「act_fixture」中搜索「甲 / 乙」'), findsOneWidget);
      expect(find.text('5 处 · 2 篇'), findsOneWidget);
      expect(find.text('阅读《第一章》'), findsOneWidget);
      expect(find.text('第 0–40 行'), findsOneWidget);
      expect(find.textContaining('Observation'), findsNothing);
      expect(find.textContaining('Executing tool'), findsNothing);

      expect(find.byKey(const ValueKey('work-raw-1')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('work-step-1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('work-raw-1')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}