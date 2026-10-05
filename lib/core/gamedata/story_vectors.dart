/// R12 vector recall over raw story lines (the semantic leg of `FIND`).
///
/// Deterministic, source-traceable pipeline (CLAUDE.md principle 4):
/// - chunking: each story's lines in a fixed sliding window ([chunkWindow]
///   lines, step [chunkStride]), text = `speaker：content` per line; a chunk
///   id is `story_id#line_start-line_end`, so a hit maps back to raw lines;
/// - vectors: L2-normalized embeddings quantized to int8 with one scale per
///   vector, stored in the optional `story_chunk_vectors` table; the
///   manifest records the embedding model, dims and chunking so a query is
///   only scored against vectors from the same model.
///
/// Hits are LOCATING HINTS (principle 5): they point at line ranges the
/// agent must READ; they never enter the evidence notebook themselves.
/// Pure Dart (sqflite_common) so the app and desktop tools share it.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:sqflite_common/sqlite_api.dart';

const int chunkWindow = 12;
const int chunkStride = 8;
const String storyChunkVectorsTable = 'story_chunk_vectors';
const String manifestEmbeddingModel = 'embedding_model';
const String manifestEmbeddingDims = 'embedding_dims';
const String manifestEmbeddingChunking = 'embedding_chunking';
const String chunkingSignature = 'window=$chunkWindow,stride=$chunkStride';

/// DDL of the optional vector table (absent on DBs built without a key).
const String storyChunkVectorsDdl = '''
  CREATE TABLE IF NOT EXISTS $storyChunkVectorsTable (
    chunk_id   TEXT PRIMARY KEY,
    story_id   TEXT NOT NULL,
    scope_id   TEXT,
    line_start INTEGER NOT NULL,
    line_end   INTEGER NOT NULL,
    scale      REAL NOT NULL,
    vec        BLOB NOT NULL
  )
''';

/// Index that makes "which stories have vectors" and "drop a story's
/// vectors" cheap (an update touches a handful of stories out of 3,600).
const String storyChunkVectorsIndexDdl =
    'CREATE INDEX IF NOT EXISTS idx_story_chunk_vectors_story '
    'ON $storyChunkVectorsTable(story_id)';

/// One story line as input to chunking.
class ChunkLine {
  const ChunkLine(this.index, this.speaker, this.content);
  final int index;
  final String? speaker;
  final String content;
}

/// One embedding unit: a window of consecutive story lines.
class StoryChunk {
  const StoryChunk({
    required this.storyId,
    required this.scopeId,
    required this.lineStart,
    required this.lineEnd,
    required this.text,
  });
  final String storyId;
  final String? scopeId;
  final int lineStart;
  final int lineEnd;
  final String text;

  String get chunkId => '$storyId#$lineStart-$lineEnd';
}

/// Splits one story's [lines] (ordered by index) into fixed windows.
/// Blank lines are skipped in the text but windows stay index-anchored.
List<StoryChunk> chunkStory(
  String storyId,
  String? scopeId,
  List<ChunkLine> lines,
) {
  if (lines.isEmpty) return const [];
  final chunks = <StoryChunk>[];
  for (var start = 0; start < lines.length; start += chunkStride) {
    final end = math.min(start + chunkWindow, lines.length);
    final window = lines.sublist(start, end);
    final text = window
        .where((l) => l.content.trim().isNotEmpty)
        .map((l) => l.speaker == null || l.speaker!.trim().isEmpty
            ? l.content.trim()
            : '${l.speaker!.trim()}：${l.content.trim()}',)
        .join('\n');
    if (text.isNotEmpty) {
      chunks.add(StoryChunk(
        storyId: storyId,
        scopeId: scopeId,
        lineStart: window.first.index,
        lineEnd: window.last.index,
        text: text,
      ),);
    }
    if (end == lines.length) break;
  }
  return chunks;
}

/// An L2-normalized vector quantized to int8 (`value ≈ q * scale`).
class QuantizedVector {
  const QuantizedVector(this.scale, this.values);
  final double scale;
  final Int8List values;
}

/// Normalizes [vector] to unit length and quantizes it to int8.
QuantizedVector quantize(List<double> vector) {
  var norm = 0.0;
  for (final v in vector) {
    norm += v * v;
  }
  norm = math.sqrt(norm);
  if (norm == 0) return QuantizedVector(0, Int8List(vector.length));
  var maxAbs = 0.0;
  for (final v in vector) {
    final a = (v / norm).abs();
    if (a > maxAbs) maxAbs = a;
  }
  final scale = maxAbs == 0 ? 0.0 : maxAbs / 127.0;
  final values = Int8List(vector.length);
  for (var i = 0; i < vector.length; i++) {
    values[i] = scale == 0 ? 0 : ((vector[i] / norm) / scale).round().clamp(-127, 127);
  }
  return QuantizedVector(scale, values);
}

/// One vector hit: a story line range and its cosine similarity.
class StoryChunkHit {
  const StoryChunkHit({
    required this.storyId,
    required this.scopeId,
    required this.lineStart,
    required this.lineEnd,
    required this.score,
  });
  final String storyId;
  final String? scopeId;
  final int lineStart;
  final int lineEnd;
  final double score;
}

