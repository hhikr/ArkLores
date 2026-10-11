import 'dart:io';

import 'package:arklores/core/gamedata/gamedata_knowledge_store.dart';
import 'package:arklores/core/gamedata/story_catalog.dart';
import 'package:arklores/core/gamedata/story_vectors.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Opt-in acceptance check of a freshly built schema 5 knowledge base.
///
///   $env:ARKLORES_RUN_DB_CHECK='true'
///   $env:ARKLORES_GAMEDATA_DB="$PWD\build\gamedata_v5\arklores_gamedata_zh.db"
///   flutter test test/live/gamedata_v5_acceptance_test.dart
///
/// It checks structure only (no model calls): bindings point at rows,
/// owners exist, vectors have valid line ranges and load through the app's
/// own index loader, and the app reader returns line kinds.
void main() {
  final enabled = Platform.environment['ARKLORES_RUN_DB_CHECK'] == 'true';
  final dbPath = Platform.environment['ARKLORES_GAMEDATA_DB'] ?? '';

  setUpAll(() {
    sqfliteFfiInit();
    sqflite.databaseFactory = databaseFactoryFfi;
  });

  test('schema 5 knowledge base is consistent', () async {
    final db = await databaseFactoryFfi.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(readOnly: true),
    );
    addTearDown(db.close);

    Future<int> count(String sql) async =>
        (await db.rawQuery(sql)).single.values.first! as int;

    expect(
      (await db.rawQuery(
        "SELECT value FROM gamedata_manifest WHERE key = 'schema_version'",
      ))
          .single['value'],
      '5',
    );
    expect(
      await count(
        'SELECT COUNT(*) FROM entry_links l WHERE '
        'NOT EXISTS (SELECT 1 FROM entries e WHERE e.id = l.src) '
        'OR NOT EXISTS (SELECT 1 FROM entries e WHERE e.id = l.dst)',
      ),
      0,
      reason: 'every binding refers to two entries',
    );
    expect(
      await count(
        'SELECT COUNT(*) FROM entries e WHERE e.collection_id IS NOT NULL '
        'AND NOT EXISTS (SELECT 1 FROM collections c WHERE c.id = e.collection_id)',
      ),
      0,
      reason: 'every owner exists',
    );
    expect(
      await count(
        'SELECT COUNT(*) FROM normalized_records WHERE entry_id IS NULL',
      ),
      0,
      reason: 'every record belongs to an entry',
    );
    expect(
      await count(
        // A file with nothing but a title line (a stub, a camera test) is
        // not a story and gets no entry (`rebuildDerived`).
        'SELECT COUNT(*) FROM story_lines s WHERE NOT EXISTS '
        '(SELECT 1 FROM entries e WHERE e.id = \'story:\' || s.story_id) '
        'AND s.story_id IN (SELECT story_id FROM story_lines '
        "GROUP BY story_id HAVING SUM(kind <> 'title') > 0)",
      ),
      0,
      reason: 'every story has an entry',
    );
    expect(
      await count(
        'SELECT COUNT(*) FROM entries WHERE type = \'enemy\' AND '
        'NOT EXISTS (SELECT 1 FROM entry_links l WHERE l.src = entries.id)',
      ),
      lessThan(300),
      reason: 'most enemies are bound to a stage',
    );

    // Gameplay text stays out.
    expect(
      await count(
        "SELECT COUNT(*) FROM normalized_records WHERE content_type = 'enemy_profile' "
        "AND section <> '敌人'",
      ),
      0,
    );

    // Vectors.
    final index = await StoryVectorIndex.load(db);
    expect(index, isNotNull);
    expect(index!.dims, 512);
    expect(
      await count(
        'SELECT COUNT(*) FROM story_chunk_vectors v WHERE v.line_start > v.line_end '
        'OR v.line_end > (SELECT MAX(line_index) FROM story_lines l WHERE l.story_id = v.story_id)',
      ),
      0,
      reason: 'vector ranges lie inside their story',
    );

    // The app reader returns the line kinds.
    final sample = await db.rawQuery(
      "SELECT story_id FROM story_lines WHERE kind = 'subtitle' "
      'GROUP BY story_id ORDER BY COUNT(*) DESC LIMIT 1',
    );
    final store = GameDataKnowledgeStore(dbPath: dbPath);
    addTearDown(store.close);
    final page = await store.readStoryLines(
      storyId: '${sample.single['story_id']}',
      maxLines: 60,
    );
    expect(page.lines.map((l) => l.kind), contains('subtitle'));
  }, skip: enabled ? false : 'set ARKLORES_RUN_DB_CHECK=true',);

  // 0.14: the related collections `outline` ends with. Printed for a look
  // (which ones they are is not asserted: that depends on the database);
  // `ARKLORES_RELATED_OF` names more collections to print, separated by `,`.
  test('related collections of some collections', () async {
    final store = GameDataKnowledgeStore(dbPath: dbPath);
    addTearDown(store.close);
    final recent = await store.readOnlySql(
      "SELECT collection_id FROM story_catalog WHERE collection_type = 'ACTIVITY' "
      'GROUP BY collection_id HAVING COUNT(*) >= 10 '
      'ORDER BY MIN(start_time) DESC LIMIT 4',
    );
    final asked = (Platform.environment['ARKLORES_RELATED_OF'] ?? '')
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty);
    final ids = <String>[
      for (final row in recent.rows) '${row.first}',
      for (final name in asked)
        if (await store.storyCollection(name) case final found?)
          found.collectionId,
    ];
    expect(ids, isNotEmpty);
    for (final id in ids) {
      final watch = Stopwatch()..start();
      final related = await store.relatedCollections(id);
      final label = (await store.storyCollection(id))!.label;
      // ignore: avoid_print
      final shown = [
        for (final r in related)
          '${r.label}[${r.shared} 人'
              '${r.similarity == null ? '' : ' / ${r.similarity!.toStringAsFixed(3)}'}]',
      ].join(' ');
      // ignore: avoid_print
      print('$label（$id）${watch.elapsedMilliseconds} ms：$shown');
      expect(related, isNotEmpty, reason: id);
      expect(related.length, lessThanOrEqualTo(6));
      expect(related.map((r) => r.id), isNot(contains(id)));
      expect(related.map((r) => r.id).toSet(), hasLength(related.length));
    }
  }, skip: enabled ? false : 'set ARKLORES_RUN_DB_CHECK=true',);

  // 0.14: where a word's lines are, as `search` and `grep` write it.
  // Printed for a look, with the time of the keyword scan that counts it
  // (which collections come first is not asserted). The words: a few
  // speakers of the database, from the most heard down, and those named in
  // `ARKLORES_SPREAD_OF` (separated by `,`).
  test('the spread of some words over the collections', () async {
    final store = GameDataKnowledgeStore(dbPath: dbPath);
    addTearDown(store.close);
    final speakers = await store.readOnlySql(
      'SELECT speaker FROM story_lines WHERE LENGTH(speaker) >= 2 '
      'GROUP BY speaker ORDER BY COUNT(*) DESC LIMIT 400',
    );
    final terms = <String>{
      for (final at in [0, 20, 100, 399])
        if (at < speakers.rows.length) '${speakers.rows[at].first}',
      ...(Platform.environment['ARKLORES_SPREAD_OF'] ?? '')
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty),
    }.toList();
    expect(terms, isNotEmpty);
    // The first use reads every story's collection.
    final first = Stopwatch()..start();
    await store.termSpread({'-': 1});
    // ignore: avoid_print
    print('story groups: ${first.elapsedMilliseconds} ms');
    Future<void> check(List<String> words) async {
      final termLines = <String, int>{};
      final termStories = <String, Map<String, int>>{};
      final watch = Stopwatch()..start();
      await store.searchStoryLinesLike(
        words,
        termLines: termLines,
        termStories: termStories,
      );
      final scan = watch.elapsedMilliseconds;
      for (final word in words) {
        final spread = await store.termSpread(termStories[word] ?? const {});
        if (spread == null) {
          expect(termLines[word], 0, reason: word);
          continue;
        }
        // ignore: avoid_print
        print('$word（${formatTermSpread(spread)}）');
        expect(spread.lines, termLines[word], reason: word);
        expect(spread.listed.length, lessThanOrEqualTo(spreadMaxListed));
        expect(spread.dense.length, lessThanOrEqualTo(spreadMaxDense));
        final parts = [...spread.listed, ...spread.dense];
        expect(parts.map((p) => p.id).toSet(), hasLength(parts.length));
        expect(
          parts.fold<int>(0, (n, p) => n + p.lines),
          lessThanOrEqualTo(spread.lines),
        );
        expect(
          spread.listed.length + spread.dense.length + spread.restCount,
          spread.collections,
        );
      }
      // ignore: avoid_print
      print('${words.length} 个词的检索（含逐章计数）：$scan ms');
    }

    for (final word in terms) {
      await check([word]);
    }
    await check(terms.take(8).toList());
  }, skip: enabled ? false : 'set ARKLORES_RUN_DB_CHECK=true',);

  // 0.14: passages of other collections that read like one (`search` with
  // `near`). Printed for a look: some passages spread over the vectors, and
  // those named in `ARKLORES_NEAR_OF` (`<story_id>:<line>`, separated by
  // `,`).
  test('passages near some passages', () async {
    final store = GameDataKnowledgeStore(dbPath: dbPath);
    addTearDown(store.close);
    final picked = await store.readOnlySql(
      'SELECT story_id, line_start FROM story_chunk_vectors '
      'WHERE (rowid % 9001) = 7 LIMIT 6',
    );
    final spots = <(String, int)>[
      for (final row in picked.rows) ('${row[0]}', (row[1] as num).toInt()),
      for (final spot in (Platform.environment['ARKLORES_NEAR_OF'] ?? '')
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.contains(':')))
        (
          spot.substring(0, spot.lastIndexOf(':')),
          int.parse(spot.substring(spot.lastIndexOf(':') + 1)),
        ),
    ];
    expect(spots, isNotEmpty);
    for (final (storyId, line) in spots) {
      final watch = Stopwatch()..start();
      final near = await store.storyChunksNear(storyId, line);
      final ms = watch.elapsedMilliseconds;
      expect(near, isNotNull, reason: '$storyId:$line');
      final labels = await store.storyCatalogEntries(
        [storyId, for (final h in near!.hits) h.storyId],
      );
      String name(String id) => labels[id]?.label ?? id;
      // ignore: avoid_print
      print('${name(storyId)} L${near.lineStart}-${near.lineEnd}（$ms ms）：'
          '${near.hits.isEmpty ? '没有' : near.hits.map((h) => '${name(h.storyId)} L${h.lineStart} ${h.score.toStringAsFixed(2)}').join('；')}');
      expect(near.hits.length, lessThanOrEqualTo(nearMaxPassages));
      expect(near.hits.every((h) => h.score >= nearMinSimilarity), isTrue);
      expect(near.hits.map((h) => h.storyId), isNot(contains(storyId)));
    }
  }, skip: enabled ? false : 'set ARKLORES_RUN_DB_CHECK=true',);
}
