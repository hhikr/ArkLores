import 'package:arklores/core/agent/agent_provider.dart';
import 'package:arklores/core/agent/chat_session_models.dart';
import 'package:arklores/core/agent/chat_session_store.dart';
import 'package:arklores/core/llm/llm_client.dart';
import 'package:arklores/features/ai/chat_history_page.dart';
import 'package:arklores/main.dart';
import 'package:arklores/shared/l10n/generated/app_localizations.dart';
import 'package:arklores/shared/providers/settings_provider.dart';
import 'package:arklores/shared/providers/theme_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late _FakeChatSessionStore store;

  setUp(() {
    store = _FakeChatSessionStore();
  });

  Future<void> saveSampleSessions() async {
    final base = DateTime(2026, 8, 24, 9, 0);
    await store.save(ChatSessionFile(
      sessionId: 's1',
      createdAt: base,
      updatedAt: base.add(const Duration(minutes: 5)),
      title: '特蕾西娅之死',
      turns: [
        ChatSessionTurn(
          turn: 1,
          timestamp: base,
          query: '特蕾西娅之死是谁造成的？',
          model: 'm',
          baseUrl: 'b',
          iterations: [
            ReActIterationRecord(
              iteration: 1,
              rawResponse: 'Thought: 调查。',
              thought: '调查。',
              action: 'search_local_lore',
              actionInput: '{"query": "特蕾西娅"}',
              tool: 'search_local_lore',
              toolArgs: const {'query': '特蕾西娅'},
              observation: '=== Result #1 ===\n原文',
            ),
          ],
          answer: '博士是下手者。',
          status: ChatTurnStatus.completed,
        ),
      ],
    ),);
    await store.save(ChatSessionFile(
      sessionId: 's2',
      createdAt: base.add(const Duration(minutes: 10)),
      updatedAt: base.add(const Duration(minutes: 12)),
      title: '阿米娅是谁',
      turns: [
        ChatSessionTurn(
          turn: 1,
          timestamp: base.add(const Duration(minutes: 10)),
          query: '阿米娅是谁',
          model: 'm',
          baseUrl: 'b',
          answer: '她是罗德岛的公开领袖。',
          status: ChatTurnStatus.completed,
        ),
      ],
    ),);
  }

  Widget testApp() {
    return ProviderScope(
      overrides: [
        chatSessionStoreProvider.overrideWithValue(store),
        initialApiConfigProvider.overrideWithValue(
          const LLMConfig(chatApiKey: 'test-key'),
        ),
      ],
      child: Consumer(
        builder: (context, ref, _) {
          final tokens = ref.watch(themeProvider);
          return MaterialApp(
            theme: buildAppTheme(tokens),
            darkTheme: buildAppTheme(tokens),
            themeMode: tokens.isDark ? ThemeMode.dark : ThemeMode.light,
            locale: const Locale('zh'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const ChatHistoryPage(),
                      ),
                    ),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> openHistory(WidgetTester tester) async {
    await tester.pumpWidget(testApp());
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('empty state is shown without sessions', (tester) async {
    await openHistory(tester);
    expect(find.text('对话记录'), findsOneWidget);
    expect(find.textContaining('暂无对话记录'), findsOneWidget);
  });

  testWidgets('history list shows sessions newest first', (tester) async {
    await saveSampleSessions();
    await openHistory(tester);
    expect(find.text('特蕾西娅之死'), findsOneWidget);
    expect(find.text('阿米娅是谁'), findsOneWidget);
    expect(find.textContaining('1 轮对话'), findsNWidgets(2));
    // The answer modes are gone: the subtitle is the time and the turn count.
    expect(find.textContaining('investigate'), findsNothing);
  });

  ProviderContainer containerOf(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(Scaffold).first));

  // A row has one action, delete: no menu, no read-only view.
  testWidgets('a row has a delete button and no menu', (tester) async {
    await saveSampleSessions();
    await openHistory(tester);
    expect(find.byIcon(Icons.more_vert_sharp), findsNothing);
    expect(find.byKey(const ValueKey('chat-history-delete-s1')), findsOneWidget);
    expect(find.byKey(const ValueKey('chat-history-delete-s2')), findsOneWidget);
    // Nothing is the current conversation yet.
    expect(find.byKey(const ValueKey('chat-history-current')), findsNothing);
  });

  testWidgets('tapping a conversation makes it the current one and pops back',
      (tester) async {
    await saveSampleSessions();
    await openHistory(tester);

    await tester.tap(find.text('特蕾西娅之死'));
    await tester.pumpAndSettle();

    expect(find.byType(ChatHistoryPage), findsNothing);
    final container = containerOf(tester);
    final messages = container.read(askChatProvider);
    expect(messages, hasLength(2));
    expect(messages[0].content, '特蕾西娅之死是谁造成的？');
    expect(messages[1].content, '博士是下手者。');
    expect(container.read(askChatProvider.notifier).currentSessionId, 's1');

    // Back in the list it is the marked one; the other is still there.
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final current = find.byKey(const ValueKey('chat-history-current'));
    expect(current, findsOneWidget);
    expect(
      find.descendant(of: current, matching: find.text('特蕾西娅之死')),
      findsOneWidget,
    );
    expect(find.textContaining('当前对话'), findsOneWidget);

    // Opening another one switches; the first stays in its file.
    await tester.tap(find.text('阿米娅是谁'));
    await tester.pumpAndSettle();
    expect(container.read(askChatProvider.notifier).currentSessionId, 's2');
    expect(container.read(askChatProvider).first.content, '阿米娅是谁');
    expect(store.sessions.keys, containsAll(['s1', 's2']));
  });

  testWidgets('delete removes the session after confirmation', (tester) async {
    await saveSampleSessions();
    await openHistory(tester);

    await tester.tap(find.byKey(const ValueKey('chat-history-delete-s1')));
    await tester.pumpAndSettle();
    expect(find.textContaining('此操作不可撤销'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('chat-history-delete-confirm')));
    await tester.pumpAndSettle();

    expect(find.text('特蕾西娅之死'), findsNothing);
    expect(find.text('阿米娅是谁'), findsOneWidget);
    expect(store.sessions, hasLength(1));
  });

  testWidgets('deleting the current conversation clears the chat',
      (tester) async {
    await saveSampleSessions();
    await openHistory(tester);
    await tester.tap(find.text('阿米娅是谁'));
    await tester.pumpAndSettle();
    final container = containerOf(tester);
    expect(container.read(askChatProvider), isNotEmpty);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('chat-history-delete-s2')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('chat-history-delete-confirm')));
    await tester.pumpAndSettle();

    expect(container.read(askChatProvider), isEmpty);
    expect(container.read(askChatProvider.notifier).currentSessionId, isNull);
    expect(find.byKey(const ValueKey('chat-history-current')), findsNothing);
    expect(store.sessions.keys, ['s1']);
  });

  // No cap on the number of conversations: the list is paged like the
  // reading history, with the same page boxes and page-number prompt.
  testWidgets('a long history is paged and a page can be jumped to',
      (tester) async {
    final base = DateTime(2026, 8, 1);
    for (var i = 1; i <= 70; i++) {
      await store.save(ChatSessionFile(
        sessionId: 'n$i',
        createdAt: base.add(Duration(hours: i)),
        updatedAt: base.add(Duration(hours: i)),
        title: '对话 $i',
      ),);
    }
    await openHistory(tester);

    expect(find.byKey(const ValueKey('chat-history-pager-top')), findsOneWidget);
    expect(find.text('对话 70'), findsOneWidget);
    expect(find.text('对话 55'), findsNothing);
    expect(find.textContaining('第 1 / 5 页'), findsWidgets);

    await tester.tap(find.byKey(const ValueKey('chat-history-page-box-2')).first);
    await tester.pumpAndSettle();
    expect(find.text('对话 55'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('chat-history-jump')).first);
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('chat-history-jump-field')), '5',);
    await tester.tap(find.byKey(const ValueKey('chat-history-jump-go')));
    await tester.pumpAndSettle();
    // The last page: the ten oldest.
    expect(find.text('对话 10'), findsOneWidget);
    expect(find.text('对话 11'), findsNothing);
  });
}

/// In-memory store: widget tests run under FakeAsync where real file IO never
/// completes, so every store method resolves immediately.
class _FakeChatSessionStore extends ChatSessionStore {
  final Map<String, ChatSessionFile> sessions = {};

  @override
  Future<void> save(ChatSessionFile session) async {
    sessions[session.sessionId] = session;
  }

  @override
  Future<ChatSessionFile?> load(String sessionId) async => sessions[sessionId];

  @override
  Future<List<ChatSessionSummary>> list() async {
    final summaries = [
      for (final session in sessions.values)
        ChatSessionSummary(
          sessionId: session.sessionId,
          title: session.title,
          updatedAt: session.updatedAt,
          createdAt: session.createdAt,
          turnCount: session.turnCount,
          lastQuery: session.lastQuery,
        ),
    ]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return summaries;
  }

  @override
  Future<int> count() async => sessions.length;

  @override
  Future<List<ChatSessionSummary>> page(int page, int size) async =>
      (await list()).skip(page * size).take(size).toList();

  @override
  Future<bool> delete(String sessionId) async {
    return sessions.remove(sessionId) != null;
  }
}
