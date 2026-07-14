import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute, debugPrint;
import 'package:flutter/services.dart' show rootBundle;

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' as sqflite;

import '../rag/chunker.dart';
import 'local_embedding/builtin_embedding_client.dart';

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
  final int failedChunks;

  /// Whether sqlite-vec native extension is active.
  /// Always false in the current pure-Dart fallback mode.
  /// Reserved for future FFI re-enablement.
  final bool useVectorExtension;

  const VectorStoreStats({
    this.totalChunks = 0,
    this.wikiChunks = 0,
    this.bookChunks = 0,
    this.totalBooks = 0,
    this.failedChunks = 0,
    this.useVectorExtension = false,
  });
}

const String _legacyProfileId = 'legacy';

// ── Top-level helper for compute() isolate ─────────────────────────────────
// Must be top-level (not a class member) so Flutter's isolate spawner can
// locate it without capturing any class state.

/// Converts a batch of embedding vectors to SQLite BLOB byte arrays.
///
/// Each double is stored as 8 bytes (Float64, big-endian). Running this in
/// a background isolate via [compute] keeps the main/UI thread free during
/// large indexing operations.
List<Uint8List> _blobifyEmbeddings(List<List<double>> embeddings) {
  return embeddings.map((vec) {
    final buffer = ByteData(vec.length * 8);
    for (var i = 0; i < vec.length; i++) {
      buffer.setFloat64(i * 8, vec[i]);
    }
    return buffer.buffer.asUint8List();
  }).toList();
}

