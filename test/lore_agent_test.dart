import 'dart:convert';
import 'dart:io';

import 'package:arklores/core/agent/lore_agent_loop.dart';
import 'package:arklores/core/agent/lore_agent_prompts.dart';
import 'package:arklores/core/agent/lore_tools.dart';
import 'package:arklores/core/agent/react_event.dart';
import 'package:arklores/core/agent/story_answer.dart';
import 'package:arklores/core/gamedata/gamedata_knowledge_store.dart';
import 'package:arklores/core/gamedata/readonly_sql.dart';
import 'package:arklores/core/llm/llm_client.dart';
import 'package:arklores/features/ai/investigation_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/temp_dir.dart';

/// R17: the tool agent — read-only SQL guard, tools over a fixture DB, and
/// the loop driven by a scripted model. Fixture names are fictional;
/// assertions check generic behaviour only.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    sqflite.databaseFactory = databaseFactoryFfi;
  });

  group('read-only SQL guard', () {
    test('accepts one SELECT / WITH query', () {
      expect(validateReadOnlySql('SELECT 1;'), 'SELECT 1');
      expect(
        validateReadOnlySql('-- note\nwith x as (select 1) select * from x'),
        contains('select * from x'),
      );
      // Keywords inside literals are text, not statements.
      expect(
        validateReadOnlySql("SELECT * FROM t WHERE c LIKE '%delete%'"),
        isNotEmpty,
      );
    });

    test('rejects writes, several statements, attach and pragma', () {
      for (final sql in [
        'INSERT INTO t VALUES (1)',
        'SELECT 1; SELECT 2',
        "ATTACH DATABASE 'x.db' AS x",
        'PRAGMA table_info(t)',
        'WITH x AS (SELECT 1) DELETE FROM t',
        '',
      ]) {
        expect(() => validateReadOnlySql(sql), throwsFormatException,
            reason: sql,);
      }
    });
  });

  test('record citations are numbered in the displayed answer', () {
    const answer = '甲 `record:aa1`，乙 `record:bb2`，再提甲 `record:aa1`。';
    expect(extractCitedRecordIds(answer), ['aa1', 'bb2']);
    expect(
      humanizeCitations(answer, const {}),
      '甲 〔资料 1〕，乙 〔资料 2〕，再提甲 〔资料 1〕。',
    );
  });

  group('tools over a fixture DB', () {
    late Directory dir;
    late GameDataKnowledgeStore store;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('arklores_lore_test');
      final dbPath = p.join(dir.path, 'lore.db');
      await _createFixture(dbPath);
      store = GameDataKnowledgeStore(dbPath: dbPath);
    });

    // R17b: the prompt the model sees (system prompts of every style and
    // of sub-agents, plus tool descriptions) states rules only — no concrete
    // story, chapter or character that could tilt it towards some questions.
    test('prompts and tool descriptions carry no concrete examples', () {
      final text = [
        for (final style in AnswerStyle.values) loreSystemPrompt(style),
        loreSystemPrompt(AnswerStyle.answer, subtask: true),
        loreTextToolProtocol(''),
        for (final t in [
          ...loreTools(store, SeenLines()),
          DelegateTool((_) async => ''),
        ])
          jsonEncode(t.toJson()),
      ].join('\n');
      expect(text, isNot(contains('库中写作')));
      expect(text, contains('写答案'));
      // Path shapes use placeholders (`level_main_<章>-<关>`), never a real
      // file, level code or character id.
      expect(RegExp(r'[\w/]+_\d+[\w-]*\.txt').hasMatch(text), isFalse);
      expect(RegExp(r'\d+-\d+').hasMatch(text), isFalse);
      expect(RegExp(r'char_\d').hasMatch(text), isFalse);
      expect(RegExp(r'main_\d').hasMatch(text), isFalse);
      // Names from the evaluation fixture and live acceptance questions.
      final eval = jsonDecode(
        File('test/fixtures/investigation_eval.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      final goldIds = [
        for (final c in eval['cases'] as List)
          for (final g in (c as Map)['gold_stories'] as List? ?? const [])
            '${(g as Map)['story_id']}',
      ];
      for (final name in [
        ...goldIds,
        '塔露拉', '切尔诺伯格', '科西切', '罗德岛', '阿米娅', '凯尔希',
        '谬因', '米格鲁', '特蕾西娅', '辞岁行', '双飞燕', '岁兽',
      ]) {
        expect(text, isNot(contains(name)), reason: name);
      }
    });

    test('the system prompt keeps the working rules', () {
      final prompt = loreSystemPrompt(AnswerStyle.answer);
      expect(prompt, contains('先看全局再读原文'));
      expect(prompt, contains('record:<该记录的 id>'));
      expect(prompt, contains('[COVERAGE: full]'));
    });

    tearDown(() async {
      await store.close();
      await deleteTempDir(dir);
    });

    test('sql aggregates over the corpus and records cited lines', () async {
      final seen = SeenLines();
      final out = await SqlTool(store, seen).execute({
        'query': 'SELECT story_id, COUNT(*) AS n FROM story_lines '
            "WHERE content LIKE '%星灯%' OR speaker LIKE '%星灯%' "
            'GROUP BY story_id ORDER BY story_id',
      });
      expect(out, contains('story_id | n'));
      expect(out, contains('activities/act_fx/level_act_fx_01_beg.txt | 2'));
      expect(out, contains('obt/main/level_main_fx-01.txt | 3'));

      final lines = await SqlTool(store, seen).execute({
        'query': 'SELECT story_id, line_index, content FROM story_lines '
            "WHERE content LIKE '%钟楼%'",
      });
      expect(lines, contains('钟楼'));
      expect(seen.covers('obt/main/level_main_fx-01.txt', 1, 1), isTrue);
    });

    test('sql reports errors, rejections and zero rows in words', () async {
      final seen = SeenLines();
      final tool = SqlTool(store, seen);
      expect(
        await tool.execute({'query': 'SELECT nope FROM story_lines'}),
        startsWith('SQL 错误'),
      );
      expect(
        await tool.execute({'query': 'DROP TABLE story_lines'}),
        startsWith('查询被拒绝'),
      );
      // A misspelled name: 0 rows plus the near names the DB does have.
      final zero = await tool.execute({
        'query':
            "SELECT * FROM story_lines WHERE content LIKE '%心灯%'",
      });
      expect(zero, startsWith('0 行'));
      expect(zero, contains('星灯'));
    });

    test('a runaway query is interrupted at the timeout', () async {
      final path = p.join(dir.path, 'lore.db');
      final watch = Stopwatch()..start();
      final result = await runReadOnlySql(
        path,
        'WITH RECURSIVE c(x) AS (SELECT 1 UNION ALL SELECT x + 1 FROM c) '
        'SELECT count(*) FROM c',
        timeout: const Duration(seconds: 1),
      );
      expect(result.error, contains('被中止'));
      expect(watch.elapsed, lessThan(const Duration(seconds: 4)));
      // The DB stays usable for the next query.
      final next = await runReadOnlySql(path, 'SELECT count(*) AS n FROM story_lines');
      expect(next.rows.single.single, 10);
    });

    test('runReadOnlySql truncates to maxRows', () async {
      final result = await store.readOnlySql(
        'SELECT story_id, line_index FROM story_lines',
        maxRows: 2,
      );
      expect(result.rows, hasLength(2));
      expect(result.truncated, isTrue);
    });

    test('grep without a scope lists hit counts per story', () async {
      final out = await GrepTool(store, SeenLines()).execute({
        'pattern': '星灯',
      });
      expect(out, contains('全库共 5 行命中，分布在 2 个故事'));
      // Main story first.
      expect(
        out.indexOf('level_main_fx-01'),
        lessThan(out.indexOf('level_act_fx_01_beg')),
      );
    });

    test('grep in a collection shows hits with context and marks them',
        () async {
      final seen = SeenLines();
      final out = await GrepTool(store, seen).execute({
        'pattern': '钟楼|会面',
        'collection': '虚构活动',
        'context': 1,
      });
      expect(out, contains('* L1 [乙] 今晚的会面不能让人知道。'));
      expect(out, contains('  L0 '));
      expect(seen.covers('activities/act_fx/level_act_fx_02_beg.txt', 0, 2),
          isTrue,);
      final missing = await GrepTool(store, seen).execute({
        'pattern': '心灯',
        'story_ids': ['obt/main/level_main_fx-01.txt'],
      });
      expect(missing, startsWith('0 行'));
      expect(missing, contains('星灯'));
    });

    test('read_story pages a chapter and suggests real ids', () async {
      final seen = SeenLines();
      final tool = ReadStoryTool(store, seen);
      final first = await tool.execute({
        'story_id': 'obt/main/level_main_fx-01',
        'count': 2,
      });
      expect(first, contains('《主线·虚构主线 0-1 幕间《开端》》'));
      expect(first, contains('L0 '));
      expect(first, contains('继续读用 start=2'));
      final rest = await tool.execute({
        'story_id': 'obt/main/level_main_fx-01.txt',
        'start': 2,
      });
      expect(rest, contains('本章结束'));
      expect(seen.covers('obt/main/level_main_fx-01.txt', 0, 3), isTrue);
      final missing =
          await tool.execute({'story_id': 'obt/main/level_main_fx-1.txt'});
      expect(missing, startsWith('没有这个 story_id'));
    });

    test('outline lists chapters with synopses', () async {
      final out = await OutlineTool(store).execute({'collection': '虚构活动'});
      expect(out, contains('activities/act_fx/level_act_fx_02_beg.txt'));
      expect(out, contains('乙与丙秘密会面'));
    });
  });

  group('agent loop', () {
    late Directory dir;
    late GameDataKnowledgeStore store;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('arklores_lore_loop');
      final dbPath = p.join(dir.path, 'lore.db');
      await _createFixture(dbPath);
      store = GameDataKnowledgeStore(dbPath: dbPath);
    });

    tearDown(() async {
      await store.close();
      await deleteTempDir(dir);
    });

    test('searches, reads, answers with checked citations; requests only '
        'grow', () async {
      final client = _ScriptedClient([
        _call('grep', {'pattern': '星灯'}),
        _call('read_story', {'story_id': 'obt/main/level_main_fx-01.txt'}),
        _answer('星灯在钟楼点亮 `obt/main/level_main_fx-01.txt:1`。\n'
            '[COVERAGE: full]'),
      ]);
      final events = await LoreAgentLoop(client: client, store: store)
          .run(query: '星灯做了什么？', style: AnswerStyle.answer)
          .toList();
      final answer = finalAnswerOf(events);
      expect(parseStoryAnswerEnvelope(answer)!.status,
          StoryAnswerStatus.answered,);
      expect(answer, contains('`obt/main/level_main_fx-01.txt:1`'));
      expect(answer, isNot(contains('COVERAGE')));
      expect(events.where((e) => e.type == ReActEventType.toolCall),
          hasLength(2),);
      // Append-only: each request extends the previous one.
      for (var i = 1; i < client.requests.length; i++) {
        final before = client.requests[i - 1];
        final after = client.requests[i];
        expect(after.length, greaterThan(before.length));
        for (var j = 0; j < before.length; j++) {
          expect(jsonEncode(after[j].toJson()), jsonEncode(before[j].toJson()));
        }
      }
      final third = client.requests[2];
      expect(third.where((m) => m.role == MessageRole.tool), hasLength(2));
    });

    test('an answer citing unread lines is sent back once', () async {
      final client = _ScriptedClient([
        _call('grep', {'pattern': '星灯'}),
        _answer('星灯离开了 `obt/main/level_main_fx-01.txt:3`。'),
        _call('read_story', {'story_id': 'obt/main/level_main_fx-01.txt'}),
        _answer('星灯离开了 `obt/main/level_main_fx-01.txt:3`。'),
      ]);
      final events = await LoreAgentLoop(client: client, store: store)
          .run(query: '星灯后来呢？', style: AnswerStyle.answer)
          .toList();
      expect(
        events.where((e) => e.type == ReActEventType.finalAnswerReset),
        hasLength(1),
      );
      final recheck = client.requests[2].last;
      expect(recheck.role, MessageRole.user);
      expect(recheck.content, contains('level_main_fx-01.txt:3'));
      expect(parseStoryAnswerEnvelope(finalAnswerOf(events))!.status,
          StoryAnswerStatus.answered,);
    });

    test('records a query showed can be cited; bare file names are sent back',
        () async {
      final client = _ScriptedClient([
        _call('sql', {
          'query': 'SELECT id, title, content FROM normalized_records '
              "WHERE content LIKE '%星灯%'",
        }),
        _answer('星灯是一盏灯 `record:rec_fx_1`，也出现在 '
            '`obt/main/level_main_fx-01.txt`。'),
        _call('read_story', {'story_id': 'obt/main/level_main_fx-01.txt'}),
        _answer('星灯是一盏灯 `record:rec_fx_1`，点亮钟楼 '
            '`obt/main/level_main_fx-01.txt:1`。'),
      ]);
      final events = await LoreAgentLoop(client: client, store: store)
          .run(query: '星灯是什么？', style: AnswerStyle.answer)
          .toList();
      final recheck = client.requests[2].last.content;
      expect(recheck, contains('只有文件名、没有行号'));
      expect(recheck, isNot(contains('record:rec_fx_1')));
      final answer = finalAnswerOf(events);
      expect(parseStoryAnswerEnvelope(answer)!.status,
          StoryAnswerStatus.answered,);
      expect(answer, isNot(contains('未能在本次读到的原文中核实')));
    });

    test('a delegated sub-agent reads; its checked citations count as seen',
        () async {
      final client = _ScriptedClient([
        _call('delegate', {
          'task': '查星灯在主线里做了什么',
          'story_ids': ['obt/main/level_main_fx-01.txt'],
        }),
        // The sub-agent's own conversation:
        _call('read_story', {'story_id': 'obt/main/level_main_fx-01.txt'}),
        _answer('- 星灯点亮钟楼 `obt/main/level_main_fx-01.txt:1`'),
        // Back in the main conversation:
        _answer('星灯点亮了钟楼 `obt/main/level_main_fx-01.txt:1`。'),
      ]);
      final events = await LoreAgentLoop(client: client, store: store)
          .run(query: '星灯做了什么？', style: AnswerStyle.answer)
          .toList();
      final child = client.requests[1];
      expect(child.first.content, contains('子助手'));
      expect(child[1].content, contains('建议阅读：obt/main/level_main_fx-01.txt'));
      expect(client.toolNames[1], isNot(contains('delegate')));
      expect(client.toolNames[0], contains('delegate'));
      final observation = events
          .firstWhere((e) => e.type == ReActEventType.toolObservation)
          .content;
      expect(observation, contains('子任务结果'));
      expect(observation, isNot(contains('STORY_ANSWER')));
      final answer = finalAnswerOf(events);
      expect(parseStoryAnswerEnvelope(answer)!.status,
          StoryAnswerStatus.answered,);
      expect(
        events.where((e) => e.type == ReActEventType.finalAnswerReset),
        isEmpty,
      );
    });

    test('fact check: a definite verdict without checked citations is '
        'downgraded', () async {
      final client = _ScriptedClient([
        _call('read_story', {'story_id': 'obt/main/level_main_fx-01.txt'}),
        _answer('[FACT_CHECK_VERDICT:supported]\n确有其事。'),
      ]);
      final events = await LoreAgentLoop(client: client, store: store)
          .run(query: '星灯点亮过钟楼吗？', style: AnswerStyle.factCheck)
          .toList();
      final answer = finalAnswerOf(events);
      expect(answer, contains('[FACT_CHECK_VERDICT:uncertain]'));
      expect(client.requests.first.first.content, contains('FACT_CHECK_VERDICT'));
    });

    test('a lead-in about the answering process is dropped, content kept',
        () async {
      Future<String> answerFor(String text) async => finalAnswerOf(
            await LoreAgentLoop(
              client: _ScriptedClient([
                _call('read_story', {
                  'story_id': 'obt/main/level_main_fx-01.txt',
                }),
                _answer(text),
              ]),
              store: store,
            ).run(query: '星灯？', style: AnswerStyle.answer).toList(),
          );
      final dropped = await answerFor(
        '已核实，现在输出完整最终答案。\n\n---\n\n'
        '星灯点亮钟楼 `obt/main/level_main_fx-01.txt:1`。',
      );
      expect(dropped, isNot(contains('已核实')));
      expect(dropped, contains('\n星灯点亮钟楼'));
      // R17b: talk about the search itself goes too.
      final toolTalk = await answerFor(
        '我已经有足够信息回答。让我确认一下这个写法的使用情况——之前 grep 显示'
        '它只出现 2 次，而另一个名字出现很多。整理答案。\n\n'
        '星灯点亮钟楼 `obt/main/level_main_fx-01.txt:1`。',
      );
      expect(toolTalk, isNot(contains('grep')));
      expect(toolTalk, contains('星灯点亮钟楼'));
      final kept = await answerFor(
        '星灯是这座城的守灯人。\n\n'
        '它点亮钟楼 `obt/main/level_main_fx-01.txt:1`。',
      );
      expect(kept, contains('星灯是这座城的守灯人。'));
    });

    test('an answer without any checked citation is not_covered', () async {
      final client = _ScriptedClient([
        _call('grep', {'pattern': '不存在的名字'}),
        _answer('知识库里没有找到相关记载。'),
      ]);
      final events = await LoreAgentLoop(client: client, store: store)
          .run(query: '某人做了什么？', style: AnswerStyle.answer)
          .toList();
      expect(parseStoryAnswerEnvelope(finalAnswerOf(events))!.status,
          StoryAnswerStatus.notCovered,);
    });

    test('falls back to text tool calls when the provider rejects tools',
        () async {
      final client = _ScriptedClient(
        [
          _answer('```tool\n{"name": "read_story", "arguments": '
              '{"story_id": "obt/main/level_main_fx-01.txt"}}\n```'),
          _answer('钟楼 `obt/main/level_main_fx-01.txt:1`'),
        ],
        rejectTools: true,
      );
      final events = await LoreAgentLoop(client: client, store: store)
          .run(query: '钟楼在哪？', style: AnswerStyle.answer)
          .toList();
      expect(finalAnswerOf(events), contains('level_main_fx-01.txt:1'));
      expect(client.requests.last.first.content, contains('```tool'));
      expect(
        client.requests.last
            .any((m) => m.role == MessageRole.user && m.content.startsWith('工具结果')),
        isTrue,
      );
    });

    test('the last turn answers without tools and is partial', () async {
      final client = _ScriptedClient([
        _call('grep', {'pattern': '星灯'}),
        _call('grep', {'pattern': '钟楼'}),
        _answer('星灯 `obt/main/level_main_fx-01.txt:1`'),
      ]);
      final events =
          await LoreAgentLoop(client: client, store: store, maxTurns: 3)
              .run(
                query: '星灯？',
                style: AnswerStyle.answer,
              )
              .toList();
      expect(client.toolChoices.last, 'none');
      expect(client.requests.last.last.content, contains('检索轮数上限'));
      // grep with no scope only gives counts, so line 1 was never shown.
      expect(finalAnswerOf(events), contains('未能在本次读到的原文中核实'));
    });

    test('old tool results are folded past the context budget', () async {
      final client = _ScriptedClient([
        _call('read_story', {'story_id': 'obt/main/level_main_fx-01.txt'}),
        _call('read_story', {'story_id': 'activities/act_fx/level_act_fx_01_beg.txt'}),
        for (var i = 0; i < 9; i++) _call('outline', {'collection': '虚构活动'}),
        _answer('完'),
      ]);
      await LoreAgentLoop(
        client: client,
        store: store,
        contextCharBudget: 1200,
      ).run(query: '读读看', style: AnswerStyle.answer).toList();
      final last = client.requests.last;
      final tools = last.where((m) => m.role == MessageRole.tool).toList();
      expect(tools.first.content, startsWith('[已折叠]'));
      expect(tools.last.content, isNot(startsWith('[已折叠]')));
    });

    test('a follow-up continues the previous conversation', () async {
      LoreConversation? saved;
      await LoreAgentLoop(
        client: _ScriptedClient([
          _call('read_story', {'story_id': 'obt/main/level_main_fx-01.txt'}),
          _answer('钟楼 `obt/main/level_main_fx-01.txt:1`'),
        ]),
        store: store,
      )
          .run(
            query: '钟楼？',
            style: AnswerStyle.answer,
            onConversation: (c) => saved = c,
          )
          .toList();
      expect(saved, isNotNull);
      final client = _ScriptedClient([
        // Cites a line read in the first question: still verified.
        _answer('还是钟楼 `obt/main/level_main_fx-01.txt:1`'),
      ]);
      final events = await LoreAgentLoop(client: client, store: store)
          .run(query: '那后来呢？', style: AnswerStyle.answer, prior: saved)
          .toList();
      final request = client.requests.single;
      expect(request.where((m) => m.role == MessageRole.tool), hasLength(1));
      expect(request.last.content, '那后来呢？');
      expect(parseStoryAnswerEnvelope(finalAnswerOf(events))!.status,
          StoryAnswerStatus.answered,);
    });
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

