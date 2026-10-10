/// 0.14: vectors for the records outside the story text (archives, voice
/// lines, modules, item and enemy texts, an operator's whole file), so a
/// search by meaning finds them too. Until now only story lines had vectors
/// and a record was found by a literal word of the query.
///
/// Deterministic and source-traceable like the story vectors
/// (`story_vectors.dart`):
/// - one chunk per record; a long one is cut where a `## ` section starts,
///   then between lines, never above [recordChunkChars]. The embedded text
///   starts with whose record it is and its title, the way a reader meets
///   it; a chunk id is `<record id>#<part>` and carries the character range
///   it covers, so a hit maps back to the text;
/// - a chunk's vector is kept with a hash of its text: after an update the
///   chunks whose text changed (or whose record is gone) are found by
///   comparing hashes, and only those are embedded again;
/// - same model and dimensions as the story vectors of the same database
///   (one embedding of the query serves both).
///
/// Hits are LOCATING HINTS: they point at a record the agent must read.
/// Pure Dart (sqflite_common), shared by the app and the desktop tools.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:sqflite_common/sqlite_api.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' show sqfliteFfiInit;
import 'package:sqlite3/sqlite3.dart' as sqlite;

import 'story_vectors.dart';

const String recordChunkVectorsTable = 'record_chunk_vectors';
const String manifestRecordChunking = 'record_embedding_chunking';

/// Most characters of a record's text in one chunk.
const int recordChunkChars = 800;
const String recordChunkingSignature = 'record,max=$recordChunkChars';

/// The two tables a record lives in.
const String recordSourceRecord = 'record';
const String recordSourceDocument = 'document';

const String recordChunkVectorsDdl = '''
  CREATE TABLE IF NOT EXISTS $recordChunkVectorsTable (
    chunk_id   TEXT PRIMARY KEY,
    record_id  TEXT NOT NULL,
    source     TEXT NOT NULL,
    part       INTEGER NOT NULL,
    char_start INTEGER NOT NULL,
    char_end   INTEGER NOT NULL,
    text_hash  TEXT NOT NULL,
    scale      REAL NOT NULL,
    vec        BLOB NOT NULL
  )
''';

const String recordChunkVectorsIndexDdl =
    'CREATE INDEX IF NOT EXISTS idx_record_chunk_vectors_record '
    'ON $recordChunkVectorsTable(record_id)';

/// One embedding unit: a record, or a part of a long one.
class RecordChunk {
  const RecordChunk({
    required this.recordId,
    required this.source,
    required this.part,
    required this.charStart,
    required this.charEnd,
    required this.text,
  });
  final String recordId;

  /// [recordSourceRecord] or [recordSourceDocument].
  final String source;
  final int part;

  /// The range of the record's `content` this chunk covers.
  final int charStart;
  final int charEnd;

  /// What is embedded: the heading (owner, title) and that range.
  final String text;

  String get chunkId => '$recordId#$part';
  String get textHash => fnv1a64(text);
}

/// FNV-1a 64-bit over UTF-8, 16 hex digits (stable across runs and
/// platforms; VM ints wrap mod 2^64).
String fnv1a64(String text) {
  var h = 0xcbf29ce484222325;
  for (final b in utf8.encode(text)) {
    h = (h ^ b) * 0x100000001b3;
  }
  return h.toUnsigned(64).toRadixString(16).padLeft(16, '0');
}

/// `owner · title：` as far as the two are there and differ.
String recordHeading(String owner, String title) {
  final o = owner.trim();
  final t = title.trim();
  final head = o.isEmpty || o == t ? t : (t.isEmpty ? o : '$o · $t');
  return head.isEmpty ? '' : '$head：';
}

