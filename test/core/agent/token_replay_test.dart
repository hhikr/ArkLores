import 'dart:convert';
import 'dart:io';

import 'package:arklores/core/agent/lore_agent_loop.dart';
import 'package:arklores/core/gamedata/gamedata_knowledge_store.dart';
import 'package:arklores/core/llm/llm_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../support/gamedata_fixture.dart';
import '../../support/sqlite.dart';
import '../../support/temp_dir.dart';
import '../../support/token_replay.dart';

ToolCall read(String id, String story, int start, int count) => ToolCall(
      id: id,
      name: 'read_story',
      arguments: jsonEncode({
        'story_id': story,
        'start': start,
        'count': count,
      }),
    );

void main() {
  test('counts schemas, call arguments and reasoning separately from system',
      () {
    final messages = [
      Message.system('规则'),
      Message.user('问题'),
      Message.assistantToolCalls(
        '',
        [read('a', 'fiction.txt', 0, 2)],
        reasoningContent: '思考',
      ),
    ];
    final r = measureReplayRequest(messages, [
      {'name': 'read_story'},
    ]);
    expect(r['system_chars'], 2);
    expect(
      r['dialogue_chars'],
      4 + replayChars(jsonEncode(messages.last.toolCalls)),
    );
    expect(
      r['tool_schema_chars'],
      replayChars(
        jsonEncode([
          {'name': 'read_story'},
        ]),
      ),
    );
    expect(r['message_count'], 3);
    expect(replayChars('𠮷'), 1);
  });

  test('duplicates distinguish stories, line identity and same-result repeats',
      () {
    final r = replayDuplicates([
      Message.toolResult(
        'a',
        '《甲》 a.txt\nL1 [人] abcdefgh\nL1 [人] abcdefgh\n固定说明重复文字abcdefgh',
      ),
      Message.toolResult('b', '《乙》 b.txt\nL1 [人] abcdefgh'),
      Message.toolResult('c', '《甲》 a.txt\nL1 [人] abcdefgh\n固定说明重复文字abcdefgh'),
    ]);
    expect(r['story_line_duplicate_chars'], replayChars('L1 [人] abcdefgh\n'));
    expect(r['other_duplicate_chars'],
        replayChars('固定说明重复文字abcdefgh\n《甲》 a.txt\n'),);
    expect(r['prefix_chars'], 4 * replayChars('L1 [人] '));
    expect(r['prefix_ratio'], closeTo(7 / 15, .0001));
    expect(r['lines_without_story_header'], 0);
  });

  test('merges overlapping and disjoint ranges through interleaved stories',
      () {
    final merged = mergeReplayReads([
      Message.assistantToolCalls('', [read('a', 'a.txt', 0, 20)]),
      Message.assistantToolCalls('', [read('b', 'b.txt', 0, 10)]),
      Message.assistantToolCalls('', [read('c', 'a.txt', 10, 20)]),
      Message.assistantToolCalls('', [
        read('d', 'a.txt', 50, 10),
        const ToolCall(id: 'other', name: 'guide', arguments: '{}'),
      ]),
      Message.assistantToolCalls('', [read('e', 'a.txt', 60, 10)]),
      Message.assistant('{"entries":[]}'),
    ]);
    expect(merged, hasLength(5));
    final first = merged.first.toolCalls!
        .map(ToolCall.fromJson)
        .map(replayArguments)
        .toList();
    expect(first, [
      {'story_id': 'a.txt', 'start': 0, 'count': 30},
      {'story_id': 'a.txt', 'start': 50, 'count': 10},
    ]);
    expect(
      merged[2].toolCalls!.single['function'],
      {'name': 'guide', 'arguments': '{}'},
    );
    expect(
      replayArguments(
        ToolCall.fromJson(merged[3].toolCalls!.single),
      )['start'],
      60,
    );
  });

  test('planner reconstructs anchors and wiki-off strips only search wiki', () {
    final messages = [
      Message.user('问题'),
      Message.assistantToolCalls('', [
        const ToolCall(
          id: 'planned_1',
          name: 'search',
          arguments: '{"query":"名字","wiki":"词"}',
        ),
        const ToolCall(
          id: 'planned_2',
          name: 'gather',
          arguments: '{"names":["名字"]}',
        ),
      ]),
      Message.assistantToolCalls(
        '',
        [
          const ToolCall(
            id: 'x',
            name: 'search',
            arguments: '{"query":"另一个名字","wiki":"词"}',
          ),
        ],
        reasoningContent: '保留',
      ),
      Message.assistant('答案'),
    ];
    expect(replayPlan(messages, wiki: false), {
      'search': ['名字'],
      'anchors': ['名字'],
      'outline': <String>[],
    });
    final script = replayScript(messages, wiki: false);
    expect(script, hasLength(2));
    expect(script.first.reasoningContent, '保留');
    expect(
      replayArguments(ToolCall.fromJson(script.first.toolCalls!.single)),
      {'query': '另一个名字'},
    );
  });

  test('script drives real tools and ledger, and fails on exhaustion',
      () async {
    useSqfliteFfi();
    final dir = await Directory.systemTemp.createTemp('token_replay');
    addTearDown(() => deleteTempDir(dir));
    final path = p.join(dir.path, 'fixture.db');
    final db = await createGameDataDb(path);
    await db.insert('story_lines', {
      'game': 'arknights',
      'story_id': 'fiction.txt',
      'line_index': 0,
      'kind': 'dialogue',
      'speaker': '甲',
      'content': '虚构的正文。',
    });
    await db.insert('story_scopes', {
      'story_id': 'fiction.txt',
      'scope_type': 'event',
      'scope_id': 'fiction',
      'source_path': 'fiction.txt',
    });
    await db.close();
    final store = GameDataKnowledgeStore(dbPath: path);
    addTearDown(store.close);
    final requests = <Map<String, Object?>>[];
    final model = ReplayLLM(
      [
        Message.assistantToolCalls('', [read('a', 'fiction.txt', 0, 1)]),
        Message.assistantToolCalls('', [read('b', 'fiction.txt', 0, 1)]),
        Message.assistant(
          '{"entries":[{"text":"正文","cite":[["fiction.txt",0,0]]}],"coverage":"full"}',
        ),
      ],
      phase: 'main',
      requests: requests,
    );
    LoreConversation? result;
    await LoreAgentLoop(client: model, store: store, preSearch: false)
        .run(
          query: '问题',
          onConversation: (c) => result = c,
        )
        .toList();
    expect(requests, hasLength(3));
    expect(result!.seen.seenRanges('fiction.txt', 0, 0).isNotEmpty, isTrue);
    expect(
      result!.messages.where((m) => m.role == MessageRole.tool).first.content,
      contains('虚构的正文。'),
    );
    await expectLater(
      model.chatCompletion([Message.user('再请求')]),
      throwsStateError,
    );
    expect(requests, hasLength(4));
  });
}
