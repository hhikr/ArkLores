import 'dart:async';
import 'dart:io';

import 'package:arklores/core/agent/agent_logger.dart';
import 'package:arklores/core/agent/agent_provider.dart';
import 'package:arklores/core/agent/answer_options.dart';
import 'package:arklores/core/agent/chat_session_models.dart';
import 'package:arklores/core/agent/chat_session_store.dart';
import 'package:arklores/core/agent/lore_agent_prompts.dart';
import 'package:arklores/core/agent/react_event.dart';
import 'package:arklores/core/agent/story_qa_agent.dart';
import 'package:arklores/core/gamedata/gamedata_knowledge_store.dart';
import 'package:arklores/core/llm/llm_client.dart';
import 'package:arklores/core/llm/usage_meter.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../support/gamedata_fixture.dart';
import '../../support/sqlite.dart';
import '../../support/temp_dir.dart';

void main() {
  late Directory tempDir;
  late ChatSessionStore store;
  late GameDataKnowledgeStore knowledge;
  late UsageMeter meter;

  setUpAll(useSqfliteFfi);

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('chat_session_recorder_test');
    store = ChatSessionStore(filePath: tempDir.path);
    meter = UsageMeter();
    final kbDir = Directory.systemTemp.createTempSync('chat_session_recorder_kb');
    addTearDown(() async {
      await knowledge.close();
      await deleteTempDir(kbDir);
    });
    knowledge = GameDataKnowledgeStore(dbPath: await _createFixtureDb(kbDir));
  });

  tearDown(() {
    AgentLogger.setEnabled(false);
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  AskChatNotifier makeNotifier(_RecorderLLM mock) {
    mock.meter = meter;
    return AskChatNotifier(
      agent: StoryQaAgent(llmClient: mock, gameDataStore: knowledge),
      usage: meter,
      sessionStore: store,
      configReader: () => const LLMConfig(
        chatModel: 'test-model',
        chatBaseUrl: 'https://example.com/v1',
      ),
      optionsReader: () => const AnswerOptions(),
    );
  }

  Future<ChatSessionFile> singleSession() async {
    final summaries = await store.list();
    expect(summaries, hasLength(1));
    return (await store.load(summaries.single.sessionId))!;
  }

  group('session recording', () {
    test('a turn records its question, raw responses and what it cost',
        () async {
      AgentLogger.setEnabled(true);
      final mock = _RecorderLLM()..reads = 2;
      final notifier = makeNotifier(mock);

      await notifier.sendMessage('特雷西娅的死是谁造成的');

      final session = await singleSession();
      expect(session.turns, hasLength(1));
      final turn = session.turns.single;
      expect(turn.query, '特雷西娅的死是谁造成的');
      expect(turn.model, 'test-model');
      expect(turn.baseUrl, 'https://example.com/v1');
      expect(turn.status, ChatTurnStatus.completed);
      // Every model response is recorded untruncated: two reads and the
      // answer (0.14: no review unless asked for). No vectors in the
      // fixture and no plan of first searches from this model (0.14): the
      // note that only keywords are searched is recorded first, then that
      // no plan came.
      expect(turn.iterations, hasLength(5));
      expect(turn.iterations.first.thought, contains('问答质量可能下降'));
      expect(turn.iterations[1].rawResponse, startsWith('（拟定检索）'));
      expect(turn.iterations[2].rawResponse, contains('read_story'));
      expect(turn.iterations[2].tool, 'read_story');
      expect(turn.iterations[4].rawResponse, contains('结论：博士'));
      expect(
        turn.iterations.map((i) => i.rawResponse),
        isNot(contains(startsWith('（审稿）'))),
      );
      // What the turn cost: the three calls, their tokens, one timeline row
      // per call; the same totals sit under the answer on screen.
      expect(turn.usage!.calls, 3);
      expect(turn.usage!.promptTokens, 300);
      expect(turn.usage!.cachedPromptTokens, 150);
      expect(turn.usage!.completionTokens, 30);
      expect(turn.timeline, hasLength(3));
      expect(notifier.state.last.stats!.calls, 3);
      expect(notifier.state.last.stats!.cacheRate, 0.5);
    });

    // The history lists a conversation from its first question on (as a
    // chat app's list of conversations does), not only once it is answered.
    test('a conversation is saved when its first question is sent', () async {
      AgentLogger.setEnabled(true);
      final spy = _SpyStore(tempDir.path);
      store = spy;
      final notifier = makeNotifier(_RecorderLLM()..reads = 1);

      await notifier.sendMessage('第一个问题');
      await notifier.sendMessage('第二个问题');

      // Written once before the first answer, then once per turn; one file.
      expect(spy.savedTurns, [0, 1, 2]);
      final session = await singleSession();
      expect(session.title, '第一个问题');
      expect(notifier.currentSessionId, session.sessionId);

      // A new conversation gets a file of its own; the first one stays.
      notifier.newSession();
      expect(notifier.currentSessionId, isNull);
      await notifier.sendMessage('另一个对话');
      expect(await store.count(), 2);
      expect(notifier.currentSessionId, isNot(session.sessionId));

      // Going back to the first one continues its file.
      notifier.loadSession((await store.load(session.sessionId))!);
      expect(notifier.state, hasLength(4));
      await notifier.sendMessage('第三个问题');
      expect((await store.load(session.sessionId))!.turns, hasLength(3));
      expect(await store.count(), 2);
    });

    // 0.14: an answer sent back is taken back whole — no step on screen, the
    // reason only in the session record (with the rejected reply).
    test('a rejected answer is not shown; why is a line of the work '
        'timeline and of the session record', () async {
      AgentLogger.setEnabled(true);
      final mock = _RecorderLLM()..uncitedFirst = true;
      final notifier = makeNotifier(mock);

      await notifier.sendMessage('她是谁');

      final shown = notifier.state.last;
      expect(shown.content, contains('结论：博士'));
      expect(shown.content, isNot(contains('没有出处的回答')));
      expect(
        shown.steps.map((s) => s.type),
        isNot(contains(ReActEventType.finalAnswerReset)),
      );
      // 0.14 (the developer asked for the timeline to carry what the
      // session record does): the reason, never the rejected text.
      final notes = shown.steps
          .where((s) => s.type == ReActEventType.recordNote)
          .toList();
      expect(notes.single.content, startsWith('退回：'));
      expect(notes.single.content, isNot(contains('没有出处的回答')));
      final turn = (await singleSession()).turns.single;
      final rejected = turn.iterations
          .singleWhere((i) => i.rawResponse.contains('没有出处的回答'));
      expect(rejected.thought, startsWith('退回：'));
      expect(turn.answer, contains('结论：博士'));
    });

    // 0.14 phone: the thinking of two turns ran together in the panel
    // ("…警告".Need more: …").
    test("each turn's thinking starts on a line of its own", () async {
      final mock = _RecorderLLM()
        ..reads = 2
        ..thinking = true;
      final notifier = makeNotifier(mock);

      await notifier.sendMessage('她是谁');

      expect(
        notifier.state.last.reasoning,
        'thought 1.\n\nthought 2.\n\nthought 3.',
      );
    });

    // 0.14: "复核" is asked for under the last answer and runs as a turn of
    // its own; the answer it reviews stays as it is.
    test('a review with no question says so; the answer stays and a '
        'follow-up still continues from it', () async {
      AgentLogger.setEnabled(true);
      final mock = _RecorderLLM()..reviewReply = '{"ok": true}';
      final notifier = makeNotifier(mock);

      await notifier.sendMessage('她是谁');
      final answer = notifier.state.last;
      expect(answer.canReview, isTrue);
      expect(answer.canDigest, isFalse); // a one-entry answer

      mock.resetAgentCalls();
      await notifier.reviewAnswer(answer.id, label: '复核上面的回答');
      expect(notifier.state, hasLength(4));
      expect(notifier.state[1].content, answer.content);
      expect(notifier.state[1].canReview, isFalse);
      expect(notifier.state[2].content, '复核上面的回答');
      expect(notifier.state.last.content, StoryQaAgent.reviewClearNote);
      expect(notifier.state.last.canReview, isFalse);
      expect(notifier.state.last.isError, isFalse);
      // One call: the reader's.
      expect(notifier.state.last.stats!.calls, 1);
      final turn = (await singleSession()).turns.last;
      expect(turn.query, '复核上面的回答');
      expect(turn.iterations.single.rawResponse, startsWith('（审稿）'));

      // The next question continues the reviewed answer's conversation
      // (what it read is still known: it is not read again).
      mock.resetAgentCalls();
      mock.reads = 0;
      await notifier.sendMessage('后来呢');
      expect(mock.requests.last.map((m) => m.content),
          contains(contains('她是罗德岛的公开领袖')),);
      expect(notifier.state.last.content, contains('结论：博士'));
    });

    test("a review's questions go back to the agent, which answers again "
        'below', () async {
      AgentLogger.setEnabled(true);
      final mock = _RecorderLLM()..reviewReply = '{"issues": ["后来呢？"]}';
      final notifier = makeNotifier(mock);

      await notifier.sendMessage('她是谁');
      final answer = notifier.state.last;
      mock.resetAgentCalls();
      await notifier.reviewAnswer(answer.id, label: '复核上面的回答');

      expect(notifier.state, hasLength(4));
      expect(notifier.state[1].content, answer.content);
      final reviewed = notifier.state.last;
      expect(reviewed.content, contains('结论：博士'));
      expect(reviewed.canReview, isFalse); // not reviewed again
      expect(reviewed.steps.first.content, contains('读者审稿'));
      expect(reviewed.steps.first.content, contains('后来呢？'));
      // The agent got the reader's question after its own answer.
      final asked = mock.requests.last.map((m) => m.content).toList();
      expect(asked, contains(contains('一位读者审读了你的答案')));
      expect(asked, contains(contains('后来呢？')));
      final turn = (await singleSession()).turns.last;
      expect(turn.iterations.first.rawResponse, startsWith('（审稿）'));
      expect(turn.answer, contains('结论：博士'));
      // The reader read the answer without its status line and citations.
      expect(mock.reviewRequest, contains('她是罗德岛的公开领袖'));
      expect(mock.reviewRequest, isNot(contains('STORY_ANSWER')));
      expect(mock.reviewRequest, isNot(contains('.txt')));
    });

    test('a review is offered under the last answer only; one that was '
        'canceled can be asked for again', () async {
      final mock = _RecorderLLM()..reviewReply = '{"ok": true}';
      final notifier = makeNotifier(mock);
      await notifier.sendMessage('第一问');
      final first = notifier.state.last.id;
      mock.resetAgentCalls();
      await notifier.sendMessage('第二问');
      expect(notifier.state[1].canReview, isFalse);
      expect(notifier.state.last.canReview, isTrue);
      // Asking for the earlier one does nothing.
      await notifier.reviewAnswer(first, label: '复核');
      expect(notifier.state, hasLength(4));

      final second = notifier.state.last.id;
      mock
        ..resetAgentCalls()
        ..reviewGate = Completer<void>();
      final running = notifier.reviewAnswer(second, label: '复核');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      notifier.cancel();
      mock.reviewGate!.complete();
      await running;
      expect(notifier.state[3].canReview, isTrue);
    });

    // 0.14: "提要" is asked for under a long answer; the paragraphs go
    // above it, the answer itself stays below the marker.
    test('a digest is written above a long answer and its cost added',
        () async {
      AgentLogger.setEnabled(true);
      final mock = _RecorderLLM()
        ..longAnswer = true
        ..stageReply = '{"stages": [{"heading": "身份", "text": "她是领袖。", '
            '"from": [1, 2, 3, 4, 5]}]}';
      final notifier = makeNotifier(mock);
      await notifier.sendMessage('她是谁');
      final answer = notifier.state.last;
      expect(answer.canDigest, isTrue);
      expect(answer.content, isNot(contains('[DETAILS]')));
      final calls = answer.stats!.calls;

      await notifier.digestAnswer(answer.id);
      final digested = notifier.state.last;
      expect(notifier.state, hasLength(2));
      expect(digested.isStreaming, isFalse);
      expect(digested.canDigest, isFalse);
      expect(digested.canReview, isTrue);
      expect(
        digested.content,
        startsWith('[STORY_ANSWER: status=answered]\n## 身份\n\n她是领袖。 '
            '`$_story:0`\n\n[DETAILS]\n\n'),
      );
      expect(digested.content, endsWith(answer.content.split('\n').last));
      expect(digested.stats!.calls, calls + 1);
      final turn = (await singleSession()).turns.single;
      expect(turn.answer, digested.content);
      expect(turn.iterations.last.rawResponse, startsWith('（整理）'));
      expect(turn.usage!.calls, calls + 1);
    });

    test('a digest that fails or is canceled leaves the answer as it was',
        () async {
      final mock = _RecorderLLM()
        ..longAnswer = true
        ..stageReply = '不是 JSON';
      final notifier = makeNotifier(mock);
      await notifier.sendMessage('她是谁');
      final answer = notifier.state.last;

      await notifier.digestAnswer(answer.id);
      expect(notifier.state.last.content, answer.content);
      expect(notifier.state.last.canDigest, isTrue);
      expect(notifier.state.last.isStreaming, isFalse);

      mock.stageGate = Completer<void>();
      final running = notifier.digestAnswer(answer.id);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(notifier.state.last.isStreaming, isTrue);
      notifier.cancel();
      mock.stageGate!.complete();
      await running;
      expect(notifier.state.last.content, answer.content);
      expect(notifier.state.last.isError, isFalse);
      expect(notifier.state.last.canDigest, isTrue);
    });

    test('the cost is counted per question, not accumulated', () async {
      AgentLogger.setEnabled(true);
      final mock = _RecorderLLM();
      final notifier = makeNotifier(mock);

      await notifier.sendMessage('第一问');
      final first = notifier.state.last.stats!.calls;
      mock.resetAgentCalls();
      await notifier.sendMessage('第二问');
      expect(notifier.state.last.stats!.calls, first);
      expect(notifier.state.first.stats, isNull); // user messages: none
    });

    test('multi-turn follow-ups append to the same session file', () async {
      AgentLogger.setEnabled(true);
      final mock = _RecorderLLM();
      final notifier = makeNotifier(mock);

      await notifier.sendMessage('第一问');
      mock.resetAgentCalls();
      await notifier.sendMessage('追问第二问');
      mock.resetAgentCalls();
      await notifier.sendMessage('追问第三问');

      final session = await singleSession();
      expect(session.turns, hasLength(3));
      expect(session.turns[0].query, '第一问');
      expect(session.turns[1].query, '追问第二问');
      expect(session.turns[1].turn, 2);
      expect(session.turns[2].query, '追问第三问');
    });

    test('a claim check records its verdict', () async {
      AgentLogger.setEnabled(true);
      final mock = _RecorderLLM()..verdict = true;
      final notifier = makeNotifier(mock);

      await notifier.sendMessage('她是罗德岛的公开领袖吗');

      final session = await singleSession();
      expect(session.turns.single.verdict, isNotNull);
      expect(notifier.state.last.factCheckVerdict, isNotNull);
    });

    test('error turns are recorded with status error', () async {
      AgentLogger.setEnabled(true);
      final mock = _RecorderLLM()..failNext = true;
      final notifier = makeNotifier(mock);

      await notifier.sendMessage('会出错的问题');

      final session = await singleSession();
      expect(session.turns.single.status, ChatTurnStatus.error);
      expect(session.turns.single.error, contains('boom'));
      expect(notifier.state.last.isError, isTrue);
    });

    test('canceled turns are recorded with status canceled', () async {
      AgentLogger.setEnabled(true);
      final mock = _RecorderLLM()..gate = Completer<void>();
      final notifier = makeNotifier(mock);

      final future = notifier.sendMessage('将被取消的问题');
      // Let the agent stream start, then cancel.
      await Future<void>.delayed(const Duration(milliseconds: 20));
      notifier.cancel();
      mock.gate!.complete();
      await future;

      final session = await singleSession();
      expect(session.turns.single.status, ChatTurnStatus.canceled);
      expect(session.turns.single.error, '[ASK_CANCELED]');
    });

    test('newSession starts a fresh session file', () async {
      AgentLogger.setEnabled(true);
      final mock = _RecorderLLM();
      final notifier = makeNotifier(mock);

      await notifier.sendMessage('第一轮会话');
      notifier.newSession();
      mock.resetAgentCalls();
      await notifier.sendMessage('新会话第一问');

      expect(await store.list(), hasLength(2));
      final sessions = [
        for (final s in await store.list()) (await store.load(s.sessionId))!,
      ];
      sessions.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      expect(sessions.first.turns.single.query, '第一轮会话');
      expect(sessions.last.turns.single.query, '新会话第一问');
    });

    test('no files are written while recording is disabled', () async {
      AgentLogger.setEnabled(false);
      final mock = _RecorderLLM();
      final notifier = makeNotifier(mock);

      await notifier.sendMessage('不记录的问题');

      expect(await store.list(), isEmpty);
      expect(notifier.state, hasLength(2));
      // The on-screen cost does not depend on recording.
      expect(notifier.state.last.stats, isNotNull);
    });
  });

  group('session restore', () {
    test('loadSession rebuilds messages and continues the same file',
        () async {
      AgentLogger.setEnabled(true);
      final mock = _RecorderLLM();
      final notifier = makeNotifier(mock);

      await notifier.sendMessage('第一问');
      final saved = await singleSession();

      // A fresh notifier (simulating app restart) restores the session.
      final restored = makeNotifier(mock);
      restored.loadSession(saved);
      expect(restored.state, hasLength(2));
      expect(restored.state[0].content, '第一问');
      expect(restored.state[0].role, MessageRole.user);
      expect(restored.state[1].role, MessageRole.assistant);
      expect(restored.state[1].steps, isNotEmpty);
      // The cost shows again under the restored answer.
      expect(restored.state[1].stats!.calls, saved.turns.single.usage!.calls);

      mock.resetAgentCalls();
      await restored.sendMessage('恢复后的追问');

      final reloaded = await store.load(saved.sessionId);
      expect(reloaded!.turns, hasLength(2));
      expect(reloaded.turns.last.query, '恢复后的追问');
    });

    test('resendLast asks the last question again', () async {
      AgentLogger.setEnabled(true);
      final mock = _RecorderLLM()..verdict = true;
      final notifier = makeNotifier(mock);

      await notifier.sendMessage('查证问题');
      final saved = await singleSession();

      final restored = makeNotifier(mock);
      restored.loadSession(saved);
      mock.resetAgentCalls();
      await restored.resendLast('查证问题');

      final reloaded = await store.load(saved.sessionId);
      expect(reloaded!.turns, hasLength(2));
      expect(reloaded.turns.last.query, '查证问题');
    });
  });
}

const String _story = 'activities/x/level_x.txt';

/// A one-chapter knowledge base for the agent.
Future<String> _createFixtureDb(Directory dir) async {
  final path = '${dir.path}${Platform.pathSeparator}kb.db';
  final db = await createGameDataDb(path);
  await insertStory(db, _story, ['旁白：她是罗德岛的公开领袖。'], scopeId: 'x');
  await db.close();
  return path;
}

/// Reads the fixture chapter [reads] times, then answers citing it. Every
/// reply is reported to [meter] with token counts, as the app's client does.
class _RecorderLLM extends LLMClient {
  int agentCalls = 0;
  int reads = 1;
  bool verdict = false;

  /// The first answer names no source; the one after it does.
  bool uncitedFirst = false;

  /// Every reply comes with a line of thinking (`thought <n>.`).
  bool thinking = false;
  bool failNext = false;
  Completer<void>? gate;
  UsageMeter? meter;

  /// What the reader ("复核") replies, and what it was asked.
  String reviewReply = '{"ok": true}';
  String reviewRequest = '';
  Completer<void>? reviewGate;

  /// The answer has five entries (long enough for "提要"); what the call
  /// that writes the digest replies.
  bool longAnswer = false;
  String stageReply = '';
  Completer<void>? stageGate;

  /// Every request of the agent itself.
  final List<List<Message>> requests = [];

  void resetAgentCalls() {
    agentCalls = 0;
    failNext = false;
    gate = null;
  }

  @override
  Future<String> chat(
    List<Message> messages, {
    List<Map<String, dynamic>>? tools,
    double temperature = 0.7,
    int maxTokens = 2048,
    List<String>? stop,
  }) async =>
      (await chatCompletion(messages, tools: tools)).content;

  @override
  Future<ChatCompletionResult> chatCompletion(
    List<Message> messages, {
    List<Map<String, dynamic>>? tools,
    double temperature = 0.7,
    int maxTokens = 2048,
    List<String>? stop,
    Future<void>? abortTrigger,
  }) async {
    // The call that plans the first searches: no plan here.
    if (messages.first.content.startsWith(loreSearchPlanRole)) {
      throw const LLMException('no plan');
    }
    final now = DateTime.now();
    ChatCompletionResult other(String content) {
      final result = ChatCompletionResult(
        content: content,
        promptTokens: 100,
        cachedPromptTokens: 50,
        completionTokens: 10,
        timing: CallTiming(startedAt: now, endedAt: now),
      );
      meter?.add(result);
      return result;
    }

    if (messages.length == 2 && messages.last.content.startsWith('问题：')) {
      reviewRequest = messages.last.content;
      if (reviewGate != null) await reviewGate!.future;
      return other(reviewReply);
    }
    if (messages.first.content == loreStageSystemPrompt) {
      if (stageGate != null) await stageGate!.future;
      return other(stageReply);
    }
    requests.add(List.of(messages));
    agentCalls++;
    if (gate != null) await gate!.future;
    if (failNext) {
      failNext = false;
      throw const LLMException('boom');
    }
    ChatCompletionResult reply(String content, [List<ToolCall> calls = const []]) =>
        ChatCompletionResult(
          content: content,
          toolCalls: calls,
          reasoningContent: thinking ? 'thought $agentCalls.' : '',
          promptTokens: 100,
          cachedPromptTokens: 50,
          completionTokens: 10,
          timing: CallTiming(startedAt: now, endedAt: now),
        );
    final result = uncitedFirst && agentCalls == reads + 1
        ? reply('没有出处的回答：她是领袖。')
        : agentCalls <= reads
        ? reply('', [
            ToolCall(
              id: 'call_$agentCalls',
              name: 'read_story',
              arguments: '{"story_id": "$_story"}',
            ),
          ])
        : reply(
            verdict
                ? '[FACT_CHECK_VERDICT:supported]\n支持：她是罗德岛的公开领袖 `$_story:0`。'
                : longAnswer
                    ? '{"entries": [${[
                        for (var n = 1; n <= 5; n++)
                          '{"text": "第 $n 条：她是领袖。", '
                              '"cite": [["$_story", 0, 0]]}',
                      ].join(', ')}], "coverage": "full"}'
                    : '她是罗德岛的公开领袖 `$_story:0`。结论：博士。',
          );
    meter?.add(result);
    return result;
  }
}

/// Notes how many turns each saved file had.
class _SpyStore extends ChatSessionStore {
  _SpyStore(String path) : super(filePath: path);

  final List<int> savedTurns = [];

  @override
  Future<void> save(ChatSessionFile session) {
    savedTurns.add(session.turns.length);
    return super.save(session);
  }
}