/// The chunks of one record. [content] as stored (ranges index into it).
List<RecordChunk> chunkRecord({
  required String id,
  required String content,
  String source = recordSourceRecord,
  String owner = '',
  String title = '',
}) {
  if (content.trim().isEmpty) return const [];
  final heading = recordHeading(owner, title);
  final ranges = <(int, int)>[];
  if (content.length <= recordChunkChars) {
    ranges.add((0, content.length));
  } else {
    // Sections first, then lines packed up to the limit, then a hard cut.
    final sections = <(int, int)>[];
    var from = 0;
    for (final m in RegExp(r'^## ', multiLine: true).allMatches(content)) {
      if (m.start > from) sections.add((from, m.start));
      from = m.start;
    }
    sections.add((from, content.length));
    for (final (a, b) in sections) {
      var start = a;
      var end = a;
      while (end < b) {
        final nl = content.indexOf('\n', end);
        var lineEnd = nl < 0 || nl >= b ? b : nl + 1;
        if (lineEnd - start > recordChunkChars) {
          if (end > start) {
            ranges.add((start, end));
            start = end;
            continue;
          }
          lineEnd = start + recordChunkChars;
        }
        end = lineEnd;
      }
      if (end > start) ranges.add((start, end));
    }
  }
  final chunks = <RecordChunk>[];
  for (final (a, b) in ranges) {
    final body = content.substring(a, b).trim();
    if (body.isEmpty) continue;
    chunks.add(
      RecordChunk(
        recordId: id,
        source: source,
        part: chunks.length,
        charStart: a,
        charEnd: b,
        text: '$heading$body',
      ),
    );
  }
  return chunks;
}

/// Whose record it is: its `entity_name`, else the name of its `entity_id`
/// (the same rule the build's derived step writes into the table).
const String recordOwnerSql =
    "COALESCE(NULLIF(entity_name, ''), "
    '(SELECT e.name FROM entities e WHERE e.id = entity_id), '
    "'')";

Future<bool> _hasTable(DatabaseExecutor db, String name) async =>
    (await db.rawQuery(
      "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?",
      [name],
    ))
        .isNotEmpty;

/// Every chunk of every record of [db], in a fixed order: the records of
/// `normalized_records` that are not copies of story text, then the
/// documents of `entity_documents`.
Future<List<RecordChunk>> recordChunksOf(DatabaseExecutor db) async {
  final chunks = <RecordChunk>[];
  if (await _hasTable(db, 'normalized_records')) {
    final owner = await _hasTable(db, 'entities') ? recordOwnerSql : "''";
    for (final r in await db.rawQuery(
      'SELECT id, title, content, $owner AS owner FROM normalized_records '
      "WHERE category != 'story' AND COALESCE(subtype, '') != 'story' "
      'ORDER BY id',
    )) {
      chunks.addAll(
        chunkRecord(
          id: '${r['id']}',
          content: '${r['content'] ?? ''}',
          owner: '${r['owner'] ?? ''}',
          title: '${r['title'] ?? ''}',
        ),
      );
    }
  }
  if (await _hasTable(db, 'entity_documents')) {
    for (final r in await db.rawQuery(
      'SELECT id, title, content, entity_name FROM entity_documents '
      'ORDER BY id',
    )) {
      chunks.addAll(
        chunkRecord(
          id: '${r['id']}',
          source: recordSourceDocument,
          content: '${r['content'] ?? ''}',
          owner: '${r['entity_name'] ?? ''}',
          title: '${r['title'] ?? ''}',
        ),
      );
    }
  }
  return chunks;
}

/// One row of [recordChunkVectorsTable] for [chunk] and its vector.
Map<String, Object?> recordVectorRow(RecordChunk chunk, QuantizedVector q) => {
      'chunk_id': chunk.chunkId,
      'record_id': chunk.recordId,
      'source': chunk.source,
      'part': chunk.part,
      'char_start': chunk.charStart,
      'char_end': chunk.charEnd,
      'text_hash': chunk.textHash,
      'scale': q.scale,
      'vec': q.values.buffer
          .asUint8List(q.values.offsetInBytes, q.values.lengthInBytes),
    };

/// One vector hit: a range of a record's text and its cosine similarity.
class RecordChunkHit {
  const RecordChunkHit({
    required this.recordId,
    required this.source,
    required this.charStart,
    required this.charEnd,
    required this.score,
  });
  final String recordId;
  final String source;
  final int charStart;
  final int charEnd;
  final double score;
}

