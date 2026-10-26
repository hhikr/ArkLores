import 'dart:convert';
import 'dart:io';

import 'package:arklores/core/agent/chat_message.dart';
import 'package:arklores/core/agent/context_ledger.dart';
import 'package:arklores/core/agent/lore_agent_loop.dart';
import 'package:arklores/core/agent/lore_agent_prompts.dart';
import 'package:arklores/core/agent/lore_tools.dart';
import 'package:arklores/core/agent/react_event.dart';
import 'package:arklores/core/agent/tools/wiki_tools.dart';
import 'package:arklores/core/gamedata/gamedata_knowledge_store.dart';
import 'package:arklores/core/llm/llm_client.dart';
import 'package:arklores/features/ai/work_steps.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_wiki.dart';
import '../../support/gamedata_fixture.dart';
import '../../support/sqlite.dart';
import '../../support/temp_dir.dart';

void main() {
  setUpAll(useSqfliteFfi);
  late Directory dir;
  late GameDataKnowledgeStore store;
  const id = 'fixture/chapter.txt';
  const answer =
      '{"entries":[{"text":"结论。","cite":[["fixture/chapter.txt",0,1]]}],"coverage":"full"}';
  Map<String, dynamic> read([int start = 0, int count = 201]) =>
      {'story_id': id, 'start': start, 'count': count};
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('context_dedupe');
    final path = '${dir.path}/test.db';
    final db = await createGameDataDb(path, catalog: true);
    await insertStory(db, id, List.generate(350, (i) => '甲：正文$i'));
    await insertStory(db, 'fixture/structure.txt', ['甲：一', '标题', '甲：二', '甲：三']);
    await db.update('story_lines', {'kind': 'section'}, where: 'story_id = ? AND line_index = 1', whereArgs: ['fixture/structure.txt']);
    await insertStory(db, 'fixture/budget.txt', List.generate(3, (i) => '甲：${List.filled(4500, '文').join()}'));
    await insertRecord(db, 'record_fixture',
        content: '资料正文', contentType: 'item_description', category: 'item',);
    await db.close();
    store = GameDataKnowledgeStore(dbPath: path);
  });
  tearDown(() async {
    await store.close();
    await deleteTempDir(dir);
  });

  test('partial omission bridges structural rows without registering omitted evidence', () async {
    const story = 'fixture/structure.txt';
    final ledger = ContextLedger()..record(0, SeenLines()..add(story, 0)..add(story, 2), step: 2, callKey: 's');
    final shown = SeenLines();
    final out = await ReadStoryTool(store, shown, ledger: ledger).execute({'story_id': story});
    expect(out, contains('（L0–L2 的原文仍在上文，略去）'));
    expect(out, contains('L3 [甲] 三'));
    expect(shown.covers(story, 3, 3), isTrue);
    expect(shown.covers(story, 0, 0), isFalse);
    ledger.record(1, shown, step: 4, callKey: 's2');
    expect(await ReadStoryTool(store, SeenLines(), ledger: ledger).execute({'story_id': story}), startsWith(inContextPrefix));
  });
  test('story dedupe checks printable evidence within the original character budget', () async {
    const story = 'fixture/budget.txt';
    final ledger = ContextLedger()..record(0, SeenLines()..add(story, 0), step: 1, callKey: 'b');
    final out = await ReadStoryTool(store, SeenLines(), ledger: ledger).execute({'story_id': story});
    expect(out, startsWith(inContextPrefix));
    expect(out, contains('L0–L0'));
    expect(out, contains('start=1'));
  });
  test('planned search results enter ledger and block matching model calls', () async {
    final client = _ScriptedClient([_call('search', {'query': '正文'}), _answer(answer)], plans: [
      '{"search":["正文"],"outline":[],"anchors":[]}',
    ],);
    final events = await LoreAgentLoop(client: client, store: store).run(query: '问题').toList();
    final calls = events.where((e) => e.type == ReActEventType.toolCall).toList();
    expect(calls, hasLength(2));
    expect(calls.first.planned, isTrue);
    expect(calls.last.inContext, isTrue);
    final outputs = events.where((e) => e.type == ReActEventType.toolObservation).toList();
    expect(outputs.last.content, contains('第 1 步'));
  });
  test('planned steps are started together, before any of them is shown',
      () async {
    final client = _ScriptedClient([_answer(answer)], plans: [
      '{"search":["正文","甲"],"outline":[],"anchors":[]}',
    ],);
    final events = await LoreAgentLoop(client: client, store: store).run(query: '问题').toList();
    final together = events.indexWhere((e) =>
        e.type == ReActEventType.status && e.content == '2 项查找同时进行',);
    final firstCall =
        events.indexWhere((e) => e.type == ReActEventType.toolCall);
    expect(together, isNonNegative);
    expect(together, lessThan(firstCall));
    expect(events.where((e) => e.type == ReActEventType.toolCall && e.planned),
        hasLength(2),);
  });
  test(
      'wiki pages block only fully present requested paragraphs including section filters',
      () async {
    final source = fakePrts();
    final wiki = fakeWikiLookup(prts: source);
    final ledger = ContextLedger()
      ..record(0, SeenLines()..addRange('wiki:prts:101@7', 0, 1),
          step: 4, callKey: 'w',);
    final seen = SeenLines();
    final tool = WikiReadTool(wiki, seen, ledger: ledger);
    final args = {'page': 'wiki:prts:101', 'count': 2};
    expect(await tool.execute(args), startsWith(inContextPrefix));
    expect(seen.isEmpty, isTrue);
    expect(
        await tool.execute({'page': 'wiki:prts:101', 'start': 1, 'count': 2}),
        contains('P1 '),);
    expect(seen.covers('wiki:prts:101@7', 1, 2), isTrue);
    ledger.record(1, SeenLines()..add('wiki:prts:101@7', 3),
        step: 5, callKey: 's',);
    expect(
        await tool
            .execute({'page': 'wiki:prts:101', 'section': '相关', 'count': 2}),
        startsWith(inContextPrefix),);
    ledger.clear();
    expect(await tool.execute(args), contains('P0 '));
    expect(source.fetches, 1);
  });
  test('blocked reads preserve previously seen citation ranges', () async {
    final seen = SeenLines();
    final ledger = ContextLedger();
    final shown = SeenLines();
    final tool = ReadStoryTool(store, seen, ledger: ledger);
    await SeenLines.duringCall(shown, () => tool.execute(read()));
    ledger.record(0, shown, step: 1, callKey: 'read');
    expect(await tool.execute(read()), startsWith(inContextPrefix));
    expect(seen.covers(id, 0, 200), isTrue);
    expect(seen.seenRanges(id, 0, 300), [(0, 200)]);
  });
  test(
      'same story read is blocked at step 1 without empty lookup counts; citations survive',
      () async {
    final client = _ScriptedClient([
      _call('read_story', read()),
      _call('read_story', read()),
      _answer(answer),
    ]);
    final events =
        await LoreAgentLoop(client: client, store: store, preSearch: false)
            .run(query: '问题')
            .toList();
    final outputs =
        events.where((e) => e.type == ReActEventType.toolObservation).toList();
    expect(outputs[1].content, startsWith(inContextPrefix));
    expect(outputs[1].content, contains('第 1 步'));
    expect(outputs[1].content, isNot(contains('次没有结果')));
    final steps = workStepsOf([
      for (final e in events)
        ReActStep(
            type: e.type,
            content: e.content,
            toolName: e.toolName,
            toolArgs: e.toolArgs,
            inContext: e.inContext,),
    ]).where((s) => s.isTool).toList();
    expect(steps.map((s) => s.number), [1, 0]);
    expect(steps[1].inContext, isTrue);
    expect(finalAnswerOf(events), contains('status=answered'));
    expect(finalAnswerOf(events), contains('chapter.txt:0-1'));
  });
  test('overlapping story read omits L100 through L200 and prints L201 onward',
      () async {
    final client = _ScriptedClient([
      _call('read_story', read()),
      _call('read_story', read(100)),
      _answer(answer),
    ]);
    final events =
        await LoreAgentLoop(client: client, store: store, preSearch: false)
            .run(query: '问题')
            .toList();
    final out =
        events.where((e) => e.type == ReActEventType.toolObservation).last;
    expect(out.inContext, isFalse);
    expect(out.content, contains('（L100–L200 的原文仍在上文，略去）'));
    expect(out.content, contains('L201 [甲]'));
    expect(out.content, isNot(contains('L100 [甲]')));
  });
  test('folded results allow the same lines to execute again', () async {
    final client = _ScriptedClient([
      _call('read_story', read()),
      for (var i = 0; i < 4; i++) _call('grep', {'pattern': '正文$i'}),
      _call('read_story', read()),
      _answer(answer),
    ]);
    final events = await LoreAgentLoop(
            client: client,
            store: store,
            preSearch: false,
            contextCharBudget: 100,)
        .run(query: '问题')
        .toList();
    final reads = events.where((e) =>
        e.type == ReActEventType.toolObservation && e.toolName == 'read_story',);
    expect(reads.last.inContext, isFalse);
    expect(reads.last.content, contains('L0 [甲]'));
    expect(
        client.requests.last.any((m) => m.content.startsWith('[已折叠]')), isTrue,);
  });
  test('same grep call is blocked even without original lines', () async {
    final args = {'pattern': '正文'};
    final client = _ScriptedClient(
        [_call('grep', args), _call('grep', args), _answer('没有可引用的原文。')],);
    final events =
        await LoreAgentLoop(client: client, store: store, preSearch: false)
            .run(query: '问题')
            .toList();
    expect(
        events
            .where((e) => e.type == ReActEventType.toolObservation)
            .last
            .inContext,
        isTrue,);
  });
  test(
      'three context-only turns force none and remove the context note after acceptance',
      () async {
    final client = _ScriptedClient([
      _call('read_story', read()),
      for (var i = 0; i < 3; i++) _call('read_story', read()),
      _answer(answer),
    ]);
    LoreConversation? saved;
    await LoreAgentLoop(client: client, store: store, preSearch: false)
        .run(query: '问题', onConversation: (c) => saved = c)
        .toList();
    expect(client.toolChoices.last, 'none');
    expect(client.requests.last.any((m) => m.content == loreUseContextNote),
        isTrue,);
    expect(
        saved!.messages.any((m) => m.content == loreUseContextNote), isFalse,);
  });
  test(
      'context-only turn disappears after execution and does not advance displayed turn',
      () async {
    final client = _ScriptedClient([
      _call('read_story', read()),
      _call('read_story', read()),
      _call('read_story', read(201, 2)),
      _answer(answer),
    ]);
    final events =
        await LoreAgentLoop(client: client, store: store, preSearch: false)
            .run(query: '问题')
            .toList();
    expect(
        client.requests.last.any((m) => m.content.startsWith(inContextPrefix)),
        isFalse,);
    final statuses = events
        .where((e) => e.type == ReActEventType.status)
        .map((e) => e.content);
    expect(statuses.where((s) => s == '第 2 轮 · 思考中').length, 2);
    expect(statuses, isNot(contains('第 4 轮 · 思考中')));
  });
  test('subtask keeps repeated reads unchanged', () async {
    final client = _ScriptedClient([
      _call('read_story', read()),
      _call('read_story', read()),
      _answer('结论 `fixture/chapter.txt:0-1`'),
    ]);
    final events = await LoreAgentLoop(
            client: client, store: store, preSearch: false, subtask: true,)
        .run(query: '问题')
        .toList();
    expect(events.any((e) => e.inContext), isFalse);
    expect(
        events
            .where((e) => e.type == ReActEventType.toolObservation)
            .last
            .content,
        contains('L0 [甲]'),);
  });
  test(
      'story page dedupe handles whole pages, end, mixed structure and unseen evidence',
      () async {
    final ledger = ContextLedger()
      ..record(0, SeenLines()..addRange(id, 0, 200), step: 1, callKey: 'x');
    final seen = SeenLines();
    final tool = ReadStoryTool(store, seen, ledger: ledger);
    final blocked = await tool.execute(read());
    expect(blocked, startsWith(inContextPrefix));
    expect(blocked, contains('start=201'));
    expect(seen.isEmpty, isTrue);
    ledger.record(1, SeenLines()..addRange(id, 201, 349),
        step: 2, callKey: 'y',);
    expect(await tool.execute(read(300)), contains('这一章到 L349 结束。'));
    ledger.clear();
    final printed = await tool.execute(read(100));
    expect(printed, contains('L100 [甲]'));
    expect(seen.covers(id, 100, 300), isTrue);
  });
  test('record dedupe requires whole record and start zero', () async {
    final ledger = ContextLedger()
      ..record(0, SeenLines()..addRecord('record_fixture', partial: true),
          step: 1, callKey: 'p',);
    final seen = SeenLines();
    final tool = ReadRecordTool(store, seen, ledger: ledger);
    expect(await tool.execute({'id': 'record_fixture'}), contains('资料正文'));
    ledger.record(1, SeenLines()..addRecord('record_fixture'),
        step: 2, callKey: 'w',);
    expect(await tool.execute({'id': 'record:record_fixture'}),
        startsWith(inContextPrefix),);
    expect(await tool.execute({'id': 'record_fixture', 'start': 1}),
        isNot(startsWith(inContextPrefix)),);
  });
}

