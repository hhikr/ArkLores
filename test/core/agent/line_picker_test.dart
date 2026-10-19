import 'dart:io';

import 'package:arklores/core/agent/coverage.dart';
import 'package:arklores/core/agent/line_picker.dart';
import 'package:arklores/core/agent/lore_tools.dart';
import 'package:arklores/core/gamedata/gamedata_knowledge_store.dart';
import 'package:arklores/core/gamedata/story_coverage_models.dart';
import 'package:arklores/core/llm/llm_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/gamedata_fixture.dart';
import '../../support/temp_dir.dart';

/// Picking lines from a wide gathering (unified refactor, phase 2: S5).
/// Fixture names are fictional.
void main() {
  CoveragePassage passage(String story, int first, int last) =>
      CoveragePassage(story, first, last, [
        for (var i = first; i <= last; i++)
          StoryLineEntry(lineIndex: i, content: '第$i行。', speaker: '甲'),
      ]);

  Coverage wide(List<CoveragePassage> passages) => Coverage(
        footprints: const [],
        passages: passages,
        located: const [],
        records: const [],
        labels: const {},
      );

  test('picked ranges are copied with a line either side, in reading order',
      () async {
    final client = _Client((request) => request.contains('a.txt')
        // The most useful first; one range is outside the segment, one in
        // a story it does not hold.
        ? '{"keep": ["a.txt:20-21", "a.txt:500", "z.txt:1", "a.txt:L3"]}'
        : '{"keep": ["b.txt:5"]}',);
    final picked = await LinePicker(client, segmentChars: 1).pick(
      '问题',
      wide([passage('a.txt', 0, 30), passage('b.txt', 0, 10)]),
    );
    expect(picked.segments, 2);
    expect(picked.failed, 0);
    expect(
      [for (final p in picked.passages) '${p.storyId} ${p.first}-${p.last}'],
      ['a.txt 2-4', 'a.txt 19-22', 'b.txt 4-6'],
    );
    expect(client.requests.first, contains('玩家的问题：问题'));
    expect(client.requests.first, contains('L20 [甲] 第20行。'));
  });

  test('each segment gets its share of the budget before any gets more',
      () async {
    // A line is 12 characters as counted (4 + 8).
    final client = _Client((request) => request.contains('a.txt')
        ? '{"keep": ["a.txt:10-29"]}'
        : '{"keep": ["b.txt:3"]}',);
    final picked = await LinePicker(client, segmentChars: 1).pick(
      '问题',
      wide([passage('a.txt', 0, 40), passage('b.txt', 0, 10)]),
      budgetChars: 120,
    );
    final stories = [for (final p in picked.passages) p.storyId];
    expect(stories, contains('b.txt'));
    final chars = picked.passages.fold(0, (n, p) => n + p.chars);
    // One range runs over its share by at most itself.
    expect(chars, lessThanOrEqualTo(120 + 22 * 12));
  });

  test('a failed segment gives the narrow lines of its stories', () async {
    final client = _Client((request) =>
        request.contains('a.txt') ? null : '{"keep": ["b.txt:5"]}',);
    final picked = await LinePicker(client, segmentChars: 1).pick(
      '问题',
      wide([passage('a.txt', 0, 30), passage('b.txt', 0, 10)]),
      fallback: [passage('a.txt', 8, 12)],
    );
    expect(picked.failed, 1);
    expect(
      [for (final p in picked.passages) '${p.storyId} ${p.first}-${p.last}'],
      ['a.txt 8-12', 'b.txt 4-6'],
    );
  });

  group('gather with a picker', () {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    late Directory dir;
    setUp(() async {
      dir = await Directory.systemTemp.createTemp('arklores_picker');
    });
    tearDown(() => deleteTempDir(dir));

    Future<GameDataKnowledgeStore> open(int stories, int lines) async {
      final path = p.join(dir.path, 'kb.db');
      final db = await createGameDataDb(path, catalog: true);
      for (var s = 0; s < stories; s++) {
        await insertStory(db, 'act_x/s$s.txt', [
          for (var i = 0; i < lines; i++)
            i % 10 == 0 ? '守灯人：第$i句。' : '风吹过第$i行的街道，灯一盏一盏亮起来。',
        ]);
      }
      await db.close();
      return GameDataKnowledgeStore(dbPath: path);
    }

    test('wide material that fits is given whole, without a call', () async {
      final store = await open(1, 30);
      final client = _Client((_) => throw StateError('no call expected'));
      final seen = SeenLines();
      final tool = GatherTool(store, seen, picker: LinePicker(client))
        ..question = '守灯人做了什么？';
      final text = await tool.execute({
        'names': ['守灯人'],
      });
      expect(client.requests, isEmpty);
      // Eight lines either side of the anchor lines (0, 10, 20).
      expect(seen.seenRanges('act_x/s0.txt', 0, 29), [(0, 28)]);
      expect(text, isNot(contains('挑出了')));
    });

    test('wider material is picked; what was picked is registered', () async {
      final store = await open(12, 120);
      final client = _Client((request) {
        final story = RegExp(r'act_x/s\d+\.txt').firstMatch(request)!.group(0);
        return '{"keep": ["$story:44-46"]}';
      });
      final seen = SeenLines();
      final tool = GatherTool(store, seen, picker: LinePicker(client))
        ..question = '守灯人做了什么？';
      final text = await tool.execute({
        'names': ['守灯人'],
      });
      expect(client.requests, isNotEmpty);
      expect(text, contains('挑出了与问题相关的行'));
      expect(text, contains('L45 '));
      final story = seen.stories.first;
      expect(seen.seenRanges(story, 43, 47), [(43, 47)]);
      // Lines not picked (nor around a pick) are not registered.
      expect(seen.seenRanges(story, 0, 0), isEmpty);
    });
  });
}

class _Client extends LLMClient {
  _Client(this.reply);

  /// The reply to a request (its user message); null fails the call.
  final String? Function(String request) reply;
  final List<String> requests = [];

  @override
  Future<String> chat(
    List<Message> messages, {
    List<Map<String, dynamic>>? tools,
    double temperature = 0.7,
    int maxTokens = 2048,
    List<String>? stop,
  }) async {
    final request = messages.last.content;
    requests.add(request);
    final r = reply(request);
    if (r == null) throw StateError('failed');
    return r;
  }

  @override
  Stream<CompletionDelta> streamTurn(
    List<Message> messages, {
    List<Map<String, dynamic>>? tools,
    String? toolChoice,
    double temperature = 0.7,
    int maxTokens = 2048,
  }) =>
      throw UnimplementedError();
}
