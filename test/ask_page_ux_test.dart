// R17d: reading at one's own pace — the Ask list never follows a streaming
// answer, the question box grows and keeps the keyboard, the accent text is readable.
import 'dart:math' as math;

import 'package:arklores/core/agent/agent_provider.dart';
import 'package:arklores/core/llm/llm_client.dart';
import 'package:arklores/core/llm/llm_provider.dart';
import 'package:arklores/features/ai/ai_chat_page.dart';
import 'package:arklores/features/ai/widgets/ask_composer.dart';
import 'package:arklores/shared/l10n/generated/app_localizations.dart';
import 'package:arklores/shared/providers/settings_provider.dart';
import 'package:arklores/shared/theme/app_theme.dart';
import 'package:arklores/shared/theme/ark_theme_tokens.dart';
import 'package:arklores/shared/theme/endfield_theme_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(Widget home, {List<Override> overrides = const []}) =>
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: home,
      ),
    );

/// A streaming answer shows a spinner, so the tree never settles; pump
/// long enough for scroll animations and flings to finish.
Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  group('Ask list scrolling', () {
    final longAnswer = [for (var i = 0; i < 120; i++) '第 $i 段答案。'].join('\n\n');

    ChatMessage answer(String content) => ChatMessage(
          id: 'a',
          role: MessageRole.assistant,
          content: content,
          isStreaming: true,
          liveStatus: '正在撰写答案',
          timestamp: DateTime(2026),
        );

    testWidgets(
        'a new question scrolls to the end once; streamed text never moves '
        'the view; the ↓ button brings the end back', (tester) async {
      await tester.pumpWidget(_app(
        const AiChatPage(),
        overrides: [
          initialApiConfigProvider.overrideWithValue(
            const LLMConfig(chatApiKey: 'test-key'),
          ),
          llmClientProvider.overrideWith((ref, level) => _SilentLLMClient()),
        ],
      ),);
      await tester.pumpAndSettle();
      final container =
          ProviderScope.containerOf(tester.element(find.byType(AiChatPage)));
      final chat = container.read(askChatProvider.notifier);

      ChatMessage question(String id) => ChatMessage(
            id: id,
            role: MessageRole.user,
            content: '问题',
            timestamp: DateTime(2026),
          );
      // ignore: invalid_use_of_protected_member
      chat.state = [question('q'), answer('开始')];
      await settle(tester);
      final position = tester
          .state<ScrollableState>(find.descendant(
            of: find.byKey(const ValueKey('ask-chat-list')),
            matching: find.byType(Scrollable),
          ).first,)
          .position;
      expect(position.pixels, 0);

      // The answer streams in far past the screen: the view does not follow.
      chat.updateMessage('a', content: longAnswer);
      await settle(tester);
      expect(position.pixels, 0);
      expect(position.maxScrollExtent, greaterThan(1000));
      expect(find.byKey(const ValueKey('scroll-to-bottom')), findsOneWidget);

      // Scrolled into the middle, more text arrives: still put.
      await tester.drag(
        find.byKey(const ValueKey('ask-chat-list')),
        const Offset(0, -600),
      );
      await settle(tester);
      final readingAt = position.pixels;
      expect(readingAt, greaterThan(0));
      chat.updateMessage('a', content: '$longAnswer\n\n再来三段。\n\n二。\n\n三。');
      await settle(tester);
      expect(position.pixels, readingAt);

      // ↓ goes to the end and hides itself.
      await tester.tap(find.byKey(const ValueKey('scroll-to-bottom')));
      await settle(tester);
      expect(position.pixels, position.maxScrollExtent);
      expect(find.byKey(const ValueKey('scroll-to-bottom')), findsNothing);

      // At the end, more text arrives: still no following.
      final atEnd = position.pixels;
      chat.updateMessage('a', content: '$longAnswer\n\n再来。\n\n二。\n\n三。\n\n四。');
      await settle(tester);
      expect(position.pixels, atEnd);
      expect(position.maxScrollExtent, greaterThan(atEnd));

      // A new question scrolls to the end once.
      // ignore: invalid_use_of_protected_member
      chat.state = [...chat.state, question('q2')];
      await settle(tester);
      expect(position.pixels, position.maxScrollExtent);
      expect(tester.takeException(), isNull);
    });
  });

  group('Ask composer', () {
    const tabHeight = 600.0;
    var sends = 0;
    late TextEditingController controller;

    Future<void> pumpComposer(
      WidgetTester tester, {
      bool isSending = false,
    }) async {
      await tester.pumpWidget(_app(
        Scaffold(
          body: Column(
            children: [
              const Expanded(child: SizedBox.shrink()),
              AskComposer(
                controller: controller,
                theme: EndfieldThemeTokens(),
                isSending: isSending,
                onSend: () => sends++,
                hintText: '问点什么',
                maxHeight: tabHeight,
              ),
            ],
          ),
        ),
      ),);
      await tester.pump();
    }

    double barHeight(WidgetTester tester) =>
        tester.getSize(find.byKey(const ValueKey('ask-input-bar'))).height;

    setUp(() {
      sends = 0;
      controller = TextEditingController();
    });
    tearDown(() => controller.dispose());

    testWidgets('grows with the text up to four lines, then stops',
        (tester) async {
      await pumpComposer(tester);
      final one = barHeight(tester);
      expect(find.byKey(const ValueKey('ask-input-expand-toggle')), findsOneWidget);
      // The expand button is hidden (transparent, not hit-testable) for a
      // short text.
      controller.text = '一\n二';
      await tester.pumpAndSettle();
      final two = barHeight(tester);
      expect(two, greaterThan(one));
      controller.text = '一\n二\n三\n四';
      await tester.pumpAndSettle();
      final four = barHeight(tester);
      controller.text = '一\n二\n三\n四\n五\n六\n七';
      await tester.pumpAndSettle();
      expect(barHeight(tester), four, reason: 'capped at four lines');
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'opens to half and to the full tab; the draft and the focus stay',
        (tester) async {
      await pumpComposer(tester);
      await tester.tap(find.byKey(const ValueKey('ask-input-field')));
      await tester.enterText(
        find.byKey(const ValueKey('ask-input-field')),
        '一\n二\n三\n四',
      );
      await tester.pumpAndSettle();
      final focusNode = tester
          .widget<TextField>(find.byKey(const ValueKey('ask-input-field')))
          .focusNode!;
      expect(focusNode.hasFocus, isTrue);

      await tester.tap(find.byKey(const ValueKey('ask-input-expand-toggle')));
      await tester.pumpAndSettle();
      expect(barHeight(tester), closeTo((tabHeight - 15) * 0.5, 1));
      expect(controller.text, '一\n二\n三\n四');
      expect(focusNode.hasFocus, isTrue);

      await tester.tap(find.byKey(const ValueKey('ask-input-fullscreen-toggle')));
      await tester.pumpAndSettle();
      expect(barHeight(tester), closeTo(tabHeight - 15, 1));
      expect(focusNode.hasFocus, isTrue);

      await tester.tap(find.byKey(const ValueKey('ask-input-fullscreen-toggle')));
      await tester.pumpAndSettle();
      expect(barHeight(tester), closeTo((tabHeight - 15) * 0.5, 1));

      await tester.tap(find.byKey(const ValueKey('ask-input-expand-toggle')));
      await tester.pumpAndSettle();
      expect(barHeight(tester), lessThan((tabHeight - 15) * 0.5));
      expect(controller.text, '一\n二\n三\n四');
      expect(tester.takeException(), isNull);
    });

    testWidgets('the keyboard key sends when collapsed, writes a line when open',
        (tester) async {
      await pumpComposer(tester);
      await tester.tap(find.byKey(const ValueKey('ask-input-field')));
      await tester.enterText(
        find.byKey(const ValueKey('ask-input-field')),
        '问题',
      );
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pump();
      expect(sends, 1);

      // Open up (the toggle shows from three lines on, or when open).
      controller.text = '一\n二\n三';
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('ask-input-expand-toggle')));
      await tester.pumpAndSettle();
      final field =
          tester.widget<TextField>(find.byKey(const ValueKey('ask-input-field')));
      expect(field.textInputAction, TextInputAction.newline);
    });

    testWidgets('sending gives the room back', (tester) async {
      controller.text = '一\n二\n三';
      await pumpComposer(tester);
      await tester.tap(find.byKey(const ValueKey('ask-input-expand-toggle')));
      await tester.pumpAndSettle();
      final open = barHeight(tester);
      await pumpComposer(tester, isSending: true);
      await tester.pumpAndSettle();
      expect(barHeight(tester), lessThan(open));
      // The send button became a cancel button.
      expect(find.byTooltip('取消'), findsOneWidget);
    });
  });
  group('accent text contrast', () {
    double luminance(Color c) => c.computeLuminance();
    double contrast(Color a, Color b) {
      final la = luminance(a);
      final lb = luminance(b);
      return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
    }

    for (final AppThemeTokens theme in [EndfieldThemeTokens(), ArkThemeTokens()]) {
      test('${theme.themeName}: accentText is readable on its surfaces', () {
        for (final surface in [
          theme.bgPrimary,
          theme.bgSecondary,
          theme.cardSurface,
        ]) {
          expect(contrast(theme.accentText, surface), greaterThanOrEqualTo(4.5));
        }
        expect(
          contrast(theme.onAccent, theme.accentPrimary),
          greaterThanOrEqualTo(4.5),
        );
      });
    }
  });
}

class _SilentLLMClient extends LLMClient {
  @override
  Future<String> chat(
    List<Message> messages, {
    List<Map<String, dynamic>>? tools,
    double temperature = 0.7,
    int maxTokens = 2048,
    List<String>? stop,
  }) async {
    return 'Final Answer: silent';
  }
}
