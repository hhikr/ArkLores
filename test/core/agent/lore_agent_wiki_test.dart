import 'dart:convert';
import 'dart:io';

import 'package:arklores/core/agent/lore_agent_loop.dart';
import 'package:arklores/core/agent/lore_agent_prompts.dart';
import 'package:arklores/core/agent/lore_answer_json.dart';
import 'package:arklores/core/agent/lore_answer_stages.dart';
import 'package:arklores/core/agent/lore_tools.dart';
import 'package:arklores/core/agent/react_event.dart';
import 'package:arklores/core/agent/story_answer.dart';
import 'package:arklores/core/agent/tools/wiki_tools.dart';
import 'package:arklores/core/gamedata/game.dart';
import 'package:arklores/core/gamedata/gamedata_knowledge_store.dart';
import 'package:arklores/core/llm/llm_client.dart';
import 'package:arklores/core/wiki/wiki_page.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../support/fake_wiki.dart';
import '../../support/gamedata_fixture.dart';
import '../../support/sqlite.dart';
import '../../support/temp_dir.dart';

/// 0.13: the wiki tools and wiki citations in the agent loop. Fictional
/// content only; assertions check generic behaviour.
void main() {
  setUpAll(useSqfliteFfi);

  group('wiki tools', () {
    test('search lists page refs; read numbers paragraphs under sections '
        'and records what it showed', () async {
      final wiki = fakeWikiLookup();
      final seen = SeenLines();
      final search = await WikiSearchTool(wiki).execute({'query': '星灯'});
      expect(search, contains('wiki:prts:101 | 星灯'));
      expect(search, contains('1 个页面'));
      expect(search, isNot(contains('（格式：页面引用')));
      expect(WikiSearchTool(wiki).description, contains('格式为页面引用 | 标题 | 摘要'));

      final read = await WikiReadTool(wiki, seen)
          .execute({'page': 'wiki:prts:101', 'count': 2});
      expect(read, contains('页面 id：wiki:prts:101@7'));
      expect(read, isNot(contains('引用写 ["wiki:prts:101@7"')));
      expect(read, contains('小节：人物关系(P1) 相关活动(P3)'));
      expect(read, contains('P0 星灯是虚构城市里的点灯人。'));
      expect(read, contains('## 人物关系\nP1 星灯与守夜人是旧识。'));
      expect(read, isNot(contains('P2 ')));
      expect(read, contains('下一段 start=2'));
      expect(seen.covers('wiki:prts:101@7', 0, 1), isTrue);
      expect(seen.covers('wiki:prts:101@7', 0, 2), isFalse);

      final section = await WikiReadTool(wiki, seen)
          .execute({'page': 'wiki:prts:101@7', 'section': '相关'});
      expect(section, contains('P3 星灯在虚构活动中登场。'));
      expect(section, isNot(contains('P1 ')));
      expect(seen.covers('wiki:prts:101@7', 3, 3), isTrue);
    });

    test('missing pages and an unreachable wiki say so', () async {
      final prts = fakePrts();
      final wiki = fakeWikiLookup(prts: prts);
      expect(
        await WikiReadTool(wiki, SeenLines()).execute({'page': '不存在'}),
        startsWith('没有这个页面'),
      );
      expect(
        await WikiSearchTool(wiki).execute({'query': '星灯', 'game': 'endfield'}),
        startsWith('没有找到'),
      );
      prts.unavailable = true;
      final down = await WikiSearchTool(wiki).execute({'query': '星灯'});
      expect(down, contains('PRTS 暂时无法访问'));
      expect(down, isNot(contains('只用本地知识库')));
      final readDown = await WikiReadTool(wiki, SeenLines())
          .execute({'page': 'wiki:prts:101'});
      expect(readDown, contains('PRTS 暂时无法访问'));
      expect(readDown, isNot(contains('只用本地知识库')));
      expect(
        WikiReadTool(wiki, SeenLines()).description,
        contains('网络不可用时改用本地知识库作答'),
      );
    });

    test('words no page holds together are searched one by one', () async {
      final wiki = fakeWikiLookup();
      final apart =
          await WikiSearchTool(wiki).execute({'query': '星灯 别处 的事'});
      expect(apart, startsWith('PRTS 上没有同时含“星灯 别处 的事”这几个词的页面'));
      expect(apart, contains('“星灯”：\nwiki:prts:101 | 星灯'));
      expect(apart, isNot(contains('“别处”')));
      // Something was found: not a lookup that came back empty.
      expect(lookupFoundNothing(apart), isFalse);
      final none = await WikiSearchTool(wiki).execute({'query': '别处 的事'});
      expect(none, startsWith('没有找到'));
      expect(none, contains('“别处”、“的事” 单独搜也没有'));
    });

    test('the same word is asked of the wiki once, also while it runs',
        () async {
      final prts = fakePrts();
      final wiki = fakeWikiLookup(prts: prts);
      final both = await Future.wait([
        wiki.search(Game.arknights, '星灯'),
        wiki.search(Game.arknights, '星灯', limit: 4),
      ]);
      expect(both.every((hits) => hits.length == 1), isTrue);
      await WikiSearchTool(wiki).execute({'query': '星灯'});
      expect(prts.searches, 1);
      // A failure is not kept.
      prts.unavailable = true;
      await expectLater(
        wiki.search(Game.arknights, '守夜人'),
        throwsA(isA<WikiUnavailable>()),
      );
      prts.unavailable = false;
      expect(await wiki.search(Game.arknights, '守夜人'), hasLength(1));
    });
  });

  group('wiki citations', () {
    test('a cite tuple of a page id becomes a ref without .txt', () {
      expect(
        loreCitationRefs([
          ['wiki:prts:101@7', 1, 2],
          ['wiki:warfarin:operators/star-lamp@1a2b3c4d', 'P3', 'P3'],
        ]),
        ['wiki:prts:101@7:1-2', 'wiki:warfarin:operators/star-lamp@1a2b3c4d:3'],
      );
      expect(
        mergeCitationRefs(['wiki:prts:101@7:1-2', 'wiki:prts:101@7:3']),
        ['wiki:prts:101@7:1-3'],
      );
      final normalized = normalizeAnswerCites(jsonEncode({
        'entries': [
          {
            'text': '甲',
            'cite': ['wiki:prts:101@7', 1, 2],
          },
        ],
      }),);
      expect(normalized, contains('[["wiki:prts:101@7",1,2]]'));
      expect(withoutCitations('甲 `wiki:prts:101@7:1-2`'), '甲');
    });

    test('the prompt names the third kind of citation only with the wiki '
        'on, and no page or character', () {
      expect(loreSystemPrompt(), isNot(contains('wiki_read')));
      final prompt = loreSystemPrompt(wiki: true);
      expect(prompt, contains('wiki_read'));
      expect(prompt, contains('["<页面 id>", <起始段>, <结束段>]'));
      expect(loreSystemPrompt(subtask: true, wiki: true),
          contains('`<页面 id>:<起始段>-<结束段>`'),);
      expect(RegExp(r'\d+-\d+').hasMatch(prompt), isFalse);
      for (final t in wikiTools(fakeWikiLookup(), SeenLines())) {
        expect(RegExp(r'\d+-\d+').hasMatch(jsonEncode(t.toJson())), isFalse);
      }
    });
  });

  group('the loop with the wiki', () {
    late Directory dir;
    late GameDataKnowledgeStore store;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('arklores_wiki_loop');
      final dbPath = p.join(dir.path, 'lore.db');
      final db = await createGameDataDb(dbPath, catalog: true);
      await insertStory(db, 'obt/main/level_main_fx-01.txt', ['星灯：我来点灯。']);
      await db.close();
      store = GameDataKnowledgeStore(dbPath: dbPath);
    });
    tearDown(() async {
      await store.close();
      await deleteTempDir(dir);
    });

    String json(List<Object> cite) => jsonEncode({
          'entries': [
            {'text': '据 Wiki 整理，星灯与守夜人是旧识。', 'cite': [cite]},
          ],
          'coverage': 'full',
        });

    test('read paragraphs cite like lines; the tools and prompt are there '
        'only with a wiki', () async {
      final client = _ScriptedClient([
        _call('wiki_search', {'query': '星灯'}),
        _call('wiki_read', {'page': 'wiki:prts:101'}),
        _answer(json(['wiki:prts:101@7', 1, 1])),
      ]);
      final events = await LoreAgentLoop(
        client: client,
        store: store,
        wiki: fakeWikiLookup(),
      ).run(query: '星灯和谁是旧识？').toList();
      expect(client.toolNames.first, containsAll(['wiki_search', 'wiki_read']));
      expect(client.requests.first.first.content, contains('Wiki 资料'));
      final answer = finalAnswerOf(events);
      expect(parseStoryAnswerEnvelope(answer)!.status,
          StoryAnswerStatus.answered,);
      expect(answer, contains('`wiki:prts:101@7:1`'));
      expect(answer, isNot(contains('未能在本次读到的原文中核实')));

      final without = _ScriptedClient([_answer('没有查到。\n[COVERAGE: gaps]')]);
      await LoreAgentLoop(client: without, store: store)
          .run(query: '星灯？')
          .toList();
      expect(without.toolNames.first, isNot(contains('wiki_read')));
      expect(without.requests.first.first.content, isNot(contains('wiki_read')));
    });

    test('a paragraph not read is sent back, then flagged', () async {
      final client = _ScriptedClient([
        _call('wiki_read', {'page': 'wiki:prts:101', 'count': 1}),
        // P3 was never shown.
        _answer(json(['wiki:prts:101@7', 3, 3])),
        _answer(json(['wiki:prts:101@7', 3, 3])),
      ]);
      final events = await LoreAgentLoop(
        client: client,
        store: store,
        wiki: fakeWikiLookup(),
      ).run(query: '星灯？').toList();
      expect(client.requests[2].last.content, contains('wiki:prts:101@7:3'));
      expect(client.requests[2].last.content, contains('实际看到的行或记录'));
      final answer = finalAnswerOf(events);
      expect(answer, contains('未能在本次读到的原文中核实'));
      expect(parseStoryAnswerEnvelope(answer)!.status,
          StoryAnswerStatus.notCovered,);
    });

    test('an unreachable wiki: the tool says so and the answer goes on',
        () async {
      final prts = fakePrts()..unavailable = true;
      final client = _ScriptedClient([
        _call('wiki_search', {'query': '星灯'}),
        _call('read_story', {'story_id': 'obt/main/level_main_fx-01.txt'}),
        _answer('星灯负责点灯 `obt/main/level_main_fx-01.txt:0`。\n[COVERAGE: full]'),
      ]);
      final events = await LoreAgentLoop(
        client: client,
        store: store,
        wiki: fakeWikiLookup(prts: prts),
      ).run(query: '星灯做什么？').toList();
      final observation = events
          .firstWhere((e) => e.type == ReActEventType.toolObservation)
          .content;
      expect(observation, contains('暂时无法访问'));
      expect(events.where((e) => e.type == ReActEventType.error), isEmpty,
          reason: events.map((e) => '${e.type}: ${e.content}').join('\n'),);
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
        ToolCall(id: 'w${_callId++}', name: name, arguments: jsonEncode(args)),
      ],
    );

_Turn _answer(String text) => _Turn(content: text);

/// Replays [turns] and records every request and the tools it offered.
class _ScriptedClient extends LLMClient {
  _ScriptedClient(this.turns);

  final List<_Turn> turns;
  final List<List<Message>> requests = [];
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
    requests.add(List.of(messages));
    toolNames.add([
      for (final t in tools ?? const <Map<String, dynamic>>[])
        '${(t['function'] as Map)['name']}',
    ]);
    final turn = turns[_next++];
    if (turn.content.isNotEmpty) yield CompletionDelta(content: turn.content);
    yield CompletionDelta(done: true, toolCalls: turn.calls);
  }
}