/// In-memory brute-force cosine index over `story_chunk_vectors`. About 51k
/// chunks x 512 dims = 26MB of int8; one query is ~26M multiply-adds.
class StoryVectorIndex {
  StoryVectorIndex._({
    required this.model,
    required this.dims,
    required List<String> storyIds,
    required List<String?> scopeIds,
    required Int32List lineStarts,
    required Int32List lineEnds,
    required Float32List scales,
    required Int8List vectors,
  })  : _storyIds = storyIds,
        _scopeIds = scopeIds,
        _lineStarts = lineStarts,
        _lineEnds = lineEnds,
        _scales = scales,
        _vectors = vectors;

  final String model;
  final int dims;
  final List<String> _storyIds;
  final List<String?> _scopeIds;
  final Int32List _lineStarts;
  final Int32List _lineEnds;
  final Float32List _scales;
  final Int8List _vectors;

  int get length => _scales.length;

  /// Loads the index, or null when the DB has no (compatible) vector table.
  static Future<StoryVectorIndex?> load(DatabaseExecutor db) async {
    final table = await db.rawQuery(
      "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?",
      [storyChunkVectorsTable],
    );
    if (table.isEmpty) return null;
    final manifest = {
      for (final row in await db.rawQuery(
        'SELECT key, value FROM gamedata_manifest WHERE key IN (?, ?, ?)',
        [manifestEmbeddingModel, manifestEmbeddingDims, manifestEmbeddingChunking],
      ))
        '${row['key']}': '${row['value']}',
    };
    final model = manifest[manifestEmbeddingModel];
    final dims = int.tryParse(manifest[manifestEmbeddingDims] ?? '');
    if (model == null || dims == null || dims <= 0) return null;

    final rows = await db.rawQuery(
      'SELECT story_id, scope_id, line_start, line_end, scale, vec '
      'FROM $storyChunkVectorsTable ORDER BY chunk_id',
    );
    final n = rows.length;
    final storyIds = List<String>.filled(n, '');
    final scopeIds = List<String?>.filled(n, null);
    final starts = Int32List(n);
    final ends = Int32List(n);
    final scales = Float32List(n);
    final vectors = Int8List(n * dims);
    var kept = 0;
    for (final row in rows) {
      final blob = row['vec'];
      if (blob is! Uint8List || blob.length != dims) continue; // corrupt row
      storyIds[kept] = '${row['story_id']}';
      scopeIds[kept] = row['scope_id'] as String?;
      starts[kept] = (row['line_start'] as num).toInt();
      ends[kept] = (row['line_end'] as num).toInt();
      scales[kept] = (row['scale'] as num).toDouble();
      vectors.setRange(
        kept * dims,
        kept * dims + dims,
        Int8List.view(blob.buffer, blob.offsetInBytes, dims),
      );
      kept++;
    }
    return StoryVectorIndex._(
      model: model,
      dims: dims,
      storyIds: storyIds.sublist(0, kept),
      scopeIds: scopeIds.sublist(0, kept),
      lineStarts: Int32List.sublistView(starts, 0, kept),
      lineEnds: Int32List.sublistView(ends, 0, kept),
      scales: Float32List.sublistView(scales, 0, kept),
      vectors: Int8List.sublistView(vectors, 0, kept * dims),
    );
  }

  /// Top [topK] chunks by cosine similarity to [query] (any length-[dims]
  /// vector; normalized here), optionally restricted to [scopeId].
  List<StoryChunkHit> search(
    List<double> query, {
    int topK = 20,
    String? scopeId,
  }) {
    if (query.length != dims || length == 0) return const [];
    var norm = 0.0;
    for (final v in query) {
      norm += v * v;
    }
    norm = math.sqrt(norm);
    if (norm == 0) return const [];
    final q = Float32List(dims);
    for (var i = 0; i < dims; i++) {
      q[i] = query[i] / norm;
    }

    final scores = <(int, double)>[];
    var floor = double.negativeInfinity;
    for (var c = 0; c < length; c++) {
      if (scopeId != null && _scopeIds[c] != scopeId) continue;
      final base = c * dims;
      var dot = 0.0;
      for (var i = 0; i < dims; i++) {
        dot += q[i] * _vectors[base + i];
      }
      final score = dot * _scales[c];
      if (scores.length < topK) {
        scores.add((c, score));
        if (scores.length == topK) {
          scores.sort((a, b) => b.$2.compareTo(a.$2));
          floor = scores.last.$2;
        }
      } else if (score > floor) {
        scores[topK - 1] = (c, score);
        scores.sort((a, b) => b.$2.compareTo(a.$2));
        floor = scores.last.$2;
      }
    }
    scores.sort((a, b) => b.$2.compareTo(a.$2));
    return [
      for (final (c, score) in scores)
        StoryChunkHit(
          storyId: _storyIds[c],
          scopeId: _scopeIds[c],
          lineStart: _lineStarts[c],
          lineEnd: _lineEnds[c],
          score: score,
        ),
    ];
  }
}
