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
import 'package:sqflite_common_ffi/sqflite_ffi.dart' show sqfliteFfiInit;
import 'package:sqlite3/sqlite3.dart' as sqlite;

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
  const ChunkLine(this.index, this.speaker, this.content,
      {this.isBreak = false,});
  final int index;
  final String? speaker;
  final String content;

  /// A `section` line (where one conversation of a merged story ends and the
  /// next begins): not embedded, and no window spans it.
  final bool isBreak;
}

/// `story_lines.kind` of the line that separates two parts of one story.
const String sectionLineKind = 'section';

/// `story_lines.kind` of the game's own summary of the part it opens (an
/// Endfield conversation's, right after its section line): a locating hint
/// shown to the reader, not story text.
const String summaryLineKind = 'summary';

/// `story_lines.kind` of a step's goal in a story laid out along its
/// mission's steps (an Endfield mission), or of a heading of the groups
/// after them: a heading, not story text.
const String stepLineKind = 'step';

/// `story_lines.kind` of the name of a mission played inside a step of the
/// story's mission (its conversations follow, under its own steps).
const String stageLineKind = 'stage';

/// `story_lines.kind` of the heading of the conversations no data places
/// (after the steps): the reader folds what follows it.
const String unplacedLineKind = 'unplaced';

/// Headings of a story laid out along its mission's steps.
const Set<String> headingLineKinds = {
  stepLineKind,
  stageLineKind,
  unplacedLineKind,
};

/// Line kinds that end one part of a story and start the next: no window
/// spans them.
const Set<String> breakLineKinds = {sectionLineKind, ...headingLineKinds};

/// Line kinds never embedded: tutorial and guide text (not part of any
/// story), the summaries (the catalog synopsis has them already) and the
/// step headings.
const Set<String> unembeddedLineKinds = {
  'system',
  summaryLineKind,
  ...headingLineKinds,
};

