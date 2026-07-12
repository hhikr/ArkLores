import 'dart:math';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' as sqflite;

import '../rag/chunker.dart';

/// The dimension of embedding vectors (text-embedding-3-small).
const int embeddingDim = 1536;

/// Result of a semantic search.
class SearchResult {
  final Chunk chunk;
  final double score;
  final String sourceType; // 'wiki' | 'book'
  final String? sourceUrl;
  final String? wiki;
  final String? bookId;

  SearchResult({
    required this.chunk,
    required this.score,
    required this.sourceType,
    this.sourceUrl,
    this.wiki,
    this.bookId,
  });
}

/// Statistics about the knowledge base.
class VectorStoreStats {
  final int totalChunks;
  final int wikiChunks;
  final int bookChunks;
  final int totalBooks;

  /// Whether sqlite-vec native extension is active.
  /// Always false in the current pure-Dart fallback mode.
  /// Reserved for future FFI re-enablement.
  final bool useVectorExtension;

  const VectorStoreStats({
    this.totalChunks = 0,
    this.wikiChunks = 0,
    this.bookChunks = 0,
    this.totalBooks = 0,
    this.useVectorExtension = false,
  });
}

/// Vector store backed by sqflite with pure-Dart cosine similarity search.
///
/// The sqlite-vec FFI path was deferred (v0.1.7-alpha.3 Android native build
/// is incomplete). When the upstream package stabilises, re-add `sqlite_vec`
/// and `sqlite3` dependencies and restore the FFI branch in each method.
class VectorStore {
  sqflite.Database? _fallbackDb;
  bool _initialized = false;

  /// Whether the sqlite-vec native extension is active (always false in
  /// fallback mode; reserved for future FFI re-enablement).
  bool get useVectorExtension => false;

  /// Initialization error message (always null in fallback-only mode).
  String? get initError => null;