/// Replays [turns] and records every request.
class _ScriptedClient extends LLMClient {
  _ScriptedClient(this.turns, {this.rejectTools = false});

  final List<_Turn> turns;
  final bool rejectTools;
  final List<List<Message>> requests = [];
  final List<String?> toolChoices = [];
  final List<List<String>> toolNames = [];
  var _next = 0;

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
  Stream<CompletionDelta> streamTurn(
    List<Message> messages, {
    List<Map<String, dynamic>>? tools,
    String? toolChoice,
    double temperature = 0.7,
    int maxTokens = 2048,
  }) async* {
    if (rejectTools && tools != null) {
      throw const LLMException(
        'Chat completion failed: tools are not supported',
        statusCode: 400,
      );
    }
    requests.add(List.of(messages));
    toolChoices.add(toolChoice);
    toolNames.add([
      for (final t in tools ?? const <Map<String, dynamic>>[])
        '${(t['function'] as Map)['name']}',
    ]);
    final turn = turns[_next++];
    if (turn.content.isNotEmpty) yield CompletionDelta(content: turn.content);
    yield CompletionDelta(done: true, toolCalls: turn.calls);
  }
}

Future<void> _createFixture(String dbPath) async {
  final db = await databaseFactoryFfi.openDatabase(dbPath);
  await db.execute(
    'CREATE TABLE story_lines (story_id TEXT, line_index INTEGER, '
    'speaker TEXT, content TEXT)',
  );
  await db.execute(
    'CREATE TABLE story_scopes (story_id TEXT PRIMARY KEY, scope_type TEXT, '
    'scope_id TEXT, source_path TEXT)',
  );
  await db.execute(
    'CREATE TABLE story_catalog (story_id TEXT PRIMARY KEY, '
    'collection_id TEXT, collection_name TEXT, collection_type TEXT, '
    'story_code TEXT, story_name TEXT, avg_tag TEXT, story_sort INTEGER, '
    'synopsis TEXT, synopsis_path TEXT, start_time INTEGER)',
  );
  await db.execute(
    'CREATE TABLE normalized_records (id TEXT PRIMARY KEY, category TEXT, '
    'title TEXT, content TEXT)',
  );
  await db.insert('normalized_records', {
    'id': 'rec_fx_1',
    'category': 'item',
    'title': '星灯',
    'content': '星灯是一盏古老的灯。',
  });
  const stories = {
    'obt/main/level_main_fx-01.txt': (
      'main_fx', '虚构主线', 'MAINLINE', '0-1', '开端', '幕间', 1, null, '星灯抵达。',
      ['夜色很深。', '星灯：钟楼的灯由我来点亮。', '旁人：星灯来了。', '星灯离开了城市。'],
    ),
    'activities/act_fx/level_act_fx_01_beg.txt': (
      'act_fx', '虚构活动', 'ACTIVITY', 'FX-1', '伏笔', '行动前', 1, 1700000000,
      '甲在城门埋下了伏笔。',
      ['城门外很安静。', '甲：我会等星灯。', '星灯：好。'],
    ),
    'activities/act_fx/level_act_fx_02_beg.txt': (
      'act_fx', '虚构活动', 'ACTIVITY', 'FX-2', '转折', '行动前', 2, 1700000000,
      '乙与丙秘密会面，达成交易。',
      ['夜里起风了。', '乙：今晚的会面不能让人知道。', '丙：这笔交易，我答应了。'],
    ),
  };
  for (final MapEntry(key: id, value: s) in stories.entries) {
    await db.insert('story_scopes', {
      'story_id': id,
      'scope_type': s.$3 == 'MAINLINE' ? 'obt' : 'activity',
      'scope_id': s.$3 == 'MAINLINE' ? 'main' : s.$1,
      'source_path': 'zh_CN/gamedata/story/$id',
    });
    await db.insert('story_catalog', {
      'story_id': id,
      'collection_id': s.$1,
      'collection_name': s.$2,
      'collection_type': s.$3,
      'story_code': s.$4,
      'story_name': s.$5,
      'avg_tag': s.$6,
      'story_sort': s.$7,
      'synopsis': s.$9,
      'start_time': s.$8,
    });
    for (final (i, text) in s.$10.indexed) {
      final colon = text.indexOf('：');
      await db.insert('story_lines', {
        'story_id': id,
        'line_index': i,
        'speaker': colon > 0 ? text.substring(0, colon) : null,
        'content': colon > 0 ? text.substring(colon + 1) : text,
      });
    }
  }
  await db.close();
}
