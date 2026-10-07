import 'dart:async';
import 'dart:io';

import 'package:arklores/core/agent/agent_logger.dart';
import 'package:arklores/core/agent/agent_provider.dart';
import 'package:arklores/core/agent/answer_options.dart';
import 'package:arklores/core/agent/chat_session_models.dart';
import 'package:arklores/core/agent/chat_session_store.dart';
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
      // Every model response is recorded untruncated: two reads, the
      // answer, and (R18) the reader's review of it.
      expect(turn.iterations, hasLength(4));
      expect(turn.iterations.first.rawResponse, contains('read_story'));
      expect(turn.iterations.first.tool, 'read_story');
      expect(turn.iterations[2].rawResponse, contains('结论：博士'));
      expect(turn.iterations.last.rawResponse, startsWith('（审稿）'));
      // What the turn cost: the four calls, their tokens, one timeline row
      // per call; the same totals sit under the answer on screen.
      expect(turn.usage!.calls, 4);
      expect(turn.usage!.promptTokens, 400);
      expect(turn.usage!.cachedPromptTokens, 200);
      expect(turn.usage!.completionTokens, 40);
      expect(turn.timeline, hasLength(4));
      expect(notifier.state.last.stats!.calls, 4);
      expect(notifier.state.last.stats!.cacheRate, 0.5);
    });

    test('the answer options are read per question: review off, no review',
        () async {
      AgentLogger.setEnabled(true);
      final mock = _RecorderLLM()
        ..reads = 2
        ..meter = meter;
      var options = const AnswerOptions(review: false);
      final notifier = AskChatNotifier(
        agent: StoryQaAgent(llmClient: mock, gameDataStore: knowledge),
        usage: meter,
        sessionStore: store,
        configReader: () => const LLMConfig(),
        optionsReader: () => options,
      );
      await notifier.sendMessage('甲是谁');
      final first = (await singleSession()).turns.single;
      expect(first.iterations, hasLength(3));
      expect(first.iterations.map((i) => i.rawResponse),
          isNot(contains(startsWith('（审稿）'))),);
      options = const AnswerOptions();
      mock.resetAgentCalls();
      await notifier.sendMessage('乙是谁');
      final second = (await singleSession()).turns.last;
      expect(second.iterations.last.rawResponse, startsWith('（审稿）'));
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
  bool failNext = false;
  Completer<void>? gate;
  UsageMeter? meter;

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
  }) async {
    agentCalls++;
    if (gate != null) await gate!.future;
    if (failNext) {
      failNext = false;
      throw const LLMException('boom');
    }
    final now = DateTime.now();
    ChatCompletionResult reply(String content, [List<ToolCall> calls = const []]) =>
        ChatCompletionResult(
          content: content,
          toolCalls: calls,
          promptTokens: 100,
          cachedPromptTokens: 50,
          completionTokens: 10,
          timing: CallTiming(startedAt: now, endedAt: now),
        );
    final result = agentCalls <= reads
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
                : '她是罗德岛的公开领袖 `$_story:0`。结论：博士。',
          );
    meter?.add(result);
    return result;
  }
}
