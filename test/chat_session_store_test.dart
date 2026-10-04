import 'dart:convert';
import 'dart:io';

import 'package:arklores/core/agent/chat_session_models.dart';
import 'package:arklores/core/agent/chat_session_store.dart';
import 'package:arklores/core/agent/story_answer.dart';
import 'package:arklores/core/agent/turn_stats.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tempDir;
  late ChatSessionStore store;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('chat_session_store_test');
    store = ChatSessionStore(filePath: tempDir.path);
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  ChatSessionFile makeSession({int turns = 2, String id = 'abc'}) {
    final base = DateTime(2026, 8, 24, 12, 0);
    return ChatSessionFile(
      sessionId: id,
      createdAt: base,
      updatedAt: base.add(Duration(minutes: turns)),
      title: turns == 0 ? '' : '首问标题',
      turns: [
        for (var i = 0; i < turns; i++)
          ChatSessionTurn(
            turn: i + 1,
            timestamp: base.add(Duration(minutes: i)),
            query: '问题$i',
            model: 'test-model',
            baseUrl: 'https://example.com/v1',
            iterations: [
              ReActIterationRecord(
                iteration: 1,
                rawResponse: 'Thought: 查证。\nAction: search_local_lore',
                thought: '查证。',
                action: 'search_local_lore',
                actionInput: '{"query": "阿米娅"}',
                tool: 'search_local_lore',
                toolArgs: const {'query': '阿米娅'},
                observation: '=== Result #1 ===\n原文片段',
              ),
            ],
            answer: '[FACT_CHECK_VERDICT:supported]\n支持。',
            verdict: FactCheckVerdict.supported,
            status: ChatTurnStatus.completed,
            durationMs: 1234,
            usage: const TurnStats(
              calls: 3,
              promptTokens: 300,
              cachedPromptTokens: 150,
              completionTokens: 30,
              elapsed: Duration(seconds: 12),
            ),
          ),
      ],
    );
  }

  test('save then load round-trips the full session', () async {
    final session = makeSession();
    await store.save(session);
    final loaded = await store.load('abc');
    expect(loaded, isNotNull);
    expect(loaded!.sessionId, 'abc');
    expect(loaded.title, '首问标题');
    expect(loaded.turns, hasLength(2));
    final turn = loaded.turns.first;
    expect(turn.usage!.calls, 3);
    expect(turn.model, 'test-model');
    expect(turn.iterations.single.rawResponse,
        contains('Thought: 查证。'),);
    expect(turn.iterations.single.observation, contains('原文片段'));
    expect(turn.verdict, FactCheckVerdict.supported);
    expect(turn.status, ChatTurnStatus.completed);
    expect(turn.durationMs, 1234);
  });

  test('list returns sessions newest-first with summaries', () async {
    await store.save(makeSession(id: 'older', turns: 1));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await store.save(makeSession(id: 'newer', turns: 3));
    final summaries = await store.list();
    expect(summaries, hasLength(2));
    expect(summaries.first.sessionId, 'newer');
    expect(summaries.first.turnCount, 3);
    expect(summaries.first.lastQuery, '问题2');
    expect(summaries.first.corrupt, isFalse);
  });

  test('corrupt file surfaces in list as corrupt and load returns null',
      () async {
    File('${tempDir.path}/conversation_broken.json')
        .writeAsStringSync('not json at all');
    final summaries = await store.list();
    expect(summaries, hasLength(1));
    expect(summaries.single.corrupt, isTrue);
    expect(await store.load('broken'), isNull);
  });

  test('delete removes the session file', () async {
    await store.save(makeSession());
    expect(await store.delete('abc'), isTrue);
    expect(await store.delete('abc'), isFalse);
    expect((await store.list()), isEmpty);
  });

  test('exportText renders a human-readable transcript', () async {
    await store.save(makeSession(turns: 1));
    final text = await store.exportText('abc');
    expect(text, isNotNull);
    expect(text, contains('ArkLores Chat Session'));
    expect(text, contains('问题0'));
    expect(text, contains('Usage          : 3 calls, 300 in (150 cached), 30 out, 12s'));
    expect(text, contains('[Iteration 1]'));
    expect(text, contains('RAW LLM RESPONSE:'));
    expect(text, contains('FINAL ANSWER:'));
  });

  test('prunes to maxSessionFiles keeping the newest', () async {
    for (var i = 0; i < ChatSessionStore.maxSessionFiles + 5; i++) {
      await store.save(makeSession(id: 's$i', turns: 1));
    }
    final summaries = await store.list();
    expect(summaries.length, ChatSessionStore.maxSessionFiles);
    // The five oldest (s0..s4) were pruned.
    expect(summaries.map((s) => s.sessionId), isNot(contains('s0')));
    expect(summaries.map((s) => s.sessionId), contains('s${ChatSessionStore.maxSessionFiles + 4}'));
  });

  test('encoded json carries the format marker and version', () async {
    final session = makeSession(turns: 1);
    final decoded = jsonDecode(session.encode()) as Map<String, dynamic>;
    expect(decoded['format'], 'arklores_chat_session');
    expect(decoded['version'], 1);
    expect(decoded['turns'], hasLength(1));
  });
}