/// [unembeddedLineKinds] as an SQL list: `kind NOT IN $unembeddedKindsSql`.
final String unembeddedKindsSql =
    "(${unembeddedLineKinds.map((k) => "'$k'").join(', ')})";

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
/// A break line ([ChunkLine.isBreak]) ends the windows of the part before it;
/// each part is windowed on its own.
List<StoryChunk> chunkStory(
  String storyId,
  String? scopeId,
  List<ChunkLine> lines,
) {
  if (lines.any((l) => l.isBreak)) {
    final chunks = <StoryChunk>[];
    var part = <ChunkLine>[];
    for (final l in [...lines, const ChunkLine(-1, null, '', isBreak: true)]) {
      if (!l.isBreak) {
        part.add(l);
        continue;
      }
      chunks.addAll(chunkStory(storyId, scopeId, part));
      part = <ChunkLine>[];
    }
    return chunks;
  }
  if (lines.isEmpty) return const [];
  final chunks = <StoryChunk>[];
  for (var start = 0; start < lines.length; start += chunkStride) {
    final end = math.min(start + chunkWindow, lines.length);
    final window = lines.sublist(start, end);
    final text = window
        .where((l) => l.content.trim().isNotEmpty)
        .map(
          (l) => l.speaker == null || l.speaker!.trim().isEmpty
              ? l.content.trim()
              : '${l.speaker!.trim()}：${l.content.trim()}',
        )
        .join('\n');
    if (text.isNotEmpty) {
      chunks.add(
        StoryChunk(
          storyId: storyId,
          scopeId: scopeId,
          lineStart: window.first.index,
          lineEnd: window.last.index,
          text: text,
        ),
      );
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
    values[i] =
        scale == 0 ? 0 : ((vector[i] / norm) / scale).round().clamp(-127, 127);
  }
  return QuantizedVector(scale, values);
}

/// The [topK] rows of [vectors] (int8, [dims] each, one [scales] entry per
/// row) closest to [query] by cosine similarity, best first, as (row,
/// score); [keep] leaves rows out. Shared by the story and the record
/// index.
List<(int, double)> topByCosine(
  Int8List vectors,
  Float32List scales,
  int dims,
  List<double> query, {
  int topK = 20,
  bool Function(int row)? keep,
}) {
  final length = scales.length;
  if (query.length != dims || length == 0 || topK <= 0) return const [];
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
    if (keep != null && !keep(c)) continue;
    final base = c * dims;
    var dot = 0.0;
    for (var i = 0; i < dims; i++) {
      dot += q[i] * vectors[base + i];
    }
    final score = dot * scales[c];
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
  return scores;
}

/// 0.14: how close a passage of another collection must be to one read
/// before it is listed as alike. Measured on the real database (2026-10-11:
/// 500 random passages, each with the 5 closest of other collections;
/// "related" taken as the two collections sharing a speaker who is not
/// everywhere): about nine in ten are related from 0.70 up, six in ten
/// between 0.65 and 0.70, a third below. Look at the real database again
/// before changing it.
const double nearMinSimilarity = 0.70;

/// Passages listed as alike, one per collection.
const int nearMaxPassages = 5;

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
        [
          manifestEmbeddingModel,
          manifestEmbeddingDims,
          manifestEmbeddingChunking,
        ],
      ))
        '${row['key']}': '${row['value']}',
    };
    final model = manifest[manifestEmbeddingModel];
    final dims = int.tryParse(manifest[manifestEmbeddingDims] ?? '');
    if (model == null || dims == null || dims <= 0) return null;
    return _fromRows(model, dims, await db.rawQuery(_rowsSql));
  }

  /// [load] from the DB file at [path] through its own read-only FFI
  /// connection, for a background isolate: the app's sqflite connection
  /// would bring the ~28 MB of vectors over the platform channel and decode
  /// them on the UI isolate in one piece, which freezes the interface.
  /// The result moves to the calling isolate without a copy
  /// (`Isolate.run`).
  static StoryVectorIndex? loadFile(String path) {
    sqfliteFfiInit(); // the bundled SQLite on desktop; a no-op elsewhere
    final db = sqlite.sqlite3.open(path, mode: sqlite.OpenMode.readOnly);
    try {
      if (db.select(
        "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?",
        [storyChunkVectorsTable],
      ).isEmpty) {
        return null;
      }
      final manifest = {
        for (final row in db.select(
          'SELECT key, value FROM gamedata_manifest WHERE key IN (?, ?, ?)',
          [
            manifestEmbeddingModel,
            manifestEmbeddingDims,
            manifestEmbeddingChunking,
          ],
        ))
          '${row['key']}': '${row['value']}',
      };
      final model = manifest[manifestEmbeddingModel];
      final dims = int.tryParse(manifest[manifestEmbeddingDims] ?? '');
      if (model == null || dims == null || dims <= 0) return null;
      return _fromRows(model, dims, db.select(_rowsSql));
    } finally {
      db.dispose();
    }
  }

  static const String _rowsSql =
      'SELECT story_id, scope_id, line_start, line_end, scale, vec '
      'FROM $storyChunkVectorsTable ORDER BY chunk_id';

  static StoryVectorIndex _fromRows(
    String model,
    int dims,
    List<Map<String, Object?>> rows,
  ) {
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

  /// 0.14: the mean direction of each collection's chunks (unit length), by
  /// [collectionOf] (story id → collection id). A collection with fewer
  /// than [minChunks] chunks has none: a few passages are not what a
  /// collection is about.
  Map<String, Float32List> collectionCentroids(
    Map<String, String> collectionOf, {
    int minChunks = 8,
  }) {
    final sums = <String, Float64List>{};
    final counts = <String, int>{};
    for (var c = 0; c < length; c++) {
      final collection = collectionOf[_storyIds[c]];
      if (collection == null) continue;
      final base = c * dims;
      var squares = 0.0;
      for (var i = 0; i < dims; i++) {
        final x = _vectors[base + i];
        squares += x * x;
      }
      if (squares == 0) continue;
      final norm = math.sqrt(squares);
      final sum = sums.putIfAbsent(collection, () => Float64List(dims));
      for (var i = 0; i < dims; i++) {
        sum[i] += _vectors[base + i] / norm;
      }
      counts[collection] = (counts[collection] ?? 0) + 1;
    }
    final centroids = <String, Float32List>{};
    for (final MapEntry(key: collection, value: sum) in sums.entries) {
      if (counts[collection]! < minChunks) continue;
      var squares = 0.0;
      for (final x in sum) {
        squares += x * x;
      }
      if (squares == 0) continue;
      final norm = math.sqrt(squares);
      final unit = Float32List(dims);
      for (var i = 0; i < dims; i++) {
        unit[i] = sum[i] / norm;
      }
      centroids[collection] = unit;
    }
    return centroids;
  }

  /// 0.14: the line range of the chunk of [storyId] that holds [line] — the
  /// first one (chunks overlap) — or null when no chunk does.
  ({int lineStart, int lineEnd})? chunkAt(String storyId, int line) {
    final at = _chunkAt(storyId, line);
    return at < 0 ? null : (lineStart: _lineStarts[at], lineEnd: _lineEnds[at]);
  }

  int _chunkAt(String storyId, int line) {
    var found = -1;
    for (var c = 0; c < length; c++) {
      if (_storyIds[c] != storyId) continue;
      if (_lineStarts[c] > line || _lineEnds[c] < line) continue;
      if (found < 0 || _lineStarts[c] < _lineStarts[found]) found = c;
    }
    return found;
  }

  List<double>? passageVector(String storyId, int line) {
    final at = _chunkAt(storyId, line);
    return at < 0
        ? null
        : [
            for (var i = 0; i < dims; i++) _vectors[at * dims + i] * _scales[at],
          ];
  }

  /// 0.14: the chunks closest to the one of [storyId] that holds [line],
  /// among the stories [keep] lets through; the stored vector is the query,
  /// so nothing is embedded. Empty when no chunk holds the line.
  List<StoryChunkHit> nearChunk(
    String storyId,
    int line, {
    int topK = 20,
    bool Function(String storyId)? keep,
  }) {
    final at = _chunkAt(storyId, line);
    if (at < 0) return const [];
    final scores = topByCosine(
      _vectors,
      _scales,
      dims,
      // Cosine: the chunk's scale does not matter.
      [for (var i = 0; i < dims; i++) _vectors[at * dims + i].toDouble()],
      topK: topK,
      keep: (c) => c != at && (keep == null || keep(_storyIds[c])),
    );
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

  /// Top [topK] chunks by cosine similarity to [query] (any length-[dims]
  /// vector; normalized here), optionally restricted to [scopeId] and to the
  /// story files [storyIds].
  List<StoryChunkHit> search(
    List<double> query, {
    int topK = 20,
    String? scopeId,
    Set<String>? storyIds,
  }) {
    final scores = topByCosine(
      _vectors,
      _scales,
      dims,
      query,
      topK: topK,
      keep: scopeId == null && storyIds == null
          ? null
          : (c) =>
              (scopeId == null || _scopeIds[c] == scopeId) &&
              (storyIds == null || storyIds.contains(_storyIds[c])),
    );
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
