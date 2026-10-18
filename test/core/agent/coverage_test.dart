import 'dart:io';

import 'package:arklores/core/agent/coverage.dart';
import 'package:arklores/core/agent/lore_tools.dart';
import 'package:arklores/core/gamedata/gamedata_knowledge_store.dart';
import 'package:arklores/core/gamedata/story_catalog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/gamedata_fixture.dart';
import '../../support/temp_dir.dart';

/// The material code gathers before the model reads (unified refactor,
/// phase 1). Fixture names are fictional; the rules are the same for any
/// name.
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory dir;

  Future<GameDataKnowledgeStore> open(
    Future<void> Function(Database db) fill,
  ) async {
    final path = p.join(dir.path, 'kb.db');
    final db = await createGameDataDb(path, catalog: true);
    await fill(db);
    await db.close();
    return GameDataKnowledgeStore(dbPath: path);
  }

  Future<void> catalog(
    Database db,
    String storyId,
    String collectionId, {
    String type = 'ACTIVITY_STORY',
    int sort = 1,
    int? startTime,
    int? showTime,
  }) =>
      db.insert(
        storyCatalogTable,
        StoryCatalogEntry(
          storyId: storyId,
          collectionId: collectionId,
          collectionName: collectionId,
          collectionType: type,
          storySort: sort,
          storyName: storyId,
          startTime: startTime,
          showTime: showTime,
        ).toRow(),
      );

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('arklores_coverage');
  });
  tearDown(() => deleteTempDir(dir));

  test('a one-character name is found as a speaker only', () async {
    final store = await open((db) async {
      await insertStory(db, 'act_x/s1.txt', [
        '灯：我在这里。',
        '路灯一盏一盏亮起来。',
        '守灯人：灯快灭了。',
      ]);
    });
    final one = await store.anchorLines('灯');
    expect(
      [for (final l in one) (l.storyId, l.lineIndex, l.spoken)],
      [('act_x/s1.txt', 0, true)],
    );
    final two = await store.anchorLines('守灯人');
    expect([for (final l in two) l.lineIndex], [2]);
    expect(two.single.spoken, isTrue);
  });

  test('two anchors in one scene rank above one anchor said often', () async {
    final store = await open((db) async {
      await insertStory(db, 'act_x/often.txt', [
        for (var i = 0; i < 60; i++)
          i == 55
              ? '远处是钟楼。'
              : (i < 30 && i % 4 == 0 ? '守灯人：又一句。' : '风。'),
      ]);
      await insertStory(db, 'act_x/scene.txt', [
        for (var i = 0; i < 20; i++)
          i == 10
              ? '守灯人：走吧。'
              : i == 12
                  ? '他们登上钟楼。'
                  : '雨。',
      ]);
    });
    final coverage =
        await CoverageBuilder(store).build(['守灯人', '钟楼'], budgetChars: 1);
    expect(coverage.stories, {'act_x/scene.txt'});
    expect(coverage.located, ['act_x/often.txt']);
    // The scene is given around both anchors.
    final lines = {
      for (final pa in coverage.passages)
        for (final l in pa.lines) l.lineIndex,
    };
    expect(lines.containsAll([10, 12]), isTrue);
  });

  test('one collection gives at most three stories before others get a turn',
      () async {
    // Every story is three lines (32 characters as counted), the anchor in
    // the middle, so each is given whole.
    const story = ['风。', '守灯人：一句话。', '雨。'];
    final store = await open((db) async {
      for (var i = 1; i <= 5; i++) {
        await insertStory(db, 'act_a/s$i.txt', story);
        await catalog(db, 'act_a/s$i.txt', 'act_a', sort: i);
      }
      await insertStory(db, 'act_b/s1.txt', story);
      await catalog(db, 'act_b/s1.txt', 'act_b');
    });
    final coverage = await CoverageBuilder(store).build(
      ['守灯人'],
      budgetChars: 4 * 32,
      // The hint ranks every act_a story above act_b's.
      hinted: {for (var i = 1; i <= 5; i++) 'act_a/s$i.txt'},
    );
    expect(coverage.stories, {
      'act_a/s1.txt',
      'act_a/s2.txt',
      'act_a/s3.txt',
      'act_b/s1.txt',
    });
    expect(coverage.chars, lessThanOrEqualTo(4 * 32));
  });

  test('material is in release order and registered as read', () async {
    final store = await open((db) async {
      for (final id in ['main_9/a.txt', 'act_c/a.txt', 'main_2/a.txt']) {
        await insertStory(db, id, ['守灯人：在。']);
      }
      // A main chapter without a time comes after every dated story.
      await catalog(db, 'main_9/a.txt', 'main_9', type: 'MAINLINE');
      await catalog(db, 'act_c/a.txt', 'act_c', startTime: 2000);
      await catalog(
        db,
        'main_2/a.txt',
        'main_2',
        type: 'MAINLINE',
        showTime: 1000,
      );
      await insertRecord(
        db,
        'rec_keeper',
        contentType: 'operator_profile',
        category: 'operator',
        content: '守灯人在钟楼住了很多年。',
        fields: {'title': '档案'},
      );
    });
    final coverage = await CoverageBuilder(store).build(['守灯人']);
    expect(
      [for (final pa in coverage.passages) pa.storyId],
      ['main_2/a.txt', 'act_c/a.txt', 'main_9/a.txt'],
    );
    final text = coverage.render();
    expect(text, contains('守灯人（3 篇 3 行，其中说话 3 行）'));
    expect(text.indexOf('main_2/a.txt'), lessThan(text.indexOf('act_c/a.txt')));
    expect(text, contains('record:rec_keeper'));

    final seen = SeenLines();
    coverage.register(seen);
    expect(seen.seenRanges('act_c/a.txt', 0, 0), [(0, 0)]);
    expect(seen.hasRecord('rec_keeper'), isTrue);
    expect(seen.recordIsPartial('rec_keeper'), isTrue);
  });

  test('a name not in the text is said so', () async {
    final store = await open((db) async {
      await insertStory(db, 'act_x/s1.txt', ['守灯人：在。']);
    });
    final coverage = await CoverageBuilder(store).build(['无人知晓']);
    expect(coverage.passages, isEmpty);
    expect(coverage.render(), contains('无人知晓（原文里没有）'));
  });
}