  /// Initializes the vector store with sqflite.
  Future<void> initialize() async {
    if (_initialized) return;

    final dir = await getApplicationDocumentsDirectory();
    final dbPath = p.join(dir.path, 'arklores_knowledge.db');

    _fallbackDb = await sqflite.openDatabase(
      dbPath,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE chunks (
            id          TEXT PRIMARY KEY,
            source_type TEXT NOT NULL,
            source_url  TEXT,
            wiki        TEXT,
            book_id     TEXT,
            page_title  TEXT,
            section     TEXT,
            content     TEXT NOT NULL,
            updated_at  INTEGER
          )
        ''');
        await db.execute('''
          CREATE TABLE chunk_embeddings (
            chunk_id  TEXT PRIMARY KEY,
            embedding BLOB NOT NULL,
            FOREIGN KEY (chunk_id) REFERENCES chunks(id)
          )
        ''');
        await db.execute('''
          CREATE TABLE books (
            id           TEXT PRIMARY KEY,
            file_name    TEXT NOT NULL,
            display_name TEXT,
            chunk_count  INTEGER,
            imported_at  INTEGER
          )
        ''');
      },
    );

    _initialized = true;
  }

  /// Inserts a single chunk with its embedding vector.
  Future<void> insertChunk(Chunk chunk, List<double> embedding,
      {String sourceType = 'wiki',
      String? sourceUrl,
      String? wiki,
      String? bookId}) async {
    await initialize();

    await _fallbackDb!.insert(
      'chunks',
      {
        'id': chunk.id,
        'source_type': sourceType,
        'source_url': sourceUrl,
        'wiki': wiki,
        'book_id': bookId,
        'page_title': chunk.pageTitle,
        'section': chunk.section,
        'content': chunk.content,
        'updated_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      },
      conflictAlgorithm: sqflite.ConflictAlgorithm.replace,
    );
    await _fallbackDb!.insert(
      'chunk_embeddings',
      {
        'chunk_id': chunk.id,
        'embedding': _doubleListToBlob(embedding),
      },
      conflictAlgorithm: sqflite.ConflictAlgorithm.replace,
    );
  }

  /// Inserts multiple chunks with their embeddings in a transaction.
  Future<void> insertChunks(
    List<Chunk> chunks,
    List<List<double>> embeddings, {
    String sourceType = 'wiki',
    String? sourceUrl,
    String? wiki,
    String? bookId,
  }) async {
    if (chunks.isEmpty) return;
    await initialize();

    await _fallbackDb!.transaction((txn) async {
      for (var i = 0; i < chunks.length; i++) {
        await txn.insert(
          'chunks',
          {
            'id': chunks[i].id,
            'source_type': sourceType,
            'source_url': sourceUrl,
            'wiki': wiki,
            'book_id': bookId,
            'page_title': chunks[i].pageTitle,
            'section': chunks[i].section,
            'content': chunks[i].content,
            'updated_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
          },
          conflictAlgorithm: sqflite.ConflictAlgorithm.replace,
        );
        await txn.insert(
          'chunk_embeddings',
          {
            'chunk_id': chunks[i].id,
            'embedding': _doubleListToBlob(embeddings[i]),
          },
          conflictAlgorithm: sqflite.ConflictAlgorithm.replace,
        );
      }
    });
  }

  /// Searches for the top-K chunks most similar to [queryEmbedding].
  ///
  /// Optionally filters by [sourceType] ('wiki' or 'book').
  Future<List<SearchResult>> search(
    List<double> queryEmbedding, {
    int topK = 10,
    String? sourceType,
  }) async {
    await initialize();
    final results = <SearchResult>[];

    final whereClause = sourceType != null
        ? 'WHERE c.source_type = ?'
        : '';
    final whereParams = <String>[];
    if (sourceType != null) whereParams.add(sourceType);

    final dbResults = await _fallbackDb!.rawQuery(
      'SELECT c.id, c.source_type, c.source_url, c.wiki, c.book_id, '
      'c.page_title, c.section, c.content, c.updated_at, '
      'e.embedding '
      'FROM chunk_embeddings e '
      'JOIN chunks c ON c.id = e.chunk_id '
      '$whereClause',
      whereParams,
    );

    final scored = <_ScoredResult>[];
    for (final row in dbResults) {
      final blob = row['embedding'] as Uint8List?;
      if (blob == null) continue;
      final vec = _blobToDoubleList(blob);
      final score = _cosineSimilarity(queryEmbedding, vec);

      scored.add(_ScoredResult(
        score: score,
        chunk: Chunk(
          id: row['id'] as String,
          content: row['content'] as String,
          pageTitle: (row['page_title'] as String?) ?? '',
          section: (row['section'] as String?) ?? '',
          seqIndex: 0,
          tokenCount: 0,
        ),
        sourceType: row['source_type'] as String,
        sourceUrl: row['source_url'] as String?,
        wiki: row['wiki'] as String?,
        bookId: row['book_id'] as String?,
      ));
    }

    // Sort by score descending and take top-K.
    scored.sort((a, b) => b.score.compareTo(a.score));
    for (var i = 0; i < scored.length && i < topK; i++) {
      results.add(SearchResult(
        chunk: scored[i].chunk,
        score: scored[i].score,
        sourceType: scored[i].sourceType,
        sourceUrl: scored[i].sourceUrl,
        wiki: scored[i].wiki,
        bookId: scored[i].bookId,
      ));
    }

    return results;
  }

  /// Deletes chunks and embeddings by source type and optional source ID.
  Future<void> deleteBySource(String sourceType, {String? bookId, String? wiki}) async {
    await initialize();

    String where;
    List<dynamic> params;
    if (bookId != null) {
      where = 'source_type = ? AND book_id = ?';
      params = [sourceType, bookId];
    } else if (wiki != null) {
      where = 'source_type = ? AND wiki = ?';
      params = [sourceType, wiki];
    } else {
      where = 'source_type = ?';
      params = [sourceType];
    }

    await _fallbackDb!.transaction((txn) async {
      final ids = await txn.query(
        'chunks',
        columns: ['id'],
        where: where,
        whereArgs: params,
      );

      for (final row in ids) {
        await txn.delete(
          'chunk_embeddings',
          where: 'chunk_id = ?',
          whereArgs: [row['id']],
        );
      }
      await txn.delete('chunks', where: where, whereArgs: params);
    });
  }

  /// Deletes a book and all its associated chunks/embeddings.
  Future<void> deleteBook(String bookId) async {
    await deleteBySource('book', bookId: bookId);

    await _fallbackDb!.delete('books', where: 'id = ?', whereArgs: [bookId]);
  }

  /// Inserts or updates a book record.
  Future<void> upsertBook({
    required String id,
    required String fileName,
    String? displayName,
    int chunkCount = 0,
  }) async {
    await initialize();

    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    await _fallbackDb!.insert(
      'books',
      {
        'id': id,
        'file_name': fileName,
        'display_name': displayName ?? fileName,
        'chunk_count': chunkCount,
        'imported_at': now,
      },
      conflictAlgorithm: sqflite.ConflictAlgorithm.replace,
    );
  }

  /// Updates a book's display name.
  Future<void> updateBookDisplayName(String bookId, String displayName) async {
    await initialize();

    await _fallbackDb!.update(
      'books',
      {'display_name': displayName},
      where: 'id = ?',
      whereArgs: [bookId],
    );
  }

  /// Returns statistics about the knowledge base.
  Future<VectorStoreStats> getStats() async {
    await initialize();

    final total = sqflite.Sqflite.firstIntValue(
          await _fallbackDb!.rawQuery('SELECT COUNT(*) FROM chunks'),
        ) ??
        0;
    final wikiCount = sqflite.Sqflite.firstIntValue(
          await _fallbackDb!
              .rawQuery("SELECT COUNT(*) FROM chunks WHERE source_type = 'wiki'"),
        ) ??
        0;
    final bookCount = sqflite.Sqflite.firstIntValue(
          await _fallbackDb!
              .rawQuery("SELECT COUNT(*) FROM chunks WHERE source_type = 'book'"),
        ) ??
        0;
    final booksCount = sqflite.Sqflite.firstIntValue(
          await _fallbackDb!.rawQuery('SELECT COUNT(*) FROM books'),
        ) ??
        0;

    return VectorStoreStats(
      totalChunks: total,
      wikiChunks: wikiCount,
      bookChunks: bookCount,
      totalBooks: booksCount,
      useVectorExtension: false,
    );
  }

  /// Returns all books stored in the knowledge base.
  Future<List<Map<String, dynamic>>> getBooks() async {
    await initialize();

    return await _fallbackDb!.query('books', orderBy: 'imported_at DESC');
  }

  // ── Utility methods ──────────────────────────────────────

  /// Converts a list of doubles to a BLOB (byte buffer).
  Uint8List _doubleListToBlob(List<double> values) {
    final buffer = ByteData(values.length * 8);
    for (var i = 0; i < values.length; i++) {
      buffer.setFloat64(i * 8, values[i]);
    }
    return buffer.buffer.asUint8List();
  }

  /// Converts a BLOB back to a list of doubles.
  List<double> _blobToDoubleList(Uint8List blob) {
    final count = blob.length ~/ 8;
    final result = List<double>.filled(count, 0.0);
    final buffer = ByteData.view(blob.buffer, blob.offsetInBytes, blob.length);
    for (var i = 0; i < count; i++) {
      result[i] = buffer.getFloat64(i * 8);
    }
    return result;
  }

  /// Computes cosine similarity between two vectors.
  double _cosineSimilarity(List<double> a, List<double> b) {
    if (a.length != b.length) return 0.0;

    double dotProduct = 0.0;
    double normA = 0.0;
    double normB = 0.0;

    for (var i = 0; i < a.length; i++) {
      dotProduct += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }

    final denominator = sqrt(normA) * sqrt(normB);
    if (denominator == 0) return 0.0;
    return dotProduct / denominator;
  }

  /// Releases database resources.
  void dispose() {
    _fallbackDb?.close();
    _fallbackDb = null;
    _initialized = false;
  }
}

/// Internal helper for scored results during search.
class _ScoredResult {
  final double score;
  final Chunk chunk;
  final String sourceType;
  final String? sourceUrl;
  final String? wiki;
  final String? bookId;

  _ScoredResult({
    required this.score,
    required this.chunk,
    required this.sourceType,
    this.sourceUrl,
    this.wiki,
    this.bookId,
  });
}
