/// Keeps the optional vectors (`story_chunk_vectors`, and 0.14 the records'
/// `record_chunk_vectors`) up to date after the knowledge base changed: plan
/// what is missing, show what it costs, and embed only that.
///
/// Records (archives, voice lines, descriptions — everything outside the
/// story text) are compared by a hash of each chunk's text: a new or
/// changed one is embedded, the vector of one that is gone is removed.
///
/// An incremental update drops the vectors of the stories it changed or
/// removed (their line numbers moved) and adds stories without vectors. This
/// library finds those stories, estimates the work for the user ([VectorPlan])
/// and embeds them ([updateStoryVectors]). A story is written whole or not
/// at all, so an interrupted run resumes where it stopped.
///
/// Pure Dart over `sqflite_common`, so the app and the desktop tools share it.
library;

import 'package:sqflite_common/sqlite_api.dart';

import '../llm/embedding_client.dart';
import 'record_vectors.dart';
import 'story_vectors.dart';

/// Chinese text costs about this many tokens per character on the embedding
/// models in use (measured: see `docs/GAMEDATA_BUILD_PIPELINE.md`).
const double embeddingTokensPerChar = 0.7;

/// Bailian's price for the embedding model, yuan per 1000 tokens. Used only
/// to give the user an estimate; the provider's bill is the truth, and other
/// providers have other prices (the plan then shows tokens only).
const double bailianYuanPer1kTokens = 0.0005;

/// Chunks overlap (12 lines per 8-line step): each line is embedded about
/// 1.5 times.
const double _overlapFactor = 1.5;

/// What the next vector update would embed.
class VectorPlan {
  const VectorPlan({
    required this.hasTable,
    required this.existingVectors,
    required this.storiesWithVectors,
    required this.pendingStories,
    required this.pendingChunks,
    required this.pendingChars,
    this.existingRecordVectors = 0,
    this.pendingRecordChunks = 0,
    this.model,
    this.dims,
  });

  /// Whether the database has the vector table at all.
  final bool hasTable;

  /// The model and size the existing vectors were made with (manifest).
  final String? model;
  final int? dims;
  final int existingVectors;
  final int storiesWithVectors;

  /// Stories that have lines but no vectors.
  final int pendingStories;

  /// Estimated chunks and characters to embed (overlap included), stories
  /// and records together.
  final int pendingChunks;
  final int pendingChars;

  /// Records: vectors there are, and chunks that are new or changed
  /// (counted in [pendingChunks] too).
  final int existingRecordVectors;
  final int pendingRecordChunks;

  /// No vectors yet: this would be the first (complete) vector build.
  bool get isFirstBuild => existingVectors == 0;

  bool get nothingToDo => pendingStories == 0 && pendingRecordChunks == 0;

  int get estimatedTokens => (pendingChars * embeddingTokensPerChar).round();

  /// Estimated cost in yuan at [yuanPer1kTokens].
  double estimatedYuan([double yuanPer1kTokens = bailianYuanPer1kTokens]) =>
      estimatedTokens / 1000 * yuanPer1kTokens;
}

/// Computes the [VectorPlan] of [db].
Future<VectorPlan> planVectorUpdate(DatabaseExecutor db) async {
  final hasTable = (await db.rawQuery(
    "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?",
    [storyChunkVectorsTable],
  ))
      .isNotEmpty;
  final manifest = {
    for (final r in await db.rawQuery(
      'SELECT key, value FROM gamedata_manifest WHERE key IN (?, ?)',
      [manifestEmbeddingModel, manifestEmbeddingDims],
    ))
      '${r['key']}': '${r['value']}',
  };
  var vectors = 0, withVectors = 0;
  if (hasTable) {
    final v = await db.rawQuery(
      'SELECT COUNT(*) AS n, COUNT(DISTINCT story_id) AS s '
      'FROM $storyChunkVectorsTable',
    );
    vectors = (v.first['n'] as num).toInt();
    withVectors = (v.first['s'] as num).toInt();
  }
  final hasKind = (await db.rawQuery('PRAGMA table_info(story_lines)'))
      .any((c) => c['name'] == 'kind');
  // `NOT IN (subquery)` is evaluated once into a temporary index; the vector
  // table has no index on story_id, so a correlated NOT EXISTS per line would
  // compare every line with every vector.
  final withoutVectors = hasTable
      ? 'AND l.story_id NOT IN '
          '(SELECT story_id FROM $storyChunkVectorsTable)'
      : '';
  final rows = await db.rawQuery(
    'SELECT COUNT(*) AS stories, '
    'SUM(CASE WHEN n <= $chunkWindow THEN 1 '
    'ELSE (n - $chunkWindow + $chunkStride - 1) / $chunkStride + 1 END) AS chunks, '
    'SUM(chars) AS chars FROM ('
    'SELECT l.story_id, COUNT(*) AS n, '
    'SUM(LENGTH(l.content) + LENGTH(IFNULL(l.speaker, \'\')) + 1) AS chars '
    'FROM story_lines l '
    "WHERE ${hasKind ? "l.kind <> 'system'" : '1 = 1'} $withoutVectors "
    'GROUP BY l.story_id)',
  );
  final r = rows.first;
  final rawChars = (r['chars'] as num?)?.toDouble() ?? 0;
  final records = await _RecordDiff.of(db);
  return VectorPlan(
    hasTable: hasTable,
    model: manifest[manifestEmbeddingModel],
    dims: int.tryParse(manifest[manifestEmbeddingDims] ?? ''),
    existingVectors: vectors,
    storiesWithVectors: withVectors,
    pendingStories: (r['stories'] as num?)?.toInt() ?? 0,
    pendingChunks:
        ((r['chunks'] as num?)?.toInt() ?? 0) + records.pending.length,
    pendingChars: (rawChars * _overlapFactor).round() +
        records.pending.fold<int>(0, (n, c) => n + c.text.length),
    existingRecordVectors: records.existing,
    pendingRecordChunks: records.pending.length,
  );
}

