import 'dart:convert';
import 'dart:io';

import 'package:arklores/core/agent/chat_message.dart';
import 'package:arklores/core/agent/context_ledger.dart';
import 'package:arklores/core/agent/lore_agent_loop.dart';
import 'package:arklores/core/agent/lore_agent_prompts.dart';
import 'package:arklores/core/agent/lore_answer_stages.dart';
import 'package:arklores/core/agent/lore_tools.dart';
import 'package:arklores/core/agent/react_event.dart';
import 'package:arklores/core/agent/story_answer.dart';
import 'package:arklores/core/gamedata/gamedata_knowledge_store.dart';
import 'package:arklores/core/llm/llm_client.dart';
import 'package:arklores/core/materials/material_document.dart';
import 'package:arklores/core/materials/material_snapshot.dart';
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
  const id = 'a.txt';
  const answer =
      '{"entries":[{"text":"结论。","cite":[["a.txt",10,12]]}],"coverage":"full"}';
  Map<String, dynamic> read([int start = 10, int count = 3]) =>
      {'story_id': id, 'start': start, 'count': count};
  _Turn reading() => _Turn(calls: [
        ToolCall(id: 'r', name: 'read_story', arguments: jsonEncode(read())),
      ], tokens: 18000,);
  LoreConversation prior(
          {int tokens = 19000, int? compacted, String last = answer,}) =>
      LoreConversation(
        messages: [Message.user('原问题'), Message.assistant(last)],
        seen: SeenLines()..addRange(id, 10, 12),
        questions: ['原问题'],
        question: '原问题',
        lastAnswer: last,
        lastPromptTokens: tokens,
        lastPromptChars: 8000,
        lastCompactionTokens: compacted,
      );
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('context_compaction');
    final path = '${dir.path}/test.db';
    final db = await createGameDataDb(path, catalog: true);
    await insertStory(db, id, List.generate(25, (i) => '甲：正文$i'),
        scopeId: 'fixture',);
    await insertStory(db, 'fixture/long.txt', List.generate(620, (i) => '甲：行$i'));
    await insertRecord(db, 'short_record',
        content: '资料正文', contentType: 'item_description', category: 'item',);
    await insertRecord(db, 'long_record',
        content: List.filled(2000, '文').join(),
        contentType: 'item_description',
        category: 'item',);
    await db.close();
    store = GameDataKnowledgeStore(dbPath: path);
  });
  tearDown(() async {
    await store.close();
    await deleteTempDir(dir);
  });

  test('compaction drops source notes with their original result message', () async {
    const policy = '按来源说明理解资料。';
    final materials = MaterialSnapshot(
      [const MaterialSource(id: 's', title: '来源', enabled: true, policy: policy)],
      [MaterialDocument(id: 'd', sourceId: 's', title: '资料', body: '正文',
          blocks: [MaterialBlock('正文', '')],),],
      const [],
    );
    final source = materials.sources.first;
    final old = prior(tokens: 100000);
    old.messages.add(Message.toolResult('old', policy));
    old.ledger.record(2, SeenLines(), step: 1, callKey: 'old',
        contextDescriptions: [materialSourceDescriptionKey(source.kind, source.policyVersion)],);
    final client = _ScriptedClient([
      _answer('{"notes":"纪要","keep":[]}'),
      _call('read_material', {'id': materials.documents.first.pageId}),
      _answer(answer),
    ]);
    final events = await LoreAgentLoop(client: client, store: store,
        materials: materials, preSearch: false, contextWarnTokens: 20000,)
        .run(query: '追问', prior: old).toList();
    expect(events.where((e) => e.type == ReActEventType.contextCompacted), hasLength(1));
    final result = events.singleWhere((e) =>
        e.type == ReActEventType.toolObservation && e.toolName == 'read_material',);
    expect(result.content, contains(policy));
    expect(result.content, contains('来源：'));
  });

  test('null threshold retains every tool result across questions', () async {
    final client = _ScriptedClient(
        [reading(), _call('read_story', read(13, 3)), _answer(answer)],);
    LoreConversation? saved;
    await LoreAgentLoop(client: client, store: store, preSearch: false)
        .run(query: '问题', onConversation: (c) => saved = c)
        .toList();
    expect(
        saved!.messages.where((m) => m.role == MessageRole.tool), hasLength(2),);
    final next = _ScriptedClient([_answer(answer)]);
    await LoreAgentLoop(client: next, store: store, preSearch: false)
        .run(query: '追问', prior: saved)
        .toList();
    expect(next.requests.single.where((m) => m.role == MessageRole.tool),
        hasLength(2),);
    expect(
        next.requests.single.any((m) => m.content.contains('[已折叠]')), isFalse,);
  });

  test(
      'reported tokens trigger compaction before next turn and rebuild paired tail',
      () async {
    final client = _ScriptedClient([
      reading(),
      _answer('{"notes":"N {with braces}","keep":["a.txt:10-12"]}'),
      _call('read_story', read(10, 2)),
      _answer(answer),
    ]);
    LoreConversation? saved;
    final events = await LoreAgentLoop(
            client: client,
            store: store,
            preSearch: false,
            contextWarnTokens: 20000,)
        .run(
            query: '问题',
            history: [
              Message.user('更早的问题'),
              Message.assistantToolCalls('',
                  [const ToolCall(id: 'old', name: 'guide', arguments: '{}')],),
              Message.toolResult('old', List.filled(10000, '旧').join()),
            ],
            onConversation: (c) => saved = c,)
        .toList();
    expect(client.requests[1].last.content, loreCompactRequest('问题', 9600));
    expect(events.where((e) => e.type == ReActEventType.finalAnswerToken).any((e) => e.content.contains('N {with braces}')), isFalse);
    expect(client.toolChoices[1], 'none');
    expect(client.limits[1], 4096);
    expect(client.specs[1], client.specs.first);
    final rebuilt = client.requests[2];
    expect(
        rebuilt[1].content,
        allOf(
            contains('【对话纪要 #1】'),
            contains('## 保留的原文'),
            contains('L10 [甲] 正文10'),
            contains('L11 [甲] 正文11'),
            contains('L12 [甲] 正文12'),
            contains('## 当前问题'),),);
    expect(rebuilt[2].toolCalls, isNotEmpty);
    expect(rebuilt[3].toolCallId, 'r');
    final blocked = events
        .where((e) => e.type == ReActEventType.toolObservation && e.inContext)
        .single;
    expect(blocked.content, contains('纪要'));
    expect(blocked.content, isNot(contains('第 0 步')));
    expect(saved!.ledger.lineInContext(id, 10), isTrue);
    expect(saved!.seen.covers(id, 10, 12), isTrue);
    expect(parseStoryAnswerEnvelope(finalAnswerOf(events))!.status,
        StoryAnswerStatus.answered,);
    final compact =
        events.singleWhere((e) => e.type == ReActEventType.contextCompacted);
    final work = workStepsOf([
      ReActStep(
          type: compact.type,
          content: compact.content,
          compactedFrom: compact.compactedFrom,
          compactedTo: compact.compactedTo,
          retainedCount: compact.retainedCount,),
    ]).single;
    expect(work.kind, WorkKind.compaction);
    expect(work.number, 0);
    expect(work.isTool, isFalse);
    final measurements = {
      'before_messages': client.requests[1].length - 1,
      'after_messages': rebuilt.length,
      'from': compact.compactedFrom,
      'to': compact.compactedTo,
      'before_chars': client.requests[1]
          .take(client.requests[1].length - 1)
          .fold(0, (n, m) => n + m.content.length),
      'after_chars': rebuilt.fold(0, (n, m) => n + m.content.length),
    };
    await Directory('build').create(recursive: true);
    await File('build/p5c_compaction_measurements.json')
        .writeAsString(jsonEncode(measurements));
  });

  test('unread lines are excluded and overflow drops the remaining suffix',
      () async {
    final p = prior(tokens: 100000);
    p.seen.addRecord('long_record');
    final client = _ScriptedClient([
      _answer(
          '{"notes":"N","keep":["a.txt:9-13","a.txt:20-21","record:long_record","a.txt:10"]}',),
      _answer(answer),
    ]);
    final events = await LoreAgentLoop(
            client: client,
            store: store,
            preSearch: false,
            contextWarnTokens: 1000,)
        .run(query: '追问', prior: p)
        .toList();
    final memo = events
        .singleWhere((e) => e.type == ReActEventType.contextCompacted)
        .content;
    expect(memo, contains('L10 [甲] 正文10'));
    expect(memo, isNot(contains('L9 [甲]')));
    expect(memo, isNot(contains('L13 [甲]')));
    expect(memo, isNot(contains('L20 [甲]')));
    expect(memo, contains('（没有放进来的保留请求：record:long_record、a.txt:10）'));
  });

  test('invalid JSON falls back to last accepted answer and continues',
      () async {
    final client = _ScriptedClient([_answer('invalid'), _answer(answer)]);
    final raw = <String>[];
    final events = await LoreAgentLoop(
            client: client,
            store: store,
            preSearch: false,
            contextWarnTokens: 1000,)
        .run(
            query: '追问',
            prior: prior(tokens: 100000),
            onRawLlmResponse: (_, s) => raw.add(s),)
        .toList();
    expect(
        events.any((e) =>
            e.type == ReActEventType.recordNote &&
            e.content.contains('压缩没有成功'),),
        isTrue,);
    expect(client.requests.last[1].content, contains('L10 [甲] 正文10'));
    expect(raw.first, contains('压缩上下文 #1'));
    expect(events.last.type, ReActEventType.complete);
  });

  test('the compaction point is a setting: the context compacts once it '
      'reaches that share of the warning', () async {
    Future<int?> compactedFrom(int percent) async {
      final client = _ScriptedClient(
          [_answer('{"notes":"N","keep":[]}'), _answer(answer), _answer(answer)],);
      final events = await LoreAgentLoop(
              client: client,
              store: store,
              preSearch: false,
              contextWarnTokens: 100000,
              compactPercent: percent,)
          .run(query: '新问题', prior: prior(tokens: 2000))
          .toList();
      return events
          .where((e) => e.type == ReActEventType.contextCompacted)
          .firstOrNull
          ?.compactedFrom;
    }

    // The size before the first request, as the loop estimates it.
    final size = (await compactedFrom(1))!;
    final share = size * 100 ~/ 100000;
    expect(await compactedFrom(share), size);
    expect(await compactedFrom(share + 2), isNull);
  });

  test('follow-up compaction leaves only memo and new question before planning',
      () async {
    final client =
        _ScriptedClient([_answer('{"notes":"N","keep":[]}'), _answer(answer)]);
    final events = await LoreAgentLoop(
            client: client,
            store: store,
            preSearch: false,
            contextWarnTokens: 1000,)
        .run(query: '新问题', prior: prior(tokens: 100000))
        .toList();
    final messages = client.requests.last;
    expect(messages, hasLength(3));
    expect(messages[2].content, '新问题');
    expect(messages[1].content, contains('1. 原问题'));
    expect(messages[1].content, isNot(contains('## 当前问题')));
    expect(messages[1].content, isNot(contains('2. 新问题')));
    expect(parseStoryAnswerEnvelope(finalAnswerOf(events))!.status,
        StoryAnswerStatus.answered,);
  });

  test('the memo gives the last answer as text with citations, not its JSON',
      () async {
    final client =
        _ScriptedClient([_answer('{"notes":"N","keep":[]}'), _answer(answer)]);
    final p = prior(tokens: 100000);
    await LoreAgentLoop(
            client: client,
            store: store,
            preSearch: false,
            contextWarnTokens: 1000,)
        .run(
          query: '新问题',
          prior: LoreConversation(
            messages: p.messages,
            seen: p.seen,
            questions: p.questions,
            question: p.question,
            lastAnswer: p.lastAnswer,
            lastPromptTokens: p.lastPromptTokens,
            lastPromptChars: p.lastPromptChars,
            entries: const [
              LoreAnswerEntry(heading: '小节'),
              LoreAnswerEntry(text: '结论。', cites: ['a.txt:10-12']),
            ],
          ),
        )
        .toList();
    final memo = client.requests.last[1].content;
    expect(memo, contains('### 小节\n- 结论。（a.txt:10-12）'));
    expect(memo, isNot(contains('"entries"')));
  });

  test('a large last turn is not kept whole: the compaction saw it', () async {
    const long =
        '{"entries":[{"text":"结论。","cite":[["fixture/long.txt",0,1]]}],"coverage":"full"}';
    final client = _ScriptedClient([
      _Turn(calls: [
        ToolCall(
          id: 'r',
          name: 'read_story',
          arguments: jsonEncode(
              {'story_id': 'fixture/long.txt', 'start': 0, 'count': 200},),
        ),
      ], tokens: 18000,),
      _answer('{"notes":"N","keep":[]}'),
      _answer(long),
    ]);
    await LoreAgentLoop(
            client: client,
            store: store,
            preSearch: false,
            contextWarnTokens: 4000,)
        .run(query: '问题')
        .toList();
    final rebuilt = client.requests.last;
    expect(rebuilt.where((m) => m.role == MessageRole.tool), isEmpty);
    expect(rebuilt[1].content, contains('【对话纪要 #1】'));
  });

  test(
      'less than ten percent growth prevents repeated compaction even above threshold',
      () async {
    final client = _ScriptedClient([
      _answer('{"notes":"${List.filled(15000, '文').join()}","keep":[]}'),
      _answer(answer),
    ]);
    final events = await LoreAgentLoop(
            client: client,
            store: store,
            preSearch: false,
            contextWarnTokens: 1000,)
        .run(query: '追问', prior: prior(tokens: 100000))
        .toList();
    final compact =
        events.where((e) => e.type == ReActEventType.contextCompacted).single;
    expect(compact.compactedTo!, greaterThan(800));
    expect(client.requests, hasLength(2));
  });

  test('subtasks never compact even when explicitly given a threshold',
      () async {
    final client = _ScriptedClient([reading(), _answer('结论 `a.txt:10-12`')]);
    final events = await LoreAgentLoop(
            client: client,
            store: store,
            preSearch: false,
            subtask: true,
            contextWarnTokens: 1,)
        .run(query: '问题')
        .toList();
    expect(
        events.any((e) => e.type == ReActEventType.contextCompacted), isFalse,);
    expect(client.requests, hasLength(2));
  });

  test('conversation JSON round trip preserves the next request prefix',
      () async {
    LoreConversation? saved;
    final client = _ScriptedClient([reading(), _answer(answer)]);
    await LoreAgentLoop(client: client, store: store, preSearch: false)
        .run(query: '问题', onConversation: (c) => saved = c)
        .toList();
    final restored = LoreConversation.fromJson(
        jsonDecode(jsonEncode(saved!.toJson())) as Map<String, dynamic>,);
    final live = _ScriptedClient([_answer(answer)]),
        disk = _ScriptedClient([_answer(answer)]);
    await LoreAgentLoop(client: live, store: store, preSearch: false)
        .run(query: '追问', prior: saved)
        .toList();
    await LoreAgentLoop(client: disk, store: store, preSearch: false)
        .run(query: '追问', prior: restored)
        .toList();
    expect(disk.requests.single.map((m) => m.toJson()).toList(),
        live.requests.single.map((m) => m.toJson()).toList(),);
    expect(restored.toJson(), saved!.toJson());
    expect(
        () => LoreConversation.fromJson({'version': 2}), throwsFormatException,);
  });

  test('hidden refused messages remap ledger indices before next question',
      () async {
    final client =
        _ScriptedClient([_call('unknown', {}), reading(), _answer(answer)]);
    LoreConversation? saved;
    await LoreAgentLoop(client: client, store: store, preSearch: false)
        .run(query: '问题', onConversation: (c) => saved = c)
        .toList();
    final entries = saved!.ledger.toJson()['messages'] as List;
    for (final raw in entries) {
      final item = raw as Map<String, dynamic>;
      expect(saved!.messages[item['index'] as int].role, MessageRole.tool);
      expect(saved!.messages[item['index'] as int].content, contains('L10'));
    }
    expect(saved!.messages.any((m) => m.content.contains('unknown')), isFalse);
    final next =
        _ScriptedClient([_call('read_story', read(10, 2)), _answer(answer)]);
    final events =
        await LoreAgentLoop(client: next, store: store, preSearch: false)
            .run(query: '追问', prior: saved)
            .toList();
    expect(
        events
            .singleWhere((e) => e.type == ReActEventType.toolObservation)
            .inContext,
        isTrue,);
  });

  test(
      'retained records are clipped and snapshot sources never fetch over the network',
      () async {
    final source = fakePrts();
    final lookup = fakeWikiLookup(prts: source);
    final page = await source.fetch('101');
    await lookup.snapshots.save(page!);
    final doc = MaterialDocument(
        id: 'fixture/doc',
        sourceId: 'fixture',
        title: '资料',
        body: '正文',
        blocks: const [
          MaterialBlock('资料已读正文', ''),
          MaterialBlock('资料未读正文', ''),
        ],);
    final materials = MaterialSnapshot(
        [const MaterialSource(id: 'fixture', title: '来源', enabled: true)],
        [doc],
        [],);
    final p = prior(tokens: 100000);
    p.seen
      ..addRecord('short_record')
      ..addRecord('long_record')
      ..add(page.id, 1)
      ..add(doc.pageId, 0);
    final client = _ScriptedClient([
      _answer(jsonEncode({
        'notes': 'N',
        'keep': [
          'record:short_record',
          'record:long_record',
          '${page.id}:0-1',
          '${doc.pageId}:0-1',
          'wiki:prts:missing@7:1',
          'record:unread',
          'invalid',
        ],
      }),),
      _answer(answer),
    ]);
    LoreConversation? saved;
    final events = await LoreAgentLoop(
            client: client,
            store: store,
            preSearch: false,
            wiki: lookup,
            materials: materials,
            contextWarnTokens: 20000,)
        .run(query: '追问', prior: p, onConversation: (c) => saved = c)
        .toList();
    final memo = events
        .singleWhere((e) => e.type == ReActEventType.contextCompacted)
        .content;
    expect(memo, contains('资料正文'));
    expect(memo, contains('（片段，全文更长）'));
    expect(memo, contains('P1 [人物关系]'));
    expect(memo, isNot(contains('P0 星灯')));
    expect(memo, contains('资料已读正文'));
    expect(memo, isNot(contains('资料未读正文')));
    expect(saved!.ledger.recordInContext('short_record'), isTrue);
    expect(saved!.ledger.recordInContext('long_record'), isFalse);
    expect(saved!.ledger.lineInContext(page.id, 1), isTrue);
    expect(saved!.ledger.lineInContext(doc.pageId, 0), isTrue);
    final restored = LoreConversation.fromJson(
        jsonDecode(jsonEncode(saved!.toJson())) as Map<String, dynamic>,);
    expect(restored.toJson(), saved!.toJson());
    expect(source.fetches, 1);
  });

  test(
      'request errors and malformed fields both recover without a previous answer',
      () async {
    for (final response in [
      'throw',
      '{"notes":1,"keep":[]}',
      '{"notes":"","keep":[]}',
      '{"notes":"N","keep":[1]}',
    ]) {
      final client = _ScriptedClient([_answer(response), _answer('没有原文。')]);
      final events = await LoreAgentLoop(
              client: client,
              store: store,
              preSearch: false,
              contextWarnTokens: 1000,)
          .run(query: '问题')
          .toList();
      expect(
          events.any((e) =>
              e.type == ReActEventType.recordNote &&
              e.content.contains('压缩没有成功'),),
          isTrue,);
      expect(events.last.type, ReActEventType.complete);
    }
  });

  test(
      'ledger JSON and remap retain overlapping lines and partial records independently',
      () {
    final seen = SeenLines()
      ..addRange('a', 1, 3)
      ..addRange('a', 5, 6)
      ..addRecord('partial', partial: true)
      ..addRecord('whole');
    final ledger = ContextLedger()
      ..record(4, seen, step: 2, callKey: 'call')
      ..record(8, SeenLines()..add('a', 3), step: 3, callKey: 'later');
    final restored = ContextLedger.fromJson(
        jsonDecode(jsonEncode(ledger.toJson())) as Map<String, dynamic>,);
    expect(restored.toJson(), ledger.toJson());
    final remapped = restored.remap({4: 0});
    expect(remapped.stepsShowing('a', 3), {2});
    expect(remapped.recordInContext('partial'), isFalse);
    remapped.forget([0]);
    expect(remapped.lineInContext('a', 3), isFalse);
    expect(ledger.lineInContext('a', 3), isTrue);
    expect(SeenLines.fromJson(seen.toJson()).toJson()['lines'], {
      'a': [
        [1, 3],
        [5, 6],
      ],
    });
  });

  test('follow-up compacts before the search planner starts', () async {
    final client = _ScriptedClient([
      _answer('{"notes":"N","keep":[]}'), _answer(answer),
    ], plans: ['{"search":[],"outline":[],"anchors":[]}'],);
    await LoreAgentLoop(client: client, store: store, contextWarnTokens: 1000)
      .run(query: '追问', prior: prior(tokens: 100000, last: '')).toList();
    expect(client.order.take(3), ['turn', 'plan', 'turn']);
    expect(client.requests.last[1].content, startsWith('【对话纪要 #1】'));
  });

  test('originals removed by compaction may be read again', () async {
    final client = _ScriptedClient([
      _call('read_story', read()),
      _Turn(calls: [ToolCall(id: 'later', name: 'read_story', arguments: jsonEncode(read(13, 3)))], tokens: 18000),
      _answer('{"notes":"N","keep":[]}'),
      _call('read_story', read()), _answer(answer),
    ]);
    final events = await LoreAgentLoop(client: client, store: store,
      preSearch: false, contextWarnTokens: 20000,).run(query: '问题').toList();
    final reads = events.where((e) => e.type == ReActEventType.toolObservation).toList();
    expect(reads, hasLength(3));
    expect(reads.last.inContext, isFalse);
    expect(reads.last.content, contains('L10 [甲] 正文10'));
  });

  test('retained story ranges read through the store page limit', () async {
    final p = prior(tokens: 100000);
    p.seen.addRange('fixture/long.txt', 0, 619);
    final client = _ScriptedClient([_answer('{"notes":"N","keep":["fixture/long.txt:0-619"]}'), _answer(answer)]);
    final events = await LoreAgentLoop(client: client, store: store, preSearch: false, contextWarnTokens: 40000)
      .run(query: '追问', prior: p).toList();
    final memo = events.singleWhere((e) => e.type == ReActEventType.contextCompacted).content;
    expect(memo, contains('L0 [甲] 行0')); expect(memo, contains('L619 [甲] 行619'));
  });

  test('message tool call reasoning and entry JSON preserve all fields', () {
    final call =
        ToolCall(id: 't', name: 'read_story', arguments: jsonEncode(read()));
    expect(ToolCall.fromJson(call.toJson()).toJson(), call.toJson());
    final message = Message.assistantToolCalls('content', [call],
        reasoningContent: 'reason',);
    final restored = Message.fromJson(
        {...message.toJson(), 'reasoning_content': message.reasoningContent},);
    expect(restored.toJson(), message.toJson());
    expect(restored.reasoningContent, 'reason');
    const entry = LoreAnswerEntry(text: 'entry', cites: ['a.txt:10-12']);
    expect(LoreAnswerEntry.fromJson(entry.toJson()).toJson(), entry.toJson());
  });
}

