// 0.14: vectors for the records outside the story text — how a record is
// chunked, how an update finds what to embed again, and that a search by
// meaning lists a record no word of the query occurs in. Fixture names are
// fictional.
import 'dart:io';

import 'package:arklores/core/agent/lore_tools.dart';
import 'package:arklores/core/agent/tools/search_tool.dart';
import 'package:arklores/core/gamedata/gamedata_knowledge_store.dart';
import 'package:arklores/core/gamedata/record_vectors.dart';
import 'package:arklores/core/gamedata/story_vector_updater.dart';
import 'package:arklores/core/llm/embedding_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/gamedata_fixture.dart';
import '../../support/sqlite.dart';
import '../../support/temp_dir.dart';

/// Texts about light, about the sea, and everything else, each on its own
/// axis.
class _TopicEmbedder implements EmbeddingClient {
  final List<String> embedded = [];

  @override
  String get model => 'emb';

  @override
  int get dimensions => 4;

  @override
  int get tokensUsed => embedded.length;

  @override
  Future<List<List<double>>> embed(List<String> texts) async {
    embedded.addAll(texts);
    return [
      for (final t in texts)
        t.contains('灯') || t.contains('照明')
            ? [1.0, 0.0, 0.0, 0.0]
            : t.contains('海')
                ? [0.0, 1.0, 0.0, 0.0]
                : [0.0, 0.0, 1.0, 0.0],
    ];
  }
}