/// The records' chunks against the vectors the database has.
class _RecordDiff {
  _RecordDiff(this.pending, this.stale, this.existing);

  /// Chunks without a vector of their current text.
  final List<RecordChunk> pending;

  /// Vectors of chunks that are gone.
  final List<String> stale;
  final int existing;

  static Future<_RecordDiff> of(DatabaseExecutor db) async {
    final hasTable = (await db.rawQuery(
      "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?",
      [recordChunkVectorsTable],
    ))
        .isNotEmpty;
    final have = <String, String>{
      if (hasTable)
        for (final r in await db.rawQuery(
          'SELECT chunk_id, text_hash FROM $recordChunkVectorsTable',
        ))
          '${r['chunk_id']}': '${r['text_hash']}',
    };
    final chunks = await recordChunksOf(db);
    final current = <String>{};
    final pending = <RecordChunk>[];
    for (final c in chunks) {
      current.add(c.chunkId);
      if (have[c.chunkId] != c.textHash) pending.add(c);
    }
    return _RecordDiff(
      pending,
      // (A chunk whose text changed is pending: its row is replaced.)
      [
        for (final id in have.keys)
          if (!current.contains(id)) id,
      ],
      have.length,
    );
  }
}

/// The outcome of [updateStoryVectors].
class VectorUpdateResult {
  const VectorUpdateResult({
    required this.stories,
    required this.chunks,
    required this.tokensUsed,
    required this.cancelled,
  });

  final int stories;

  /// Chunks embedded, stories and records together.
  final int chunks;

  /// Tokens the provider reported (0 when it reports none).
  final int tokensUsed;
  final bool cancelled;
}

/// Thrown when the configured embedding model or size differs from the one
/// the existing vectors were made with (mixing them makes search wrong).
class VectorModelMismatch implements Exception {
  const VectorModelMismatch({
    required this.have,
    required this.want,
  });

  final String have;
  final String want;

  @override
  String toString() =>
      'Existing vectors were made with $have; the configured model is $want.';
}

