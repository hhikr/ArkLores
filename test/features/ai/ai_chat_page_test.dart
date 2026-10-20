// The AI page: floating actions and empty state, cancel and retry, the
// focus after returning from a page, a Wiki context handed over, and (R17d)
// a list that never follows a streaming answer.
import 'dart:async';

import 'package:arklores/core/agent/agent_provider.dart';
import 'package:arklores/core/agent/answer_options.dart';
import 'package:arklores/core/llm/llm_client.dart';
import 'package:arklores/core/llm/llm_provider.dart';
import 'package:arklores/features/ai/ai_chat_page.dart';
import 'package:arklores/features/settings/settings_service.dart';
import 'package:arklores/shared/l10n/generated/app_localizations.dart';
import 'package:arklores/shared/providers/settings_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_llm.dart';

List<Override> _withModel(LLMClient model) => [
      initialApiConfigProvider.overrideWithValue(
        const LLMConfig(chatApiKey: 'test-key'),
      ),
      llmClientProvider.overrideWith((ref, level) => model),
    ];

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
  testWidgets('no app bar: the actions float; Ask starts empty with the '
      'question box', (tester) async {
    await tester.pumpWidget(
        _app(const AiChatPage(), overrides: _withModel(ScriptedLLM(['x']))),);
    await tester.pumpAndSettle();
    // The actions float over the conversation; the box (answer options,
    // send) sits at the bottom. No tabs, no answer modes.
    expect(find.byType(AppBar), findsNothing);
    expect(find.byType(TabBar), findsNothing);
    expect(find.byKey(const ValueKey('ask-floating-actions')), findsOneWidget);
    // The conversations, not the reading history (that is on the library page).
    expect(find.byKey(const ValueKey('ask-chat-history')), findsOneWidget);
    expect(find.byIcon(Icons.menu_book_outlined), findsNothing);
    expect(find.byType(BackButton), findsNothing);
    expect(find.text('AI 问答'), findsOneWidget); // the empty-state title
    expect(find.byTooltip('回答方式'), findsNothing);
    expect(find.textContaining('直接问任何剧情问题'), findsOneWidget);
    expect(find.byKey(const ValueKey('ask-input-field')), findsOneWidget);
    // 0.14: one options button; "深度思考" is a row of its panel.
    expect(find.byKey(const ValueKey('deep-thinking-toggle')), findsNothing);
    expect(find.byKey(const ValueKey('answer-options')), findsOneWidget);
    expect(find.byTooltip('发送'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // 0.14: the options open upward from their button as a panel beside the
  // box (not a route), and nothing in it takes focus: the keyboard stays.
  testWidgets('the answer options open above the box without taking the '
      'focus; the wikis and the sub-agents are switched there and saved',
      (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    await tester.pumpWidget(
        _app(const AiChatPage(), overrides: _withModel(ScriptedLLM(['x']))),);
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(AiChatPage)),
    );
    expect(container.read(answerOptionsProvider), const AnswerOptions());
    final box = find.descendant(
      of: find.byKey(const ValueKey('ask-input-field')),
      matching: find.byType(EditableText),
    );
    await tester.tap(box);
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('answer-options')));
    await tester.pumpAndSettle();
    final panel = find.byKey(const ValueKey('answer-options-panel'));
    expect(panel, findsOneWidget);
    expect(tester.widget<EditableText>(box).focusNode.hasFocus, isTrue);
    // Above the whole box (the text being typed stays in view), within the
    // screen.
    final card = tester.getRect(find.byKey(const ValueKey('ask-input-bar')));
    final rect = tester.getRect(panel);
    expect(rect.bottom, lessThanOrEqualTo(card.top));
    expect(rect.top, greaterThanOrEqualTo(0));
    expect(rect.height, lessThan(200));
    // The digest and the review are not options of a question any more.
    for (final title in ['Wiki 资料', '子助手', '深度思考']) {
      expect(find.text(title), findsOneWidget);
    }
    expect(find.text('复核'), findsNothing);
    expect(find.text('提要'), findsNothing);

    // The panel stays open while its rows are switched.
    await tester.tap(find.byKey(const ValueKey('answer-option-wiki')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('answer-option-delegate')));
    await tester.pumpAndSettle();
    const changed = AnswerOptions(wiki: false, delegate: true);
    expect(container.read(answerOptionsProvider), changed);
    expect(await SettingsService().loadAnswerOptions(), changed);
    expect(container.read(deepThinkingProvider), isFalse);
    await tester.tap(find.byKey(const ValueKey('answer-option-think')));
    await tester.pumpAndSettle();
    expect(container.read(deepThinkingProvider), isTrue);
    expect(tester.widget<EditableText>(box).focusNode.hasFocus, isTrue);

    // A touch elsewhere closes it.
    await tester.tapAt(const Offset(20, 200));
    await tester.pumpAndSettle();
    expect(panel, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a model service without a known switch for thinking is not '
      'offered "深度思考"', (tester) async {
    await tester.pumpWidget(_app(
      const AiChatPage(),
      overrides: [
        initialApiConfigProvider.overrideWithValue(
          const LLMConfig(
            chatApiKey: 'test-key',
            chatBaseUrl: 'https://llm.example.com/v1',
            chatModel: 'some-model',
          ),
        ),
        llmClientProvider.overrideWith((ref, level) => ScriptedLLM(['x'])),
      ],
    ),);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('answer-options')));
    await tester.pumpAndSettle();
    expect(find.text('Wiki 资料'), findsOneWidget);
    expect(find.text('深度思考'), findsNothing);
  });

  testWidgets('without an embedding service the empty page warns that '
      'answers may suffer', (tester) async {
    await tester.pumpWidget(
        _app(const AiChatPage(), overrides: _withModel(ScriptedLLM(['x']))),);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('ask-no-vector-warning')), findsOneWidget);
    expect(find.textContaining('问答质量可能下降'), findsOneWidget);
  });
  testWidgets('a question can be cancelled, then retried from the menu',
      (tester) async {
    await tester
        .pumpWidget(_app(const AiChatPage(), overrides: _withModel(_Pending())));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '甲是谁');
    await tester.tap(find.byTooltip('发送'));
    await tester.pump();
    expect(find.byTooltip('取消'), findsOneWidget);
    await tester.tap(find.byTooltip('取消'));
    await tester.pump();
    expect(find.text('已取消本次回答。'), findsOneWidget);
    // Retry sits in the floating actions' menu.
    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    expect(find.text('重试'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('back from a page opened in the conversation, the focus is on '
      'the conversation, not the question box', (tester) async {
    await tester.pumpWidget(
        _app(const AiChatPage(), overrides: _withModel(ScriptedLLM(['x']))),);
    await tester.pumpAndSettle();
    final container =
        ProviderScope.containerOf(tester.element(find.byType(AiChatPage)));
    // ignore: invalid_use_of_protected_member
    container.read(askChatProvider.notifier).state = [
      ChatMessage(
        id: 'q',
        role: MessageRole.user,
        content: '问题',
        timestamp: DateTime(2026),
      ),
      ChatMessage(
        id: 'a',
        role: MessageRole.assistant,
        content: '回答。',
        timestamp: DateTime(2026),
      ),
    ];
    await tester.pumpAndSettle();
    final box = find.descendant(
      of: find.byKey(const ValueKey('ask-input-field')),
      matching: find.byType(EditableText),
    );
    bool boxFocused() =>
        tester.widget<EditableText>(box).focusNode.hasFocus;

    await tester.tap(box);
    await tester.pump();
    expect(boxFocused(), isTrue);
    // Touching the conversation (e.g. a source) and opening a page from it.
    await tester.tap(find.text('回答。'));
    await tester.pump();
    expect(boxFocused(), isFalse);
    Navigator.of(tester.element(find.text('回答。'))).push(
      MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('原文'))),
    );
    await tester.pumpAndSettle();
    Navigator.of(tester.element(find.text('原文'))).pop();
    await tester.pumpAndSettle();
    expect(boxFocused(), isFalse);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'ask-chat');
    expect(tester.takeException(), isNull);
  });

  testWidgets('opened from a Wiki page, the page has a way back',
      (tester) async {
    await tester.pumpWidget(_app(
      Builder(
        builder: (context) => TextButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const AiChatPage()),
          ),
          child: const Text('打开'),
        ),
      ),
      overrides: _withModel(ScriptedLLM(['x'])),
    ),);
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    expect(find.byType(BackButton), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byType(AiChatPage), findsNothing);
  });

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
      await tester.pumpWidget(_app(const AiChatPage(),
          overrides: _withModel(ScriptedLLM(['Final Answer: silent'])),),);
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
}

/// A model that never answers.
class _Pending extends LLMClient {
  @override
  Future<String> chat(
    List<Message> messages, {
    List<Map<String, dynamic>>? tools,
    double temperature = 0.7,
    int maxTokens = 2048,
    List<String>? stop,
  }) =>
      Completer<String>().future;
}