// ─────────────────────────────────────────────────────────────────────────────

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

    // Use external storage on Android so it is visible to users (similar to markdown cache)
    Directory dir = await getApplicationDocumentsDirectory();
    if (Platform.isAndroid) {
      final extDir = await getExternalStorageDirectory();
      if (extDir != null) dir = extDir;
    }
    final dbPath = p.join(dir.path, 'arklores_knowledge.db');

    // Legacy sandbox database path migration
    final legacyDir = await getApplicationDocumentsDirectory();
    final legacyPath = p.join(legacyDir.path, 'arklores_knowledge.db');
    final legacyFile = File(legacyPath);
    final file = File(dbPath);

    if (dbPath != legacyPath &&
        await legacyFile.exists() &&
        !await file.exists()) {
      try {
        await file.parent.create(recursive: true);
        await legacyFile.copy(dbPath);
        await legacyFile.delete();
        print(
            '[VectorStore] Successfully migrated legacy sandbox database to: $dbPath');
      } catch (e) {
        print('[VectorStore] Failed to migrate legacy sandbox database: $e');
      }
    }

    if (!await file.exists()) {
      try {
        await file.parent.create(recursive: true);
        final data =
            await rootBundle.load('assets/seeds/arklores_knowledge.db');
        final bytes =
            data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
        await file.writeAsBytes(bytes, flush: true);
        print('[VectorStore] Successfully seeded database from assets.');
      } catch (e) {
        print(
            '[VectorStore] Database seed asset not found or failed to load. Creating fresh database.');
      }
    }

    _fallbackDb = await sqflite.openDatabase(
      dbPath,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS chunks (
            id          TEXT PRIMARY KEY,
            source_type TEXT NOT NULL,
            source_url  TEXT,
            wiki        TEXT,
            book_id     TEXT,
            page_title  TEXT,
            section     TEXT,
            content     TEXT NOT NULL,
            updated_at  INTEGER,
            embedding_status TEXT DEFAULT 'ok',
            profile_id TEXT DEFAULT 'legacy'
          )
        ''');
        await db.execute('''
          CREATE TABLE IF NOT EXISTS chunk_embeddings (
            chunk_id  TEXT PRIMARY KEY,
            embedding BLOB NOT NULL,
            FOREIGN KEY (chunk_id) REFERENCES chunks(id)
          )
        ''');
        await db.execute('''
          CREATE TABLE IF NOT EXISTS books (
            id           TEXT PRIMARY KEY,
            file_name    TEXT NOT NULL,
            display_name TEXT,
            chunk_count  INTEGER,
            imported_at  INTEGER,
            profile_id TEXT DEFAULT 'legacy'
          )
        ''');
        await db.execute('''
          CREATE TABLE IF NOT EXISTS seed_metadata (
            key   TEXT PRIMARY KEY,
            value TEXT NOT NULL
          )
        ''');
      },
    );

    // Run schema migration if upgrading from previous version.
    try {
      await _fallbackDb!.execute(
        "ALTER TABLE chunks ADD COLUMN embedding_status TEXT DEFAULT 'ok'",
      );
    } catch (_) {
      // Ignored if column already exists.
    }
    try {
      await _fallbackDb!.execute(
        "ALTER TABLE chunks ADD COLUMN profile_id TEXT DEFAULT 'legacy'",
      );
    } catch (_) {
      // Ignored if column already exists.
    }
    try {
      await _fallbackDb!.execute(
        "ALTER TABLE books ADD COLUMN profile_id TEXT DEFAULT 'legacy'",
      );
    } catch (_) {
      // Ignored if column already exists.
    }
    try {
      await _fallbackDb!.execute('''
        CREATE TABLE IF NOT EXISTS seed_metadata (
          key   TEXT PRIMARY KEY,
          value TEXT NOT NULL
        )
      ''');
    } catch (_) {
      // Ignored if table already exists.
    }

    await _normalizeSeedWikiTimestamps();

    // Self-healing check: check if the first few embeddings are corrupt (identical vectors due to past tflite_flutter gotcha)
    try {
      final sampleEmbeddings = await _fallbackDb!.rawQuery('''
        SELECT ce.embedding FROM chunk_embeddings ce
        INNER JOIN chunks c ON ce.chunk_id = c.id
        WHERE c.profile_id = 'builtin:builtin-embedding'
        LIMIT 5
      ''');
      if (sampleEmbeddings.length >= 2) {
        final blobs = sampleEmbeddings.map((row) => row['embedding'] as Uint8List).toList();
        final vectors = blobs.map((b) => _blobToDoubleList(b)).toList();
        
        final sim = _cosineSimilarity(vectors[0], vectors[1]);
        // If similarity is extremely close to 1.0 (e.g. > 0.9999), they are corrupt constant vectors!
        if (sim > 0.9999) {
          print('[VectorStore] Corrupt/constant embeddings detected (sim = $sim). Resetting profile to trigger re-embedding...');
          await _fallbackDb!.transaction((txn) async {
            await txn.update(
              'chunks',
              {'embedding_status': 'pending_embedding'},
              where: "profile_id = 'builtin:builtin-embedding'",
            );
            await txn.delete(
              'chunk_embeddings',
              where: "chunk_id IN (SELECT id FROM chunks WHERE profile_id = 'builtin:builtin-embedding')",
            );
          });
          print('[VectorStore] Successfully reset corrupt embeddings.');
        }
      }
    } catch (e) {
      debugPrint('[VectorStore] Self-healing error: $e');
    }

    _initialized = true;

    // Kick off one-time embedding for pending chunks (seed data from CLI builder).
    // This runs asynchronously so initialize() returns immediately.
    _embedPendingChunksAsync();
  }

  Future<void> _embedPendingChunksAsync() async {
    try {
      final pending = await countChunksByStatus('pending_embedding');
      if (pending > 0) {
        print('[VectorStore] Embedding $pending pending chunks...');
        final done = await embedPendingChunks();
        print('[VectorStore] Embedded $done/$pending pending chunks.');
      }
    } catch (e) {
      debugPrint('[VectorStore] Pending embed error (non-fatal): $e');
    }
  }

  Future<void> _normalizeSeedWikiTimestamps() async {
    final metadata = await _fallbackDb!.query('seed_metadata');
    final values = {
      for (final row in metadata) row['key'] as String: row['value'] as String,
    };
    if (values['embedding_profile_id'] != 'builtin:builtin-embedding') return;

    final builtAt = DateTime.tryParse(values['built_at'] ?? '');
    if (builtAt == null) return;

    final builtAtSeconds = builtAt.millisecondsSinceEpoch ~/ 1000;
    await _fallbackDb!.update(
      'chunks',
      {'updated_at': builtAtSeconds},
      where: "source_type = 'wiki' "
          "AND profile_id = 'builtin:builtin-embedding' "
          'AND updated_at < ?',
      whereArgs: [builtAtSeconds],
    );
  }

  bool isZeroVector(List<double> vec) {
    if (vec.isEmpty) return true;
    for (final v in vec) {
      if (v != 0.0) return false;
    }
    return true;
  }

  /// Inserts a single chunk with its embedding vector.
  Future<void> insertChunk(
    Chunk chunk,
    List<double> embedding, {
    String sourceType = 'wiki',
    String? sourceUrl,
    String? wiki,
    String? bookId,
    String profileId = _legacyProfileId,
  }) async {
    await initialize();

    final isZero = isZeroVector(embedding);
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
        'embedding_status': isZero ? 'zero_vector' : 'ok',
        'profile_id': profileId,
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
  ///
  /// BLOB serialization is performed in a background isolate via [compute]
  /// so the main/UI thread is not blocked during large indexing batches.
  Future<void> insertChunks(
    List<Chunk> chunks,
    List<List<double>> embeddings, {
    String sourceType = 'wiki',
    String? sourceUrl,
    String? wiki,
    String? bookId,
    String profileId = _legacyProfileId,
  }) async {
    if (chunks.isEmpty) return;
    await initialize();

    // Offload the CPU-intensive Float64 → BLOB conversion to a background
    // isolate. This is the primary cause of UI-thread jank/black-screen
    // during the embedding phase: each 1536-dim vector requires ~12 KB of
    // ByteData writes, and doing this for every chunk in the main isolate
    // starves the Flutter rendering pipeline.
    final blobs = await compute(_blobifyEmbeddings, embeddings);

    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await _fallbackDb!.transaction((txn) async {
      for (var i = 0; i < chunks.length; i++) {
        final isZero = isZeroVector(embeddings[i]);
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
            'updated_at': now,
            'embedding_status': isZero ? 'zero_vector' : 'ok',
            'profile_id': profileId,
          },
          conflictAlgorithm: sqflite.ConflictAlgorithm.replace,
        );
        await txn.insert(
          'chunk_embeddings',
          {
            'chunk_id': chunks[i].id,
            'embedding': blobs[i],
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
    String? profileId,
  }) async {
    await initialize();
    final results = <SearchResult>[];

    final filters = <String>[];
    final whereParams = <Object?>[];
    if (sourceType != null) {
      filters.add('c.source_type = ?');
      whereParams.add(sourceType);
    }
    if (profileId != null) {
      filters.add('c.profile_id = ?');
      whereParams.add(profileId);
    }
    final whereClause = filters.isEmpty ? '' : 'WHERE ${filters.join(' AND ')}';

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
  Future<void> deleteBySource(
    String sourceType, {
    String? bookId,
    String? wiki,
    String? profileId,
  }) async {
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

    if (profileId != null) {
      where += ' AND profile_id = ?';
      params.add(profileId);
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

  /// Returns a map of pageTitle -> {max_updated_at, has_failures} for a given wiki.
  Future<Map<String, ({int updatedAt, bool hasFailures})>> getWikiPagesMetadata(
    String wiki, {
    String? profileId,
  }) async {
    await initialize();
    final results = await _fallbackDb!.rawQuery(
      '''
      SELECT page_title, MAX(updated_at) as max_updated,
             SUM(CASE WHEN embedding_status = 'zero_vector' THEN 1 ELSE 0 END) as fail_count
      FROM chunks
      WHERE source_type = 'wiki' AND wiki = ?
      ${profileId != null ? 'AND profile_id = ?' : ''}
      GROUP BY page_title
    ''',
      profileId != null ? [wiki, profileId] : [wiki],
    );

    final metadata = <String, ({int updatedAt, bool hasFailures})>{};
    for (final row in results) {
      final title = row['page_title'] as String? ?? '';
      if (title.isEmpty) continue;
      final maxUpdated = (row['max_updated'] as int?) ?? 0;
      final failCount = (row['fail_count'] as int?) ?? 0;
      metadata[title] = (updatedAt: maxUpdated, hasFailures: failCount > 0);
    }
    return metadata;
  }

  /// Deletes chunks and embeddings for a specific Wiki page.
  Future<void> deleteWikiPage(String wiki, String pageTitle,
      {String? profileId}) async {
    await initialize();
    await _fallbackDb!.transaction((txn) async {
      final ids = await txn.query(
        'chunks',
        columns: ['id'],
        where: 'source_type = ? AND wiki = ? AND page_title = ?'
            '${profileId != null ? ' AND profile_id = ?' : ''}',
        whereArgs: [
          'wiki',
          wiki,
          pageTitle,
          if (profileId != null) profileId,
        ],
      );

      for (final row in ids) {
        await txn.delete(
          'chunk_embeddings',
          where: 'chunk_id = ?',
          whereArgs: [row['id']],
        );
      }
      await txn.delete(
        'chunks',
        where: 'source_type = ? AND wiki = ? AND page_title = ?'
            '${profileId != null ? ' AND profile_id = ?' : ''}',
        whereArgs: [
          'wiki',
          wiki,
          pageTitle,
          if (profileId != null) profileId,
        ],
      );
    });
  }

  /// Returns all chunks where embedding_status is 'zero_vector'.
  Future<List<Map<String, dynamic>>> getFailedChunks(
      {String? profileId}) async {
    await initialize();
    return await _fallbackDb!.query(
      'chunks',
      where:
      "embedding_status = 'zero_vector'${profileId != null ? ' AND profile_id = ?' : ''}",
      whereArgs: profileId != null ? [profileId] : null,
    );
  }

  /// Retrieves a single chunk by its ID.
  Future<Map<String, dynamic>?> getChunkById(String id) async {
    await initialize();
    final list = await _fallbackDb!.query(
      'chunks',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return list.isNotEmpty ? list.first : null;
  }

  /// Updates a specific chunk's embedding and marks it as 'ok'.
  Future<void> updateChunkEmbedding(
      String chunkId, List<double> embedding) async {
    await initialize();
    await _fallbackDb!.transaction((txn) async {
      await txn.update(
        'chunks',
        {
          'embedding_status': 'ok',
          'updated_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        },
        where: 'id = ?',
        whereArgs: [chunkId],
      );
      await txn.insert(
        'chunk_embeddings',
        {
          'chunk_id': chunkId,
          'embedding': _doubleListToBlob(embedding),
        },
        conflictAlgorithm: sqflite.ConflictAlgorithm.replace,
      );
    });
  }

  /// Deletes a book and all its associated chunks/embeddings.
  Future<void> deleteBook(String bookId) async {
    await deleteBySource('book', bookId: bookId);

    await _fallbackDb!.delete('books', where: 'id = ?', whereArgs: [bookId]);
  }

  Future<void> deleteProfileData(String profileId) async {
    await initialize();
    await _fallbackDb!.transaction((txn) async {
      final ids = await txn.query(
        'chunks',
        columns: ['id'],
        where: 'profile_id = ?',
        whereArgs: [profileId],
      );
      for (final row in ids) {
        await txn.delete(
          'chunk_embeddings',
          where: 'chunk_id = ?',
          whereArgs: [row['id']],
        );
      }
      await txn
          .delete('chunks', where: 'profile_id = ?', whereArgs: [profileId]);
      await txn
          .delete('books', where: 'profile_id = ?', whereArgs: [profileId]);
    });
  }

  /// Inserts or updates a book record.
  Future<void> upsertBook({
    required String id,
    required String fileName,
    String? displayName,
    int chunkCount = 0,
    String profileId = _legacyProfileId,
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
        'profile_id': profileId,
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
  Future<VectorStoreStats> getStats({String? profileId}) async {
    await initialize();

    final profileWhere = profileId != null ? ' AND profile_id = ?' : '';
    final profileArgs = profileId != null ? [profileId] : null;

    final total = sqflite.Sqflite.firstIntValue(
          await _fallbackDb!.rawQuery(
            'SELECT COUNT(*) FROM chunks WHERE 1=1$profileWhere',
            profileArgs,
          ),
        ) ??
        0;
    final wikiCount = sqflite.Sqflite.firstIntValue(
          await _fallbackDb!.rawQuery(
            "SELECT COUNT(*) FROM chunks WHERE source_type = 'wiki'$profileWhere",
            profileArgs,
          ),
        ) ??
        0;
    final bookCount = sqflite.Sqflite.firstIntValue(
          await _fallbackDb!.rawQuery(
            "SELECT COUNT(*) FROM chunks WHERE source_type = 'book'$profileWhere",
            profileArgs,
          ),
        ) ??
        0;
    final booksCount = sqflite.Sqflite.firstIntValue(
          await _fallbackDb!.rawQuery(
            'SELECT COUNT(*) FROM books WHERE 1=1${profileId != null ? ' AND profile_id = ?' : ''}',
            profileArgs,
          ),
        ) ??
        0;
    final failedCount = sqflite.Sqflite.firstIntValue(
          await _fallbackDb!.rawQuery(
            "SELECT COUNT(*) FROM chunks WHERE embedding_status = 'zero_vector'$profileWhere",
            profileArgs,
          ),
        ) ??
        0;

    return VectorStoreStats(
      totalChunks: total,
      wikiChunks: wikiCount,
      bookChunks: bookCount,
      totalBooks: booksCount,
      failedChunks: failedCount,
      useVectorExtension: false,
    );
  }

  /// Returns all books stored in the knowledge base.
  Future<List<Map<String, dynamic>>> getBooks({String? profileId}) async {
    await initialize();

    return await _fallbackDb!.query(
      'books',
      where: profileId != null ? 'profile_id = ?' : null,
      whereArgs: profileId != null ? [profileId] : null,
      orderBy: 'imported_at DESC',
    );
  }

  /// Returns the count of chunks with a given [embeddingStatus].
  Future<int> countChunksByStatus(
    String embeddingStatus, {
    String? profileId,
  }) async {
    await initialize();
    final where = profileId != null
        ? 'embedding_status = ? AND profile_id = ?'
        : 'embedding_status = ?';
    final args =
        profileId != null ? [embeddingStatus, profileId] : [embeddingStatus];
    return sqflite.Sqflite.firstIntValue(
          await _fallbackDb!.rawQuery(
            'SELECT COUNT(*) FROM chunks WHERE $where',
            args,
          ),
        ) ??
        0;
  }

  /// Embeds all chunks with `pending_embedding` status using the builtin model.
  ///
  /// Returns the number of chunks successfully embedded. This is a one-time
  /// operation on the first launch after seed install.
  Future<int> embedPendingChunks({
    String? profileId,
    void Function(int current, int total)? onProgress,
  }) async {
    await initialize();

    final rows = await _fallbackDb!.query(
      'chunks',
      columns: ['id', 'content'],
      where: "embedding_status = 'pending_embedding'"
          '${profileId != null ? ' AND profile_id = ?' : ''}',
      whereArgs: profileId != null ? [profileId] : null,
    );
    if (rows.isEmpty) return 0;

    // Load builtin embedding client from assets
    final client = await BuiltinEmbeddingClient.load();
    var embedded = 0;

    try {
      for (var i = 0; i < rows.length; i++) {
        final row = rows[i];
        final id = row['id'] as String;
        final content = row['content'] as String;

        if (content.trim().isEmpty) {
          await _fallbackDb!.update(
            'chunks',
            {'embedding_status': 'zero_vector'},
            where: 'id = ?',
            whereArgs: [id],
          );
          embedded++;
          continue;
        }

        try {
          final vector = await client.embed(content);
          if (isZeroVector(vector)) {
            await _fallbackDb!.update(
              'chunks',
              {'embedding_status': 'zero_vector'},
              where: 'id = ?',
              whereArgs: [id],
            );
          } else {
            await _fallbackDb!.update(
              'chunks',
              {'embedding_status': 'ok'},
              where: 'id = ?',
              whereArgs: [id],
            );
            await _fallbackDb!.insert(
              'chunk_embeddings',
              {
                'chunk_id': id,
                'embedding': _doubleListToBlob(vector),
              },
              conflictAlgorithm: sqflite.ConflictAlgorithm.replace,
            );
          }
        } catch (_) {
          await _fallbackDb!.update(
            'chunks',
            {'embedding_status': 'zero_vector'},
            where: 'id = ?',
            whereArgs: [id],
          );
        }

        embedded++;
        onProgress?.call(embedded, rows.length);
      }
    } finally {
      client.dispose();
    }

    return embedded;
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

  /// Reads a single seed metadata value by key.
  Future<String?> getSeedMetadata(String key) async {
    await initialize();
    final rows = await _fallbackDb!.query(
      'seed_metadata',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
    );
    return rows.isNotEmpty ? rows.first['value'] as String? : null;
  }

  /// Reads all seed metadata as a map.
  Future<Map<String, String>> getAllSeedMetadata() async {
    await initialize();
    final rows = await _fallbackDb!.query('seed_metadata');
    return {for (final r in rows) r['key'] as String: r['value'] as String};
  }

  /// Upserts a seed metadata entry (insert or replace).
  Future<void> upsertSeedMetadata(String key, String value) async {
    await initialize();
    await _fallbackDb!.insert(
      'seed_metadata',
      {'key': key, 'value': value},
      conflictAlgorithm: sqflite.ConflictAlgorithm.replace,
    );
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