/// Embeds every story without vectors, then every record chunk that is new
/// or changed, and stores the result in [db] (a writable connection).
/// Existing vectors stay; the tables and their manifest rows are created
/// when missing. [onRecordProgress]: record chunks done of those to embed.
///
/// Throws [VectorModelMismatch] when vectors from another model or size exist.
Future<VectorUpdateResult> updateStoryVectors({
  required Database db,
  required EmbeddingClient client,
  void Function(int doneStories, int totalStories, int chunks)? onProgress,
  void Function(int doneChunks, int totalChunks)? onRecordProgress,
  bool Function()? shouldCancel,
  int concurrency = 3,
}) async {
  await db.execute(storyChunkVectorsDdl);
  await db.execute(storyChunkVectorsIndexDdl);
  final manifest = {
    for (final r in await db.rawQuery(
      'SELECT key, value FROM gamedata_manifest WHERE key IN (?, ?)',
      [manifestEmbeddingModel, manifestEmbeddingDims],
    ))
      '${r['key']}': '${r['value']}',
  };
  final haveModel = manifest[manifestEmbeddingModel];
  final haveDims = manifest[manifestEmbeddingDims];
  final existing = (await db.rawQuery(
    'SELECT COUNT(*) AS n FROM $storyChunkVectorsTable',
  ))
      .first['n'] as num;
  if (existing > 0 &&
      haveModel != null &&
      (haveModel != client.model || haveDims != '${client.dimensions}')) {
    throw VectorModelMismatch(
      have: '$haveModel@$haveDims',
      want: '${client.model}@${client.dimensions}',
    );
  }

  final hasKind = (await db.rawQuery('PRAGMA table_info(story_lines)'))
      .any((c) => c['name'] == 'kind');
  final stories = await db.rawQuery(
    "SELECT s.story_id, CASE WHEN s.scope_id IS NULL OR s.scope_id = '' "
    "THEN s.scope_type ELSE s.scope_type || ':' || s.scope_id END AS scope_key "
    'FROM story_scopes s WHERE s.story_id NOT IN '
    '(SELECT story_id FROM $storyChunkVectorsTable) '
    // A story of tutorial text only has nothing to embed.
    "${hasKind ? "AND s.story_id IN (SELECT story_id FROM story_lines WHERE kind <> 'system') " : ''}"
    'ORDER BY s.story_id',
  );
  var doneStories = 0, doneChunks = 0;
  final tokensBefore = client.tokensUsed;
  var cancelled = false;
  var next = 0;

  Future<void> worker() async {
    while (true) {
      if (shouldCancel != null && shouldCancel()) {
        cancelled = true;
        return;
      }
      if (next >= stories.length) return;
      final story = stories[next++];
      final storyId = '${story['story_id']}';
      final lines = await db.rawQuery(
        "SELECT line_index, speaker, content${hasKind ? ', kind' : ''} FROM story_lines "
        "WHERE story_id = ? ${hasKind ? "AND kind <> 'system'" : ''} "
        'ORDER BY line_index',
        [storyId],
      );
      final chunks = chunkStory(storyId, story['scope_key'] as String?, [
        for (final l in lines)
          ChunkLine(
            (l['line_index'] as num).toInt(),
            l['speaker'] as String?,
            '${l['content'] ?? ''}',
            isBreak: l['kind'] == sectionLineKind,
          ),
      ]);
      if (chunks.isNotEmpty) {
        final vectors = await client.embed([for (final c in chunks) c.text]);
        await db.transaction((txn) async {
          for (var i = 0; i < chunks.length; i++) {
            final q = quantize(vectors[i]);
            await txn.insert(
              storyChunkVectorsTable,
              {
                'chunk_id': chunks[i].chunkId,
                'story_id': storyId,
                'scope_id': chunks[i].scopeId,
                'line_start': chunks[i].lineStart,
                'line_end': chunks[i].lineEnd,
                'scale': q.scale,
                'vec': q.values.buffer.asUint8List(
                  q.values.offsetInBytes,
                  q.values.lengthInBytes,
                ),
              },
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          }
        });
        doneChunks += chunks.length;
      }
      doneStories++;
      onProgress?.call(doneStories, stories.length, doneChunks);
    }
  }

  await Future.wait([for (var w = 0; w < concurrency; w++) worker()]);

  // Records: remove what no longer matches, embed what is missing. A batch
  // is written whole, so an interrupted run resumes where it stopped.
  await db.execute(recordChunkVectorsDdl);
  await db.execute(recordChunkVectorsIndexDdl);
  final records = await _RecordDiff.of(db);
  if (records.stale.isNotEmpty) {
    await db.transaction((txn) async {
      for (final id in records.stale) {
        await txn.delete(
          recordChunkVectorsTable,
          where: 'chunk_id = ?',
          whereArgs: [id],
        );
      }
    });
  }
  const perBatch = 20;
  var nextRecord = 0;
  var doneRecords = 0;
  Future<void> recordWorker() async {
    while (true) {
      if (cancelled || (shouldCancel != null && shouldCancel())) {
        cancelled = true;
        return;
      }
      if (nextRecord >= records.pending.length) return;
      final from = nextRecord;
      final to = from + perBatch > records.pending.length
          ? records.pending.length
          : from + perBatch;
      nextRecord = to;
      final batch = records.pending.sublist(from, to);
      final vectors = await client.embed([for (final c in batch) c.text]);
      await db.transaction((txn) async {
        for (var i = 0; i < batch.length; i++) {
          await txn.insert(
            recordChunkVectorsTable,
            recordVectorRow(batch[i], quantize(vectors[i])),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      });
      doneRecords += batch.length;
      doneChunks += batch.length;
      onRecordProgress?.call(doneRecords, records.pending.length);
    }
  }

  await Future.wait([for (var w = 0; w < concurrency; w++) recordWorker()]);
  if (doneRecords > 0) {
    await db.insert(
      'gamedata_manifest',
      {'key': manifestRecordChunking, 'value': recordChunkingSignature},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  if (doneChunks > 0) {
    await db.transaction((txn) async {
      for (final entry in {
        manifestEmbeddingModel: client.model,
        manifestEmbeddingDims: '${client.dimensions}',
        manifestEmbeddingChunking: chunkingSignature,
      }.entries) {
        await txn.insert(
          'gamedata_manifest',
          {'key': entry.key, 'value': entry.value},
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }
  return VectorUpdateResult(
    stories: doneStories,
    chunks: doneChunks,
    tokensUsed: client.tokensUsed - tokensBefore,
    cancelled: cancelled,
  );
}
