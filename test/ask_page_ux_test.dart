// R17d: reading at one's own pace — the Ask list never follows a streaming
// answer, the mode panel keeps the keyboard, the accent text is readable.
import 'dart:math' as math;

import 'package:arklores/core/agent/agent_provider.dart';
import 'package:arklores/core/agent/question_router.dart';
import 'package:arklores/core/llm/llm_client.dart';
import 'package:arklores/core/llm/llm_provider.dart';
import 'package:arklores/features/ai/ai_chat_page.dart';
import 'package:arklores/features/ai/widgets/ask_mode_picker.dart';
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

  group('Ask mode panel', () {
    Future<(FocusNode, ProviderContainer)> pumpPicker(
      WidgetTester tester,
    ) async {
      final focus = FocusNode();
      addTearDown(focus.dispose);
      await tester.pumpWidget(_app(
        Scaffold(
          body: Column(
            children: [
              const Spacer(),
              Row(
                children: [
                  const AskModePicker(),
                  Expanded(child: TextField(focusNode: focus)),
                ],
              ),
            ],
          ),
        ),
      ),);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(AskModePicker)),
      );
      return (focus, container);
    }

    testWidgets(
        'slides up above the button, keeps the text field focused and '
        'sets the mode', (tester) async {
      final (focus, container) = await pumpPicker(tester);
      await tester.tap(find.byType(TextField));
      await tester.pump();
      expect(focus.hasFocus, isTrue);

      await tester.tap(find.byKey(const ValueKey('ask-mode-menu')));
      await tester.pumpAndSettle();
      final panel = find.byKey(const ValueKey('ask-mode-panel'));
      expect(panel, findsOneWidget);
      for (final mode in AiMode.values) {
        expect(find.byKey(ValueKey('ask-mode-${mode.name}')), findsOneWidget);
      }
      // Above the button.
      expect(
        tester.getBottomLeft(panel).dy,
        lessThanOrEqualTo(
          tester.getTopLeft(find.byKey(const ValueKey('ask-mode-menu'))).dy,
        ),
      );
      expect(focus.hasFocus, isTrue);

      await tester.tap(find.byKey(const ValueKey('ask-mode-summarize')));
      await tester.pumpAndSettle();
      expect(container.read(aiModeProvider), AiMode.summarize);
      expect(panel, findsNothing);
      expect(focus.hasFocus, isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('closes on a tap outside without changing the mode',
        (tester) async {
      final (_, container) = await pumpPicker(tester);
      await tester.tap(find.byKey(const ValueKey('ask-mode-menu')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('ask-mode-panel')), findsOneWidget);
      await tester.tapAt(const Offset(400, 40));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('ask-mode-panel')), findsNothing);
      expect(container.read(aiModeProvider), AiMode.auto);
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