void main() {
  setUpAll(useSqfliteFfi);

  group('chunking', () {
    test('a short record is one chunk, headed by whose it is', () {
      final chunks = chunkRecord(
        id: 'r1',
        owner: '看守人',
        title: '交谈1',
        content: '今晚的灯很亮。',
      );
      expect(chunks, hasLength(1));
      expect(chunks.single.chunkId, 'r1#0');
      expect(chunks.single.text, '看守人 · 交谈1：今晚的灯很亮。');
      expect((chunks.single.charStart, chunks.single.charEnd), (0, 7));
      // The owner is not said twice, nothing is said for nothing.
      expect(
        chunkRecord(id: 'r', owner: '旧灯', title: '旧灯', content: '一盏灯。')
            .single
            .text,
        '旧灯：一盏灯。',
      );
      expect(chunkRecord(id: 'r', content: '一盏灯。').single.text, '一盏灯。');
      expect(chunkRecord(id: 'r', content: '  \n'), isEmpty);
    });

    test('a long record is cut at its sections, then between lines', () {
      final content = [
        '## 基础档案',
        '第一节。',
        '## 档案资料一',
        for (var i = 0; i < 60; i++) '第二节的第 $i 行，写得稍微长一些。',
        '## 档案资料二',
        '很长的一行${'字' * 2000}',
      ].join('\n');
      final chunks = chunkRecord(id: 'doc', title: '看守人', content: content);
      expect(chunks.length, greaterThan(4));
      expect(chunks.first.text, '看守人：## 基础档案\n第一节。');
      for (final c in chunks) {
        expect(c.charEnd - c.charStart, lessThanOrEqualTo(recordChunkChars));
        expect(c.text, startsWith('看守人：'));
      }
      // The ranges follow one another and cover the whole text.
      expect(chunks.first.charStart, 0);
      expect(chunks.last.charEnd, content.length);
      for (var i = 1; i < chunks.length; i++) {
        expect(chunks[i].charStart, chunks[i - 1].charEnd);
        expect(chunks[i].part, i);
      }
      // A section starts a chunk of its own.
      expect(
        chunks.where((c) => content.startsWith('## ', c.charStart)),
        hasLength(greaterThanOrEqualTo(3)),
      );
      // The same input, the same chunks.
      final again = chunkRecord(id: 'doc', title: '看守人', content: content);
      expect(
        again.map((c) => c.textHash).toList(),
        chunks.map((c) => c.textHash).toList(),
      );
    });
  });

  group('in a database', () {
    late Directory dir;
    late String path;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('arklores_record_vectors');
      path = p.join(dir.path, 'kb.db');
      final db = await createGameDataDb(path);
      await insertEntity(db, 'char_fx_keeper', '看守人');
      await insertStory(db, 'activities/x/level_x_01.txt', [
        '甲：出发吧。',
        '海面很平静。',
      ]);
      await insertRecord(
        db,
        'rec_voice',
        contentType: 'operator_voice',
        category: 'operator',
        subtype: 'voice',
        content: '夜里总要有人看着它。',
        fields: {'entity_id': 'char_fx_keeper', 'title': '交谈1'},
      );
      await insertRecord(
        db,
        'rec_lamp',
        contentType: 'item_description',
        category: 'world_item',
        subtype: 'item',
        content: '一盏旧灯，守了很多年。',
        fields: {'entity_name': '旧物', 'title': '旧物'},
      );
      // A copy of story text is searched as story text, not as a record.
      await insertRecord(
        db,
        'rec_story_copy',
        contentType: 'story_line',
        content: '甲：出发吧。',
      );
      await db.insert('entity_documents', {
        'id': 'doc_keeper',
        'game': 'arknights',
        'language': 'zh',
        'entity_id': 'char_fx_keeper',
        'entity_name': '看守人',
        'entity_type': 'operator',
        'document_type': 'operator_profile_bundle',
        'title': '看守人',
        'summary': '',
        'content': '## 基础档案\n来自海边的人。',
        'source_paths': '[]',
        'source_record_ids': '[]',
      });
      await db.close();
    });

    tearDown(() => deleteTempDir(dir));

    test('an update embeds what is new or changed and drops what is gone',
        () async {
      final db = await databaseFactoryFfi.openDatabase(path);
      addTearDown(db.close);
      final client = _TopicEmbedder();

      final plan = await planVectorUpdate(db);
      expect(plan.pendingRecordChunks, 3);
      expect(plan.pendingChunks, greaterThanOrEqualTo(4)); // with the story
      expect(plan.nothingToDo, isFalse);

      final progress = <(int, int)>[];
      final first = await updateStoryVectors(
        db: db,
        client: client,
        onRecordProgress: (done, total) => progress.add((done, total)),
      );
      expect(first.chunks, 4);
      expect(progress.last, (3, 3));
      // The voice line is embedded with the name of its operator.
      expect(client.embedded, contains('看守人 · 交谈1：夜里总要有人看着它。'));
      Future<List<Object?>> ids() async => [
            for (final r in await db.rawQuery(
              'SELECT chunk_id FROM $recordChunkVectorsTable ORDER BY chunk_id',
            ))
              r['chunk_id'],
          ];
      expect(await ids(), ['doc_keeper#0', 'rec_lamp#0', 'rec_voice#0']);
      final after = await planVectorUpdate(db);
      expect(after.nothingToDo, isTrue);
      expect(after.existingRecordVectors, 3);
      expect(
        (await db.query(
          'gamedata_manifest',
          where: 'key = ?',
          whereArgs: [manifestRecordChunking],
        ))
            .single['value'],
        recordChunkingSignature,
      );

      // One record's text changes, one is removed, the operator is renamed.
      await db.update(
        'normalized_records',
        {'content': '一盏新灯。'},
        where: "id = 'rec_lamp'",
      );
      await db.delete('entity_documents', where: "id = 'doc_keeper'");
      await db.update(
        'entities',
        {'name': '巡夜人'},
        where: "id = 'char_fx_keeper'",
      );
      expect((await planVectorUpdate(db)).pendingRecordChunks, 2);
      client.embedded.clear();
      final second = await updateStoryVectors(db: db, client: client);
      expect(second.chunks, 2);
      expect(
        client.embedded,
        unorderedEquals(['旧物：一盏新灯。', '巡夜人 · 交谈1：夜里总要有人看着它。']),
      );
      expect(await ids(), ['rec_lamp#0', 'rec_voice#0']);
      expect((await planVectorUpdate(db)).nothingToDo, isTrue);
    });

    test('a search by meaning lists a record no word of the query is in',
        () async {
      final db = await databaseFactoryFfi.openDatabase(path);
      final client = _TopicEmbedder();
      await updateStoryVectors(db: db, client: client);
      await db.close();

      final store = GameDataKnowledgeStore(dbPath: path);
      addTearDown(store.close);
      final near = await store.searchRecordsByVector([1, 0, 0, 0], limit: 2);
      expect(near.first.id, 'rec_lamp');
      expect(near.first.snippet, '一盏旧灯，守了很多年。');
      expect(near.first.score, closeTo(1, 0.01));

      final seen = SeenLines();
      final out = (await SearchTool(store, seen, embeddingClient: client)
              .run('照明的器具'))
          .text;
      expect(out, contains('照明的器具（0 行'));
      expect(out, contains('record:rec_lamp | world_item·item | 旧物'));
      // Only the excerpt was shown.
      expect(seen.recordIsPartial('rec_lamp'), isTrue);
      // What is far from the query is not listed for being a vector.
      expect(out, isNot(contains('record:doc_keeper')));
    });
  });
}
