import 'package:arklores/core/library/portrait_provider.dart';
import 'package:arklores/features/ai/widgets/answer_reveal.dart';
import 'package:arklores/features/ai/widgets/story_answer_body.dart';
import 'package:arklores/shared/l10n/generated/app_localizations.dart';
import 'package:arklores/shared/providers/theme_provider.dart';
import 'package:arklores/shared/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/screenshot.dart';

final _eligibleNames = StateProvider<List<String>>((ref) => const ['林舟', '洛青']);

Future<void> show(
  WidgetTester tester,
  String content, {
  bool streaming = true,
  bool reduced = false,
  bool immediate = false,
  bool light = true,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        highlightNamesProvider
            .overrideWith((ref) async => ref.watch(_eligibleNames)),
        initialThemeProvider
            .overrideWithValue(light ? AppTheme.endfield : AppTheme.ark),
      ],
      child: MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Consumer(
          builder: (context, ref, _) {
            final theme = ref.watch(themeProvider);
            return MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
              child: Shot(
                child: ColoredBox(
                  color: theme.bgPrimary,
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Align(
                        alignment: Alignment.topLeft,
                        child: SizedBox(
                          width: 344,
                          child: StoryAnswerBody(
                            content: content,
                            streaming: streaming,
                            revealImmediately: immediate,
                            styleSheet: MarkdownStyleSheet(
                              p: theme
                                  .text(18, height: 1.6)
                                  .copyWith(fontFamily: 'NotoSansSC'),
                              h2: theme.heading(22),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  setUpAll(() async {
    for (final font in ['Saira', 'NotoSansSC']) {
      await (FontLoader(font)
            ..addFont(rootBundle.load('assets/fonts/$font.ttf')))
          .load();
    }
  });

  testWidgets('completion, streaming links and stable height each frame',
      (tester) async {
    const first = '林舟带着洛青沿着河岸前行，寻找旧城留下的线索。';
    await show(tester, first);
    expect(find.byType(MarkdownBody), findsNothing);
    await show(tester, '$first\n\n林舟继续');
    expect(find.byType(MarkdownBody), findsOneWidget);
    final markdown = tester.widget<MarkdownBody>(find.byType(MarkdownBody));
    expect(markdown.data, contains('arklores-speaker:'));
    final reveal = tester.widget<AnswerReveal>(find.byType(AnswerReveal));
    expect(reveal.queue.value(reveal.id), lessThan(1));
    final size = tester.getSize(find.byType(AnswerReveal));
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.getSize(find.byType(AnswerReveal)), size);
    }
    await show(tester, '$first\n\n林舟继续', streaming: false);
    expect(find.byType(MarkdownBody), findsNWidgets(2));
    expect(
      tester.widgetList<MarkdownBody>(find.byType(MarkdownBody)).last.data,
      '林舟继续',
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('120 chars per second, queue double speed, end triple speed',
      (tester) async {
    final paragraph = '字' * 120;
    expect(answerRevealDuration(120), const Duration(seconds: 1));
    expect(answerRevealDuration(1000), const Duration(milliseconds: 1200));
    await show(tester, '正在写');
    await show(tester, '$paragraph\n\n后文');
    var reveal = tester.widget<AnswerReveal>(find.byType(AnswerReveal));
    await tester.pump(const Duration(milliseconds: 500));
    expect(reveal.queue.value(reveal.id), closeTo(0.5, 0.02));
    await show(tester, '$paragraph\n\n后文', streaming: false);
    await tester.pump(const Duration(milliseconds: 100));
    expect(reveal.queue.value(reveal.id), closeTo(0.8, 0.02));
    await tester.pumpAndSettle();
    await show(tester, '新的流');
    await show(tester, '$paragraph\n\n$paragraph乙\n\n$paragraph丙\n\n末段');
    reveal = tester.widgetList<AnswerReveal>(find.byType(AnswerReveal)).first;
    await tester.pump(const Duration(milliseconds: 250));
    expect(reveal.queue.value(reveal.id), closeTo(0.5, 0.02));
    await tester.pumpAndSettle();
  });

  testWidgets(
      'history, reopened details, reduced motion and stop show immediately',
      (tester) async {
    await show(tester, '历史段落', streaming: false);
    var reveal = tester.widget<AnswerReveal>(find.byType(AnswerReveal));
    expect(reveal.queue.value(reveal.id), 1);
    await show(tester, '新答案');
    await show(tester, '新答案\n\n后文', reduced: true);
    reveal = tester.widget<AnswerReveal>(find.byType(AnswerReveal));
    expect(reveal.queue.value(reveal.id), 1);
    await show(tester, '另一答案');
    await show(tester, '另一答案\n\n末段', immediate: true, streaming: false);
    for (final r
        in tester.widgetList<AnswerReveal>(find.byType(AnswerReveal))) {
      expect(r.queue.value(r.id), 1);
    }
    await show(tester, '概括\n\n[DETAILS]\n\n已有细节', streaming: false);
    await tester.tap(find.byKey(const ValueKey('answer-details-toggle')));
    await tester.pump();
    reveal = tester.widgetList<AnswerReveal>(find.byType(AnswerReveal)).last;
    expect(reveal.queue.value(reveal.id), 1);
    await tester.pumpAndSettle();
  });

  testWidgets('changing the eligible names refreshes a completed answer',
      (tester) async {
    await show(tester, '林舟与洛青。', streaming: false);
    expect(
      tester.widget<MarkdownBody>(find.byType(MarkdownBody)).data,
      contains('arklores-speaker:'),
    );
    final container =
        ProviderScope.containerOf(tester.element(find.byType(StoryAnswerBody)));
    container.read(_eligibleNames.notifier).state = [];
    await tester.pumpAndSettle();
    expect(
      tester.widget<MarkdownBody>(find.byType(MarkdownBody)).data,
      '林舟与洛青。',
    );
  });

  testWidgets('stopping flushes an active queue and rollback drops old blocks',
      (tester) async {
    await show(tester, '正在写');
    final paragraph = '林舟继续调查。' * 20;
    final content = '$paragraph\n\n洛青核对\n\n末段';
    await show(tester, content);
    await tester.pump(const Duration(milliseconds: 100));
    final reveal =
        tester.widgetList<AnswerReveal>(find.byType(AnswerReveal)).first;
    expect(reveal.queue.value(reveal.id), inExclusiveRange(0, 1));
    await show(tester, content, streaming: false, immediate: true);
    for (final r
        in tester.widgetList<AnswerReveal>(find.byType(AnswerReveal))) {
      expect(r.queue.value(r.id), 1);
    }
    await show(tester, '重新作答');
    expect(find.byType(MarkdownBody), findsNothing);
    await show(tester, '重新作答\n\n后文');
    expect(find.byType(MarkdownBody), findsOneWidget);
    expect(tester.widget<MarkdownBody>(find.byType(MarkdownBody)).data, '重新作答');
    await tester.pumpAndSettle();
  });

  testWidgets(
      'identical paragraphs link a name only once and keep citation space',
      (tester) async {
    await show(tester, '正在写');
    const text = '林舟核对记录。';
    const cite = 'activities/fixture/level_fixture.txt:0';
    await show(tester, '$text `$cite`\n\n$text\n\n末段');
    final bodies =
        tester.widgetList<MarkdownBody>(find.byType(MarkdownBody)).toList();
    expect(bodies.first.data, contains('arklores-speaker:'));
    expect(bodies.last.data, isNot(contains('arklores-speaker:')));
    final first = find.byType(AnswerReveal).first;
    final size = tester.getSize(first);
    expect(
      tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity,
      0,
    );
    await tester.pump(const Duration(milliseconds: 30));
    expect(tester.getSize(first), size);
    await tester.pumpAndSettle();
    expect(
      tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity,
      1,
    );
    expect(tester.getSize(first), size);
  });

  testWidgets('headings, lists and the details boundary seal full blocks',
      (tester) async {
    await show(tester, '## 标题');
    await show(tester, '## 标题\n\n- 林舟检查记录\n- 洛青继续');
    final reveals =
        tester.widgetList<AnswerReveal>(find.byType(AnswerReveal)).toList();
    expect(reveals.length, 2);
    expect(reveals[0].lineHeight, isNot(reveals[1].lineHeight));
    final before = tester.getSize(find.byType(AnswerReveal).last);
    for (var frame = 0; frame < 25; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.getSize(find.byType(AnswerReveal).last), before);
    }
    await show(tester, '林舟概括。\n\n[DETAILS]\n\n未完成的细节');
    expect(find.byType(MarkdownBody), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('answer-details-toggle')));
    await tester.pump();
    expect(find.byType(MarkdownBody), findsOneWidget);
    await show(tester, '林舟概括。\n\n[DETAILS]\n\n未完成的细节\n\n尾段');
    expect(find.byType(MarkdownBody), findsNWidgets(2));
    final detail =
        tester.widgetList<AnswerReveal>(find.byType(AnswerReveal)).last;
    expect(detail.queue.value(detail.id), 1);
    await tester.pumpAndSettle();
  });

  for (final light in [true, false]) {
    testWidgets('half revealed paragraph ${light ? 'light' : 'dark'}',
        (tester) async {
      tester.view.physicalSize = const Size(784, 880);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await show(tester, '', light: light);
      const paragraph = '林舟与洛青来到河岸，在旧城留下的记录中寻找线索。'
          '他们整理沿途见闻，逐一核对曾经经过这里的人。'
          '河边的灯光渐渐亮起，远处传来新的消息，两人继续向前。';
      await show(tester, '$paragraph\n\n下一段仍在撰写', light: light);
      await tester.pump(
        Duration(
          microseconds:
              (answerRevealDuration(paragraph.runes.length).inMicroseconds *
                      0.47)
                  .round(),
        ),
      );
      await shoot(tester, 'reveal_half_${light ? 'light' : 'dark'}');
      await tester.pumpAndSettle();
    });
  }
}