/// In-memory brute-force cosine index over [recordChunkVectorsTable].
class RecordVectorIndex {
  RecordVectorIndex._(
    this.dims,
    this._ids,
    this._sources,
    this._starts,
    this._ends,
    this._scales,
    this._vectors,
  );

  final int dims;
  final List<String> _ids;
  final List<String> _sources;
  final Int32List _starts;
  final Int32List _ends;
  final Float32List _scales;
  final Int8List _vectors;

  int get length => _scales.length;

  static const String _rowsSql =
      'SELECT record_id, source, char_start, char_end, scale, vec '
      'FROM $recordChunkVectorsTable ORDER BY chunk_id';

  /// Loads the index, or null when the DB has no record vectors.
  static Future<RecordVectorIndex?> load(DatabaseExecutor db) async {
    if (!await _hasTable(db, recordChunkVectorsTable)) return null;
    final dims = int.tryParse(
      '${(await db.rawQuery(
        'SELECT value FROM gamedata_manifest WHERE key = ?',
        [manifestEmbeddingDims],
      )).firstOrNull?['value'] ?? ''}',
    );
    if (dims == null || dims <= 0) return null;
    return _fromRows(dims, await db.rawQuery(_rowsSql));
  }

  /// [load] from the file at [path] through its own read-only FFI
  /// connection, for a background isolate (see
  /// [StoryVectorIndex.loadFile]).
  static RecordVectorIndex? loadFile(String path) {
    sqfliteFfiInit();
    final db = sqlite.sqlite3.open(path, mode: sqlite.OpenMode.readOnly);
    try {
      if (db.select(
        "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?",
        [recordChunkVectorsTable],
      ).isEmpty) {
        return null;
      }
      final row = db.select(
        'SELECT value FROM gamedata_manifest WHERE key = ?',
        [manifestEmbeddingDims],
      );
      final dims = row.isEmpty ? null : int.tryParse('${row.first['value']}');
      if (dims == null || dims <= 0) return null;
      return _fromRows(dims, db.select(_rowsSql));
    } finally {
      db.dispose();
    }
  }

  static RecordVectorIndex _fromRows(
    int dims,
    List<Map<String, Object?>> rows,
  ) {
    final n = rows.length;
    final ids = List<String>.filled(n, '');
    final sources = List<String>.filled(n, '');
    final starts = Int32List(n);
    final ends = Int32List(n);
    final scales = Float32List(n);
    final vectors = Int8List(n * dims);
    var kept = 0;
    for (final row in rows) {
      final blob = row['vec'];
      if (blob is! Uint8List || blob.length != dims) continue; // corrupt row
      ids[kept] = '${row['record_id']}';
      sources[kept] = '${row['source']}';
      starts[kept] = (row['char_start'] as num).toInt();
      ends[kept] = (row['char_end'] as num).toInt();
      scales[kept] = (row['scale'] as num).toDouble();
      vectors.setRange(
        kept * dims,
        kept * dims + dims,
        Int8List.view(blob.buffer, blob.offsetInBytes, dims),
      );
      kept++;
    }
    return RecordVectorIndex._(
      dims,
      ids.sublist(0, kept),
      sources.sublist(0, kept),
      Int32List.sublistView(starts, 0, kept),
      Int32List.sublistView(ends, 0, kept),
      Float32List.sublistView(scales, 0, kept),
      Int8List.sublistView(vectors, 0, kept * dims),
    );
  }

  /// Top [topK] chunks by cosine similarity to [query].
  List<RecordChunkHit> search(List<double> query, {int topK = 10}) => [
        for (final (c, score)
            in topByCosine(_vectors, _scales, dims, query, topK: topK))
          RecordChunkHit(
            recordId: _ids[c],
            source: _sources[c],
            charStart: _starts[c],
            charEnd: _ends[c],
            score: score,
          ),
      ];
}
