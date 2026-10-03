import 'dart:async';
import 'dart:io';

import 'package:arklores/core/agent/agent_logger.dart';
import 'package:arklores/core/agent/agent_provider.dart';
import 'package:arklores/core/agent/chat_session_models.dart';
import 'package:arklores/core/agent/chat_session_store.dart';
import 'package:arklores/core/agent/fact_check_agent.dart';
import 'package:arklores/core/agent/investigation_agent.dart';
import 'package:arklores/core/agent/question_router.dart';
import 'package:arklores/core/agent/summary_agent.dart';
import 'package:arklores/core/gamedata/gamedata_knowledge_store.dart';
import 'package:arklores/core/llm/llm_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/temp_dir.dart';

void main() {
  late Directory tempDir;
  late ChatSessionStore store;
  late GameDataKnowledgeStore knowledge;

  setUpAll(() {
    sqfliteFfiInit();
    sqflite.databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('chat_session_recorder_test');
    store = ChatSessionStore(filePath: tempDir.path);
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

  AskChatNotifier makeNotifier(_RecorderLLM mock) => AskChatNotifier(
        summaryAgent: SummaryAgent(llmClient: mock, gameDataStore: knowledge),
        factCheckAgent:
            FactCheckAgent(llmClient: mock, gameDataStore: knowledge),
        investigationAgent:
            InvestigationAgent(llmClient: mock, gameDataStore: knowledge),
        router: QuestionRouter(llmClient: mock),
        sessionStore: store,
        configReader: () => const LLMConfig(
          chatModel: 'test-model',
          chatBaseUrl: 'https://example.com/v1',
        ),
      );

  Future<ChatSessionFile> singleSession() async {
    final summaries = await store.list();
    expect(summaries, hasLength(1));
    return (await store.load(summaries.single.sessionId))!;
  }

  group('session recording', () {
    test('auto-routed turn records router decision and raw response',
        () async {
      AgentLogger.setEnabled(true);
      final mock = _RecorderLLM(routeLabel: 'investigate')..mode = AiMode.investigate;
      final notifier = makeNotifier(mock);

      await notifier.sendMessage('特雷西娅的死是谁造成的', mode: AiMode.auto);

      final session = await singleSession();
      expect(session.turns, hasLength(1));
      final turn = session.turns.single;
      expect(turn.userMode, AiMode.auto);
      expect(turn.effectiveMode, AiMode.investigate);
      expect(turn.router!.rawResponse, 'investigate');
      expect(turn.router!.error, isNull);
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
    });

    test('multi-turn follow-ups append to the same session file', () async {
      AgentLogger.setEnabled(true);
      final mock = _RecorderLLM(routeLabel: 'summarize')..mode = AiMode.summarize;
      final notifier = makeNotifier(mock);

      await notifier.sendMessage('第一问', mode: AiMode.summarize);
      mock.resetAgentCalls();
      await notifier.sendMessage('追问第二问', mode: AiMode.summarize);
      mock.resetAgentCalls();
      await notifier.sendMessage('追问第三问', mode: AiMode.auto);

      final session = await singleSession();
      expect(session.turns, hasLength(3));
      expect(session.turns[0].query, '第一问');
      expect(session.turns[1].query, '追问第二问');
      expect(session.turns[1].turn, 2);
      expect(session.turns[2].query, '追问第三问');
      expect(session.turns[2].userMode, AiMode.auto);
      expect(session.turns[2].effectiveMode, AiMode.summarize);
    });

    test('mode switches across turns are recorded per turn', () async {
      AgentLogger.setEnabled(true);
      final mock = _RecorderLLM(routeLabel: 'verify');
      final notifier = makeNotifier(mock);

      await notifier.sendMessage('概括问题', mode: AiMode.summarize);
      mock
        ..mode = AiMode.verify
        ..resetAgentCalls();
      await notifier.sendMessage('查证问题', mode: AiMode.verify);
      mock
        ..mode = AiMode.verify
        ..resetAgentCalls();
      await notifier.sendMessage('自动问题', mode: AiMode.auto);

      final session = await singleSession();
      expect(session.turns[0].userMode, AiMode.summarize);
      expect(session.turns[0].effectiveMode, AiMode.summarize);
      expect(session.turns[1].userMode, AiMode.verify);
      expect(session.turns[1].effectiveMode, AiMode.verify);
      expect(session.turns[1].verdict, isNotNull);
      expect(session.turns[2].userMode, AiMode.auto);
      expect(session.turns[2].effectiveMode, AiMode.verify);
    });

    test('error turns are recorded with status error', () async {
      AgentLogger.setEnabled(true);
      final mock = _RecorderLLM(routeLabel: 'summarize')..failNext = true;
      final notifier = makeNotifier(mock);

      await notifier.sendMessage('会出错的问题', mode: AiMode.summarize);

      final session = await singleSession();
      expect(session.turns.single.status, ChatTurnStatus.error);
      expect(session.turns.single.error, contains('boom'));
      expect(notifier.state.last.isError, isTrue);
    });

    test('canceled turns are recorded with status canceled', () async {
      AgentLogger.setEnabled(true);
      final mock = _RecorderLLM(routeLabel: 'summarize')..gate = Completer<void>();
      final notifier = makeNotifier(mock);

      final future = notifier.sendMessage('将被取消的问题', mode: AiMode.summarize);
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
      final mock = _RecorderLLM(routeLabel: 'summarize');
      final notifier = makeNotifier(mock);

      await notifier.sendMessage('第一轮会话', mode: AiMode.summarize);
      notifier.newSession();
      mock.resetAgentCalls();
      await notifier.sendMessage('新会话第一问', mode: AiMode.summarize);

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
      final mock = _RecorderLLM(routeLabel: 'summarize');
      final notifier = makeNotifier(mock);

      await notifier.sendMessage('不记录的问题', mode: AiMode.summarize);

      expect(await store.list(), isEmpty);
      expect(notifier.state, hasLength(2));
    });
  });

  group('session restore', () {
    test('loadSession rebuilds messages and continues the same file',
        () async {
      AgentLogger.setEnabled(true);
      final mock = _RecorderLLM(routeLabel: 'summarize');
      final notifier = makeNotifier(mock);

      await notifier.sendMessage('第一问', mode: AiMode.summarize);
      final saved = await singleSession();

      // A fresh notifier (simulating app restart) restores the session.
      final restored = makeNotifier(mock);
      restored.loadSession(saved);
      expect(restored.state, hasLength(2));
      expect(restored.state[0].content, '第一问');
      expect(restored.state[0].role, MessageRole.user);
      expect(restored.state[1].role, MessageRole.assistant);
      expect(restored.state[1].steps, isNotEmpty);

      mock.resetAgentCalls();
      await restored.sendMessage('恢复后的追问', mode: AiMode.summarize);

      final reloaded = await store.load(saved.sessionId);
      expect(reloaded!.turns, hasLength(2));
      expect(reloaded.turns.last.query, '恢复后的追问');
    });

    test('restored verify session continues with its effective mode', () async {
      AgentLogger.setEnabled(true);
      final mock = _RecorderLLM(routeLabel: 'verify')..mode = AiMode.verify;
      final notifier = makeNotifier(mock);

      await notifier.sendMessage('查证问题', mode: AiMode.auto);
      final saved = await singleSession();

      final restored = makeNotifier(mock);
      restored.loadSession(saved);
      mock.resetAgentCalls();
      await restored.resendLast('查证问题');

      final reloaded = await store.load(saved.sessionId);
      expect(reloaded!.turns, hasLength(2));
      expect(reloaded.turns.last.userMode, AiMode.verify);
    });
  });
}

const String _story = 'activities/x/level_x.txt';

/// A one-chapter knowledge base for the agents.
Future<String> _createFixtureDb(Directory dir) async {
  final path = '${dir.path}${Platform.pathSeparator}kb.db';
  final db = await databaseFactoryFfi.openDatabase(path);
  await db.execute(
    'CREATE TABLE story_lines (story_id TEXT, line_index INTEGER, '
    'speaker TEXT, content TEXT)',
  );
  await db.execute(
    'CREATE TABLE story_scopes (story_id TEXT PRIMARY KEY, scope_type TEXT, '
    'scope_id TEXT, source_path TEXT)',
  );
  await db.insert('story_scopes', {
    'story_id': _story,
    'scope_type': 'activity',
    'scope_id': 'x',
    'source_path': 'zh_CN/gamedata/story/$_story',
  });
  await db.insert('story_lines', {
    'story_id': _story,
    'line_index': 0,
    'speaker': '旁白',
    'content': '她是罗德岛的公开领袖。',
  });
  await db.close();
  return path;
}

/// Distinguishes router calls (system prompt contains 模式分类器) from agent
/// calls. Agent calls read the fixture chapter (twice in investigate mode),
/// then answer citing it.
class _RecorderLLM extends LLMClient {
  _RecorderLLM({required this.routeLabel});
  final String routeLabel;
  int routeCalls = 0;
  int agentCalls = 0;
  bool failNext = false;
  Completer<void>? gate;

  AiMode mode = AiMode.summarize;

  void resetAgentCalls() {
    agentCalls = 0;
    failNext = false;
    gate = null;
  }

  bool _isRouteCall(List<Message> messages) =>
      messages.first.content.contains('模式分类器');

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
    if (_isRouteCall(messages)) {
      routeCalls++;
      return ChatCompletionResult(content: routeLabel);
    }
    agentCalls++;
    if (gate != null) await gate!.future;
    if (failNext) {
      failNext = false;
      throw const LLMException('boom');
    }
    final reads = mode == AiMode.investigate ? 2 : 1;
    if (agentCalls <= reads) {
      return ChatCompletionResult(
        content: '',
        toolCalls: [
          ToolCall(
            id: 'call_$agentCalls',
            name: 'read_story',
            arguments: '{"story_id": "$_story"}',
          ),
        ],
      );
    }
    return ChatCompletionResult(
      content: mode == AiMode.verify
          ? '[FACT_CHECK_VERDICT:supported]\n支持：她是罗德岛的公开领袖 `$_story:0`。'
          : '她是罗德岛的公开领袖 `$_story:0`。结论：博士。',
    );
  }
}