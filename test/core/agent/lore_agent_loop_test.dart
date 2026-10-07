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

import '../../support/gamedata_fixture.dart';
import '../../support/sqlite.dart';
import '../../support/temp_dir.dart';

/// R17: the tool agent — read-only SQL guard, tools over a fixture DB, and
/// the loop driven by a scripted model. Fixture names are fictional;
/// assertions check generic behaviour only.
void main() {
  setUpAll(useSqfliteFfi);

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
        loreSystemPrompt(),
        loreSystemPrompt(subtask: true),
        loreTextToolProtocol(''),
        loreReviewPrompt,
        loreReviewFollowUp(['<问题>'], json: true),
        loreStagePrompt('1. <条目>'),
        for (final t in [
          ...loreTools(store, SeenLines()),
          DelegateTool((_) async => ''),
        ])
          jsonEncode(t.toJson()),
      ].join('\n');
      expect(text, isNot(contains('库中写作')));
      expect(text, contains('不要用引号引用台词'));
      // R17c: no carve-out for "allowed" quotes — naming one invites it.
      expect(text, isNot(contains('引号只用于')));
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
        '安多恩', '众生行迹', '拉特兰', '吾导先路',
        // R18: no named plot device either — only ways of working that hold
        // for any story.
        '梦', '幻觉', '幻象', '叙诡', '诡计', '叙述性诡计',
      ]) {
        expect(text, isNot(contains(name)), reason: name);
      }
    });

    test('the system prompt keeps the working rules', () {
      final prompt = loreSystemPrompt();
      expect(prompt, contains('先看全局再读原文'));
      expect(prompt, contains('["record", "<记录 id>"]'));
      expect(prompt, contains('"entries"'));
      expect(prompt, contains('"coverage"'));
      // Sub-agents still hand back markdown notes.
      final sub = loreSystemPrompt(subtask: true);
      expect(sub, contains('[COVERAGE: full]'));
      expect(sub, isNot(contains('"entries"')));
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
          .run(query: '星灯做了什么？')
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

    test('a JSON answer streams as markdown; copied dialogue is sent back',
        () async {
      String json(String text) => jsonEncode({
            'entries': [
              {
                'text': text,
                'cite': [
                  ['obt/main/level_main_fx-01.txt', 1, 1],
                ],
              },
            ],
            'coverage': 'full',
          });
      final client = _ScriptedClient([
        _call('read_story', {'story_id': 'obt/main/level_main_fx-01.txt'}),
        _answer(json('星灯说“钟楼的灯由我来点亮”。')),
        _answer(json('星灯主动承担了点亮钟楼的事。')),
      ]);
      final events = await LoreAgentLoop(client: client, store: store)
          .run(query: '星灯做了什么？')
          .toList();
      final recheck = client.requests[2].last.content;
      expect(recheck, contains('照搬了原文台词'));
      expect(recheck, contains('钟楼的灯由我来点亮'));
      expect(recheck, contains('JSON'));
      // The model's JSON stays in the conversation it is sent back with.
      expect(client.requests[2][client.requests[2].length - 2].content,
          startsWith('{'),);
      final answer = finalAnswerOf(events);
      expect(parseStoryAnswerEnvelope(answer)!.status,
          StoryAnswerStatus.answered,);
      expect(answer, contains(
          '星灯主动承担了点亮钟楼的事。 `obt/main/level_main_fx-01.txt:1`',),);
      expect(answer, isNot(contains('"entries"')));
      // Tokens streamed were markdown, not JSON.
      final streamed = events
          .where((e) => e.type == ReActEventType.finalAnswerToken)
          .map((e) => e.content)
          .join();
      expect(streamed, isNot(contains('{')));
      expect(streamed, contains('星灯'));
    });

    test('an answer citing unread lines is sent back once', () async {
      final client = _ScriptedClient([
        _call('grep', {'pattern': '星灯'}),
        _answer('星灯离开了 `obt/main/level_main_fx-01.txt:3`。'),
        _call('read_story', {'story_id': 'obt/main/level_main_fx-01.txt'}),
        _answer('星灯离开了 `obt/main/level_main_fx-01.txt:3`。'),
      ]);
      final events = await LoreAgentLoop(client: client, store: store)
          .run(query: '星灯后来呢？')
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
          .run(query: '星灯是什么？')
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
          .run(query: '星灯做了什么？')
          .toList();
      // R18: only the main agent's answer is reviewed.
      expect(client.reviewRequests, hasLength(1));
      expect(client.reviewRequests.single.first.content, loreReviewPrompt);
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

    // R18: the reviewer reads the answer (no tools, no text); its questions
    // go back to the main agent, which checks them and answers again. One
    // review per question; the rewrite gets its own citation check.
    test('a reader review sends its questions back once', () async {
      const story = 'obt/main/level_main_fx-01.txt';
      final client = _ScriptedClient(
        [
          _call('read_story', {'story_id': story}),
          _answer('星灯点亮了钟楼 `$story:1`。'),
          _call('grep', {'pattern': '星灯'}),
          _answer('星灯点亮了钟楼 `$story:1`，后来离开 `$story:3`。'),
        ],
        reviews: ['{"issues": ["后来离开城市的经过是否被漏掉？"]}', '{"issues": ["再问"]}'],
      );
      final events = await LoreAgentLoop(client: client, store: store)
          .run(query: '星灯做了什么？')
          .toList();
      expect(client.reviewRequests, hasLength(1));
      final review = client.reviewRequests.single;
      expect(review.first.content, loreReviewPrompt);
      expect(review[1].content, contains('星灯做了什么？'));
      expect(review[1].content, contains('星灯点亮了钟楼'));
      expect(review[1].content, contains('虚构主线'));
      expect(review[1].content, isNot(contains('.txt')));
      final followUp = client.requests[2].last.content;
      expect(followUp, contains('后来离开城市的经过是否被漏掉？'));
      expect(followUp, contains('只是线索'));
      expect(followUp, contains('不写读者问题里的文件名'));
      expect(loreReviewPrompt, contains('不写文件名'));
      expect(
        events
            .where((e) => e.type == ReActEventType.finalAnswerReset)
            .map((e) => e.content),
        ['审稿提出 1 个问题，正在核实'],
      );
      expect(
        events.any((e) =>
            e.type == ReActEventType.thought && e.content.contains('读者审稿'),),
        isTrue,
      );
      final answer = finalAnswerOf(events);
      expect(answer, contains('后来离开 `$story:3`'));
      expect(parseStoryAnswerEnvelope(answer)!.status,
          StoryAnswerStatus.answered,);
    });

    // R18: a rewrite reply that only talks about the process is asked for
    // once more; if it still is not an answer, the earlier answer stays.
    test('a process-only reply after a review is asked again, then the '
        'earlier answer is kept', () async {
      const story = 'obt/main/level_main_fx-01.txt';
      final client = _ScriptedClient(
        [
          _call('read_story', {'story_id': story}),
          _answer('星灯点亮了钟楼 `$story:1`。'),
          _answer('出处已核实，现在输出最终答案。'),
          _answer('好的。'),
        ],
        reviews: ['{"issues": ["后来呢？"]}'],
      );
      final events = await LoreAgentLoop(client: client, store: store)
          .run(query: '星灯做了什么？')
          .toList();
      expect(client.requests, hasLength(4));
      expect(client.requests.last.last.content, contains('这不是最终答案'));
      final answer = finalAnswerOf(events);
      expect(parseStoryAnswerEnvelope(answer)!.status,
          StoryAnswerStatus.answered,);
      expect(answer, contains('星灯点亮了钟楼 `$story:1`'));
    });

    String detailJson(List<(String, List<List<Object>>)> entries) =>
        jsonEncode({
          'entries': [
            for (final (text, cite) in entries) {'text': text, 'cite': cite},
          ],
          'coverage': 'full',
        });

    const main = 'obt/main/level_main_fx-01.txt';
    const act = 'activities/act_fx/level_act_fx_01_beg.txt';
    final fiveEntries = detailJson([
      ('夜里星灯到来。', [[main, 0, 0]]),
      ('星灯答应点亮钟楼。', [[main, 1, 1]]),
      ('旁人看见了星灯。', [[main, 2, 2]]),
      ('甲在城门等星灯。', [[act, 1, 2]]),
      ('星灯离开了城市。', [[main, 3, 3]]),
    ]);

    test('a long answer is reorganised; citations merge from its entries',
        () async {
      final client = _ScriptedClient(
        [
          _call('read_story', {'story_id': main}),
          _call('read_story', {'story_id': act}),
          _answer(fiveEntries),
          _answer(jsonEncode({
            'stages': [
              {'heading': '到来', 'text': '星灯到城里并答应点亮钟楼。', 'from': [1, 2, 3]},
              {'text': '星灯最后离开。', 'from': [5]},
            ],
          }),),
        ],
        reviews: ['{"ok": true}'],
      );
      final conversations = <LoreConversation>[];
      final events = await LoreAgentLoop(client: client, store: store)
          .run(
            query: '星灯做了什么？',
            onConversation: conversations.add,
          )
          .toList();
      expect(client.requests, hasLength(4));
      final stage = client.requests.last;
      expect(client.toolChoices.last, 'none');
      expect(stage.last.content, contains('1. 夜里星灯到来。'));
      expect(stage.last.content, contains('"stages"'));
      // The model's detailed JSON stays before the reorganising request.
      expect(stage[stage.length - 2].content, startsWith('{"entries"'));
      final answer = finalAnswerOf(events);
      final body = answer.substring(answer.indexOf('\n') + 1);
      expect(
        body,
        startsWith('## 到来\n\n'
            // Entry 4 is in no paragraph: it joins the one of entry 3.
            '星灯到城里并答应点亮钟楼。 `$main:0-2` `$act:1-2`\n\n'
            '星灯最后离开。 `$main:3`\n\n[DETAILS]\n\n'),
      );
      expect(body, contains('星灯离开了城市。 `$main:3`'));
      expect(parseStoryAnswerEnvelope(answer)!.status,
          StoryAnswerStatus.answered,);
      // The detailed answer streamed under the marker; the paragraphs were
      // written above it.
      final streamed = events
          .where((e) => e.type == ReActEventType.finalAnswerToken)
          .map((e) => e.content)
          .join();
      expect(streamed, startsWith('[DETAILS]\n\n'));
      // A follow-up continues after the detailed JSON answer.
      final kept = conversations.single.messages;
      expect(kept.last.content, startsWith('{"entries"'));
    });

    test('a failed reorganisation keeps the detailed answer only', () async {
      final client = _ScriptedClient([
        _call('read_story', {'story_id': main}),
        _call('read_story', {'story_id': act}),
        _answer(fiveEntries),
        _answer('不是 JSON'),
      ]);
      final events = await LoreAgentLoop(client: client, store: store)
          .run(query: '星灯做了什么？')
          .toList();
      final answer = finalAnswerOf(events);
      expect(answer, isNot(contains('[DETAILS]')));
      expect(answer, contains('夜里星灯到来。 `$main:0`'));
    });

    test('a short answer is not reorganised', () async {
      final client = _ScriptedClient([
        _call('read_story', {'story_id': main}),
        _answer(detailJson([
          ('星灯答应点亮钟楼。', [[main, 1, 1]]),
          ('星灯离开了城市。', [[main, 3, 3]]),
        ]),),
      ]);
      final events = await LoreAgentLoop(client: client, store: store)
          .run(query: '星灯做了什么？')
          .toList();
      expect(client.requests, hasLength(2));
      expect(finalAnswerOf(events), isNot(contains('[DETAILS]')));
    });

    test('fact check: a definite verdict without checked citations is '
        'downgraded', () async {
      final client = _ScriptedClient([
        _call('read_story', {'story_id': 'obt/main/level_main_fx-01.txt'}),
        _answer('[FACT_CHECK_VERDICT:supported]\n确有其事。'),
      ]);
      final events = await LoreAgentLoop(client: client, store: store)
          .run(query: '星灯点亮过钟楼吗？')
          .toList();
      final answer = finalAnswerOf(events);
      expect(answer, contains('[FACT_CHECK_VERDICT:uncertain]'));
      expect(client.requests.first.first.content, contains('"verdict"'));
    });

    test('a JSON answer that starts with a verdict keeps it when cited',
        () async {
      const id = 'obt/main/level_main_fx-01.txt';
      final client = _ScriptedClient([
        _call('read_story', {'story_id': id}),
        _answer('{"verdict": "supported", "entries": [{"text": "确有其事。", '
            '"cite": [["$id", 1, 1]]}], "coverage": "full"}'),
      ]);
      final events = await LoreAgentLoop(client: client, store: store)
          .run(query: '星灯点亮过钟楼吗？')
          .toList();
      final answer = finalAnswerOf(events);
      expect(answer, contains('[FACT_CHECK_VERDICT:supported]'));
      expect(parseFactCheckVerdict(answer), FactCheckVerdict.supported);
      expect(parseStoryAnswerEnvelope(answer)!.status,
          StoryAnswerStatus.answered,);
    });

    test('an answer without a verdict gets none added', () async {
      const id = 'obt/main/level_main_fx-01.txt';
      final client = _ScriptedClient([
        _call('read_story', {'story_id': id}),
        _answer('{"entries": [{"text": "星灯点亮钟楼。", '
            '"cite": [["$id", 1, 1]]}]}'),
      ]);
      final events = await LoreAgentLoop(client: client, store: store)
          .run(query: '星灯做了什么？')
          .toList();
      expect(finalAnswerOf(events), isNot(contains('FACT_CHECK_VERDICT')));
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
            ).run(query: '星灯？').toList(),
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
          .run(query: '某人做了什么？')
          .toList();
      expect(parseStoryAnswerEnvelope(finalAnswerOf(events))!.status,
          StoryAnswerStatus.notCovered,);
    });

    test('a flat cite list is read, and kept in the nested form', () async {
      const id = 'obt/main/level_main_fx-01.txt';
      LoreConversation? saved;
      final client = _ScriptedClient([
        _call('read_story', {'story_id': id}),
        // Flat: ["<story_id>", a, b] directly inside cite.
        _answer('{"entries": [{"text": "星灯点亮钟楼。", '
            '"cite": ["$id", 1, 2]}], "coverage": "full"}'),
      ]);
      final events = await LoreAgentLoop(client: client, store: store)
          .run(
            query: '钟楼？',
            onConversation: (c) => saved = c,
          )
          .toList();
      final answer = finalAnswerOf(events);
      expect(answer, contains('星灯点亮钟楼。 `$id:1-2`'));
      expect(parseStoryAnswerEnvelope(answer)!.status,
          StoryAnswerStatus.answered,);
      expect(client.requests, hasLength(2));
      expect(saved!.messages.last.content, contains('"cite":[["$id",1,2]]'));
    });

    test('citations in an unreadable shape ask for the nested form once',
        () async {
      const id = 'obt/main/level_main_fx-01.txt';
      final client = _ScriptedClient([
        _call('read_story', {'story_id': id}),
        _answer('{"entries": [{"text": "星灯点亮钟楼。", '
            '"cite": [{"file": "$id"}]}]}'),
        _answer('{"entries": [{"text": "星灯点亮钟楼。", '
            '"cite": [["$id", 1, 1]]}]}'),
      ]);
      final events = await LoreAgentLoop(client: client, store: store)
          .run(query: '钟楼？')
          .toList();
      expect(client.requests, hasLength(3));
      expect(client.requests.last.last.content, contains('数组的数组'));
      final answer = finalAnswerOf(events);
      expect(answer, contains('`$id:1`'));
      expect(parseStoryAnswerEnvelope(answer)!.status,
          StoryAnswerStatus.answered,);
    });

    test('a turn cut by a dropped connection is asked again', () async {
      final client = _DroppingClient(
        [
          _call('read_story', {'story_id': 'obt/main/level_main_fx-01.txt'}),
          _answer('钟楼 `obt/main/level_main_fx-01.txt:1`'),
        ],
        drops: 2,
      );
      final events = await LoreAgentLoop(
        client: client,
        store: store,
        review: false,
        streamRetryDelay: Duration.zero,
      ).run(query: '钟楼？').toList();
      expect(client.attempts, 4); // two dropped, then the two real turns
      expect(events.where((e) => e.type == ReActEventType.error), isEmpty);
      expect(events.map((e) => e.content), contains('连接中断，正在重试（2/2）'));
    });

    test('a connection that keeps dropping ends with the error', () async {
      final client = _DroppingClient([_answer('x')], drops: 5);
      final events = await LoreAgentLoop(
        client: client,
        store: store,
        review: false,
        streamRetryDelay: Duration.zero,
      ).run(query: '钟楼？').toList();
      expect(client.attempts, 3);
      expect(events.last.type, ReActEventType.error);
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
          .run(query: '钟楼在哪？')
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
      ).run(query: '读读看').toList();
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
            onConversation: (c) => saved = c,
          )
          .toList();
      expect(saved, isNotNull);
      final client = _ScriptedClient([
        // Cites a line read in the first question: still verified.
        _answer('还是钟楼 `obt/main/level_main_fx-01.txt:1`'),
      ]);
      final events = await LoreAgentLoop(client: client, store: store)
          .run(query: '那后来呢？', prior: saved)
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

/// Fails the first [drops] model calls with a dropped connection.
class _DroppingClient extends _ScriptedClient {
  _DroppingClient(super.turns, {required this.drops});
  final int drops;
  var attempts = 0;

  @override
  Stream<CompletionDelta> streamTurn(
    List<Message> messages, {
    List<Map<String, dynamic>>? tools,
    String? toolChoice,
    double temperature = 0.7,
    int maxTokens = 2048,
  }) {
    if (attempts++ < drops) {
      throw const LLMException('Network error: Connection reset');
    }
    return super.streamTurn(
      messages,
      tools: tools,
      toolChoice: toolChoice,
      temperature: temperature,
      maxTokens: maxTokens,
    );
  }
}

/// Replays [turns] and records every request.
class _ScriptedClient extends LLMClient {
  _ScriptedClient(this.turns, {this.rejectTools = false, this.reviews = const []});

  final List<_Turn> turns;
  final bool rejectTools;

  /// R18: replies of the reviewer (`chatCompletion`); with none left the
  /// call fails, which lets the answer through.
  final List<String> reviews;
  final List<List<Message>> reviewRequests = [];
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
  Future<ChatCompletionResult> chatCompletion(
    List<Message> messages, {
    List<Map<String, dynamic>>? tools,
    double temperature = 0.7,
    int maxTokens = 2048,
    List<String>? stop,
  }) async {
    reviewRequests.add(List.of(messages));
    if (reviewRequests.length > reviews.length) throw UnimplementedError();
    return ChatCompletionResult(content: reviews[reviewRequests.length - 1]);
  }

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
  final db = await createGameDataDb(dbPath, catalog: true);
  await insertRecord(
    db,
    'rec_fx_1',
    contentType: 'item_description',
    category: 'item',
    content: '星灯是一盏古老的灯。',
    fields: {'title': '星灯'},
  );
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
    await insertStory(
      db,
      id,
      s.$10,
      scopeType: s.$3 == 'MAINLINE' ? 'obt' : 'activity',
      scopeId: s.$3 == 'MAINLINE' ? 'main' : s.$1,
    );
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
  }
  await db.close();
}