/// One scripted model turn.
class _Turn {
  const _Turn({this.content = '', this.calls = const []});
  final String content;
  final List<ToolCall> calls;
}

var _callId = 0;

_Turn _call(String name, Map<String, dynamic> args) => _Turn(
      calls: [
        ToolCall(id: 'c${_callId++}', name: name, arguments: jsonEncode(args)),
      ],
    );

_Turn _answer(String text) => _Turn(content: text);

/// Replays model turns without contacting a service.
class _ScriptedClient extends LLMClient {
  _ScriptedClient(this.turns, {this.plans = const []});
  final List<_Turn> turns;
  final List<String> plans;
  final requests = <List<Message>>[];
  final toolChoices = <String?>[];
  var _next = 0;
  var _plan = 0;
  @override
  Future<String> chat(List<Message> messages, {List<Map<String, dynamic>>? tools,
      double temperature = 0.7, int maxTokens = 2048, List<String>? stop,}) async => throw UnimplementedError();
  @override
  Future<ChatCompletionResult> chatCompletion(List<Message> messages,
      {List<Map<String, dynamic>>? tools, double temperature = 0.7,
       int maxTokens = 2048, List<String>? stop, Future<void>? abortTrigger,}) async {
    if (_plan < plans.length) return ChatCompletionResult(content: plans[_plan++]);
    throw UnimplementedError();
  }
  @override
  Stream<CompletionDelta> streamTurn(List<Message> messages,
      {List<Map<String, dynamic>>? tools, String? toolChoice,
       double temperature = 0.7, int maxTokens = 2048,}) async* {
    requests.add(List.of(messages));
    toolChoices.add(toolChoice);
    final turn = turns[_next++];
    if (turn.content.isNotEmpty) yield CompletionDelta(content: turn.content);
    yield CompletionDelta(done: true, toolCalls: turn.calls);
  }
}
