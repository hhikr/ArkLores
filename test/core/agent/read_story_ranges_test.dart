import 'dart:convert';
import 'dart:io';
import 'package:arklores/core/agent/context_ledger.dart';
import 'package:arklores/core/agent/lore_tools.dart';
import 'package:arklores/core/agent/tool_call_gate.dart';
import 'package:arklores/core/gamedata/gamedata_knowledge_store.dart';
import 'package:arklores/core/llm/llm_client.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../support/gamedata_fixture.dart';
import '../../support/sqlite.dart';
import '../../support/temp_dir.dart';

void main() {
  setUpAll(useSqfliteFfi);
  late Directory dir;
  late GameDataKnowledgeStore store;
  const id = 'fixture/ranges.txt';
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('read_ranges');
    final path = '${dir.path}/test.db';
    final db = await createGameDataDb(path, catalog: true);
    await insertStory(db, id, List.generate(400, (i) => '甲：正文$i'));
    await insertStory(
        db, 'fixture/long.txt', List.generate(5, (i) => '甲：${'文' * 4500}'),);
    await db.close();
    store = GameDataKnowledgeStore(dbPath: path);
  });
  tearDown(() async {
    await store.close();
    await deleteTempDir(dir);
  });
  Map<String, dynamic> args(Object? ranges) =>
      {'story_id': id, 'ranges': ranges};
  test(
      'sorts disjoint passages, prints one header and registers only shown lines',
      () async {
    final seen = SeenLines();
    final out = await ReadStoryTool(store, seen).execute({
      ...args([
        [10, 2],
        [0, 2],
      ]),
      'start': 200,
      'count': 1,
    });
    expect(RegExp('《').allMatches(out).length, 1);
    expect(out, contains('（L2–L9 未读）'));
    expect(out.indexOf('L0 '), lessThan(out.indexOf('L10 ')));
    expect(seen.covers(id, 0, 1), isTrue);
    expect(seen.covers(id, 10, 11), isTrue);
    for (var i = 2; i < 10; i++) {
      expect(seen.covers(id, i, i), isFalse);
    }
    expect(seen.covers(id, 200, 200), isFalse);
  });
  test('merges overlapping and adjacent ranges', () async {
    final out = await ReadStoryTool(store, SeenLines()).execute(args([
      [3, 4],
      [0, 5],
      [7, 2],
    ]),);
    for (var i = 0; i < 9; i++) {
      expect(RegExp('^L$i ', multiLine: true).allMatches(out).length, 1);
    }
    expect(out, isNot(contains('未读')));
  });
  test('line budget reports the remainder and later passages', () async {
    final seen = SeenLines();
    final out = await ReadStoryTool(store, seen).execute(args([
      [0, 290],
      [300, 30],
      [350, 10],
    ]),);
    expect(seen.covers(id, 300, 309), isTrue);
    expect(seen.covers(id, 310, 310), isFalse);
    expect(out, contains('start=310, count=20'));
    expect(out, contains('start=350, count=10'));
    expect(RegExp('^L', multiLine: true).allMatches(out).length, 300);
  });
  test('character budget spans all passages and reports every remaining range',
      () async {
    final seen = SeenLines();
    final out = await ReadStoryTool(store, seen).execute({
      'story_id': 'fixture/long.txt',
      'ranges': [
        [0, 1],
        [2, 2],
      ],
    });
    expect(seen.covers('fixture/long.txt', 0, 0), isTrue);
    expect(seen.covers('fixture/long.txt', 2, 2), isFalse);
    expect(out, contains('start=2, count=2'));
  });
  test('partial and complete context omission retain gaps and context prefix',
      () async {
    final ledger = ContextLedger()
      ..record(0, SeenLines()..addRange(id, 0, 1), step: 1, callKey: 'a');
    final seen = SeenLines();
    final tool = ReadStoryTool(store, seen, ledger: ledger);
    final out = await tool.execute(args([
      [0, 2],
      [10, 2],
    ]),);
    expect(out, contains('原文仍在上文'));
    expect(out, contains('L10 '));
    expect(seen.covers(id, 10, 11), isTrue);
    ledger.record(1, seen, step: 2, callKey: 'b');
    final blocked = await tool.execute(args([
      [0, 2],
      [10, 2],
    ]),);
    expect(blocked, startsWith(inContextPrefix));
    expect(blocked, contains('（L2–L9 未读）'));
    expect(blocked, isNot(contains('L10 [甲]')));
  });
  test('gate rejects malformed ranges and gives a usable example', () {
    final tool = ReadStoryTool(store, SeenLines());
    for (final bad in [
      [
        [0],
      ],
      [
        [0, 1, 2],
      ],
      [
        [-1, 2],
      ],
      [
        [0, 0],
      ],
      [
        ['0', 2],
      ],
      [
        [0.5, 2],
      ],
      List.filled(5, [0, 1]),
      '0,2',
    ]) {
      final checked = checkToolCall(
          ToolCall(
              id: 'r', name: 'read_story', arguments: jsonEncode(args(bad)),),
          tool,
          ['read_story'],);
      expect(checked.ok, isFalse, reason: '$bad');
      expect(checked.error, contains('[[0,200],[250,20]]'));
    }
    expect(
        checkToolCall(
            ToolCall(
                id: 'r',
                name: 'read_story',
                arguments: jsonEncode(args([
                  [0, 2],
                ]),),),
            tool,
            ['read_story'],).ok,
        isTrue,);
  });
  test('null or empty ranges mean not given: start/count apply', () async {
    final tool = ReadStoryTool(store, SeenLines());
    for (final none in [null, <Object?>[]]) {
      final call = {...args(none), 'start': 5, 'count': 2};
      expect(
          checkToolCall(
              ToolCall(id: 'r', name: 'read_story', arguments: jsonEncode(call)),
              tool,
              ['read_story'],).ok,
          isTrue,
          reason: '$none',);
      final out = await tool.execute(call);
      expect(out, contains('L5 '));
      expect(out, contains('L6 '));
      expect(out, isNot(contains('L7 ')));
      expect(canonicalCallKey('read_story', call),
          canonicalCallKey(
              'read_story', {'story_id': id, 'start': 5, 'count': 2},),);
    }
  });
  test('the last passage says whether the chapter goes on', () async {
    final tool = ReadStoryTool(store, SeenLines());
    final middle = await tool.execute(args([
      [0, 2],
      [10, 2],
    ]),);
    expect(middle, contains('本章在 L11 之后还有；继续读用 start=12'));
    final end = await tool.execute(args([
      [0, 2],
      [395, 10],
    ]),);
    expect(end, contains('这一章到 L399 结束'));
  });
  test(
      'canonical key normalizes order and overlap and ignores overridden arguments',
      () {
    final first = args([
      [10, 2],
      [0, 3],
      [2, 2],
    ]);
    expect(
        canonicalCallKey('read_story', {...first, 'start': 9, 'count': 1}),
        canonicalCallKey(
            'read_story',
            args([
              [0, 4],
              [10, 2],
            ]),),);
    expect(
        canonicalCallKey('read_story', first),
        isNot(canonicalCallKey(
            'read_story',
            args([
              [0, 4],
              [11, 2],
            ]),),),);
  });
}
