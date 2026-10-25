// The open Ask conversations (AskSessionsNotifier): which one is shown, when
// a new one is made, and which are kept. The conversations are stand-ins
// whose messages the test sets.
import 'package:arklores/core/agent/agent_provider.dart';
import 'package:arklores/core/agent/chat_session_models.dart';
import 'package:arklores/core/agent/story_qa_agent.dart';
import 'package:arklores/core/gamedata/gamedata_knowledge_store.dart';
import 'package:arklores/core/llm/llm_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/memory_chat_store.dart';

void main() {
  late MemoryChatSessionStore store;
  late ProviderContainer container;

  setUp(() {
    store = MemoryChatSessionStore();
    container = ProviderContainer(
      overrides: [
        chatSessionStoreProvider.overrideWithValue(store),
        askChatProvider.overrideWith((ref, key) => _Held()),
      ],
    );
  });
  tearDown(() => container.dispose());

  AskSessionsNotifier sessions() => container.read(askSessionsProvider.notifier);
  AskSessions state() => container.read(askSessionsProvider);
  _Held chat(String key) => sessions().chat(key) as _Held;

  test('a new conversation is made only when the shown one has messages', () {
    final first = state().shown;
    sessions().startNew();
    expect(state().shown, first);
    expect(state().open, [first]);

    chat(first).hold(answering: false);
    sessions().startNew();
    final second = state().shown;
    expect(second, isNot(first));
    expect(state().open, [second, first]);
  });

  test('showing another conversation forgets the shown one when it is empty',
      () {
    final first = state().shown;
    chat(first).hold(answering: true);
    sessions().startNew();
    final empty = state().shown;

    sessions().show(first);
    expect(state().shown, first);
    expect(state().open, [first]);
    // Showing it again, or a key that is not open, changes nothing.
    sessions().show(first);
    sessions().show(empty);
    expect(state().shown, first);
  });

  test('one answering keeps answering while another is shown, and is not '
      'closed', () {
    final first = state().shown;
    chat(first).hold(answering: true);
    sessions().startNew();
    final second = state().shown;
    expect(sessions().answering(first), isTrue);
    expect(sessions().answering(second), isFalse);

    sessions().close(first);
    expect(state().open, contains(first));

    chat(first).hold(answering: false);
    sessions().close(first);
    expect(state().open, [second]);
    expect(state().shown, second);
  });

  test('closing the shown conversation shows a new empty one', () {
    final first = state().shown;
    chat(first).hold(answering: false);
    sessions().close(first);
    expect(state().shown, isNot(first));
    expect(state().open, [state().shown]);
    expect(sessions().messagesOf(state().shown), isEmpty);
  });

  test('a saved conversation is opened once; a missing file opens nothing',
      () async {
    final at = DateTime(2026, 10, 25);
    await store.save(ChatSessionFile(
      sessionId: 's1',
      createdAt: at,
      updatedAt: at,
      title: 't',
      turns: [
        ChatSessionTurn(
          turn: 1,
          timestamp: at,
          query: 'q',
          model: 'm',
          baseUrl: 'b',
          answer: 'a',
          status: ChatTurnStatus.completed,
        ),
      ],
    ),);
    final first = state().shown;

    expect(await sessions().openSaved('s1'), isTrue);
    final opened = state().shown;
    expect(sessions().keyOf('s1'), opened);
    // The empty conversation shown before is forgotten.
    expect(state().open, [opened]);

    sessions().startNew();
    expect(await sessions().openSaved('s1'), isTrue);
    expect(state().shown, opened);
    expect(state().open, hasLength(1));

    expect(await sessions().openSaved('missing'), isFalse);
    expect(state().shown, opened);
    expect(first, isNot(opened));
  });
}

/// An Ask conversation whose messages the test sets.
class _Held extends AskChatNotifier {
  _Held()
      : super(
          agent: StoryQaAgent(
            llmClient: _NoLLM(),
            gameDataStore: GameDataKnowledgeStore(dbPath: 'unused.db'),
          ),
          configReader: () => const LLMConfig(),
        );

  /// A question and its answer, still being written when [answering].
  void hold({required bool answering}) {
    final at = DateTime(2026);
    state = [
      ChatMessage(id: 'q', role: MessageRole.user, content: 'q', timestamp: at),
      ChatMessage(
        id: 'a',
        role: MessageRole.assistant,
        content: '',
        isStreaming: answering,
        timestamp: at,
      ),
    ];
  }
}

class _NoLLM implements LLMClient {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('no model in these tests');
}