/// One scripted model turn.
class _Turn {
  const _Turn({this.content = '', this.calls = const [], this.tokens});
  final String content;
  final int? tokens;
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
  final order = <String>[];
  final specs = <List<Map<String, dynamic>>?>[];
  final limits = <int>[];
  var _next = 0;
  var _plan = 0;
  @override
  Future<String> chat(
    List<Message> messages, {
    List<Map<String, dynamic>>? tools,
    double temperature = 0.7,
    int maxTokens = 2048,
    List<String>? stop,
  }) async =>
      throw UnimplementedError();
  @override
  Future<ChatCompletionResult> chatCompletion(
    List<Message> messages, {
    List<Map<String, dynamic>>? tools,
    double temperature = 0.7,
    int maxTokens = 2048,
    List<String>? stop,
    Future<void>? abortTrigger,
  }) async {
    order.add('plan');
    if (_plan < plans.length) {
      return ChatCompletionResult(content: plans[_plan++]);
    }
    throw UnimplementedError();
  }

  @override
  Stream<CompletionDelta> streamTurn(
    List<Message> messages, {
    List<Map<String, dynamic>>? tools,
    String? toolChoice,
    double temperature = 0.7,
    int maxTokens = 2048,
  }) async* {
    order.add('turn');
    requests.add(List.of(messages));
    toolChoices.add(toolChoice);
    specs.add(tools);
    limits.add(maxTokens);
    final turn = turns[_next++];
    if (turn.content == 'throw') throw const LLMException('offline test');
    if (turn.content.isNotEmpty) yield CompletionDelta(content: turn.content);
    yield CompletionDelta(
        done: true, toolCalls: turn.calls, promptTokens: turn.tokens,);
  }
}
