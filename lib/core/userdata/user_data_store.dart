/// 0.11 library page: the user database (`userdata/arklores_user.db`).
///
/// Everything the user creates lives here — reading history, bookmarks and
/// (M4) imported materials — and nowhere else. The official knowledge base
/// stays read-only and is replaced as a whole on update; the two files are
/// never `ATTACH`ed and share no foreign keys. Items are addressed with
/// [LibraryRef] strings, so a knowledge base update cannot break or delete
/// user data (`docs/V0.11_PLAN.md` §3.1).
///
/// The schema evolves through [userDataMigrations] (`PRAGMA user_version`):
/// append a step, never edit a released one.
library;

import 'package:sqflite_common/sqlite_api.dart';

import 'library_ref.dart';

/// File name of the user database inside its own `userdata/` directory.
const String userDataFileName = 'arklores_user.db';

/// Ordered schema steps; step `i` upgrades `user_version` i → i + 1.
final List<Future<void> Function(DatabaseExecutor db)> userDataMigrations = [
  // v1 (0.11 M1): reading history and bookmarks.
  (db) async {
    await db.execute('''
      CREATE TABLE reading_progress (
        ref          TEXT PRIMARY KEY,
        title        TEXT NOT NULL,
        line_index   INTEGER NOT NULL DEFAULT 0,
        opened_at    INTEGER NOT NULL,
        open_count   INTEGER NOT NULL DEFAULT 1,
        finished     INTEGER NOT NULL DEFAULT 0,
        from_citation INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_reading_progress_opened ON reading_progress(opened_at)',
    );
    await db.execute('''
      CREATE TABLE bookmarks (
        id          TEXT PRIMARY KEY,
        ref         TEXT NOT NULL,
        title       TEXT NOT NULL,
        line_start  INTEGER,
        line_end    INTEGER,
        note        TEXT,
        created_at  INTEGER NOT NULL
      )
    ''');
    await db.execute('CREATE INDEX idx_bookmarks_ref ON bookmarks(ref)');
  },
];

/// Schema version produced by [userDataMigrations].
int get userDataSchemaVersion => userDataMigrations.length;

/// Where the user is in one item, for "continue reading".
class ReadingProgress {
  const ReadingProgress({
    required this.ref,
    required this.title,
    required this.lineIndex,
    required this.openedAt,
    required this.openCount,
    required this.finished,
    required this.fromCitation,
  });

  factory ReadingProgress.fromRow(Map<String, Object?> row) => ReadingProgress(
        ref: row['ref']! as String,
        title: row['title']! as String,
        lineIndex: (row['line_index']! as num).toInt(),
        openedAt: DateTime.fromMillisecondsSinceEpoch(
          (row['opened_at']! as num).toInt(),
        ),
        openCount: (row['open_count']! as num).toInt(),
        finished: row['finished'] == 1,
        fromCitation: row['from_citation'] == 1,
      );

  /// Serialized [LibraryRef]; parse with [LibraryRef.tryParse].
  final String ref;
  final String title;

  /// 0-based line (stories) or section index (documents) last shown.
  final int lineIndex;
  final DateTime openedAt;
  final int openCount;
  final bool finished;

  /// True while the item was only ever opened from an answer's evidence
  /// chain; reading it from the library clears the flag.
  final bool fromCitation;
}

/// A saved place (a line range, optionally with a note) in one item.
class LibraryBookmark {
  const LibraryBookmark({
    required this.id,
    required this.ref,
    required this.title,
    required this.createdAt,
    this.lineStart,
    this.lineEnd,
    this.note,
  });

  factory LibraryBookmark.fromRow(Map<String, Object?> row) => LibraryBookmark(
        id: row['id']! as String,
        ref: row['ref']! as String,
        title: row['title']! as String,
        lineStart: (row['line_start'] as num?)?.toInt(),
        lineEnd: (row['line_end'] as num?)?.toInt(),
        note: row['note'] as String?,
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          (row['created_at']! as num).toInt(),
        ),
      );

  final String id;
  final String ref;
  final String title;
  final int? lineStart;
  final int? lineEnd;
  final String? note;
  final DateTime createdAt;
}

/// Opens, migrates and serves the user database.
class UserDataStore {
  UserDataStore({
    required this.factory,
    required this.path,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final DatabaseFactory factory;

  /// Absolute path of the database file.
  final String path;
  final DateTime Function() _clock;

  Database? _db;
  Future<Database>? _opening;

  Future<Database> get _database {
    final db = _db;
    if (db != null) return Future.value(db);
    return _opening ??= _open();
  }

  Future<Database> _open() async {
    final db = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: userDataSchemaVersion,
        onUpgrade: (db, from, to) async {
          for (var v = from; v < to; v++) {
            await userDataMigrations[v](db);
          }
        },
        onCreate: (db, version) async {
          for (final step in userDataMigrations) {
            await step(db);
          }
        },
        onDowngrade: (db, from, to) async {
          // A newer app wrote this file. Its extra tables and columns are
          // left alone; this version only touches what it knows.
        },
      ),
    );
    _db = db;
    return db;
  }

  Future<void> close() async {
    final db = _db;
    _db = null;
    _opening = null;
    await db?.close();
  }

  // ─── Reading history ────────────────────────────────────────────

  /// Records that [ref] was opened at [lineIndex]. An open from the evidence
  /// chain ([fromCitation]) does not overwrite a library reading position.
  Future<void> recordOpen(
    LibraryRef ref, {
    required String title,
    int lineIndex = 0,
    bool fromCitation = false,
  }) async {
    final db = await _database;
    final now = _clock().millisecondsSinceEpoch;
    final key = ref.toString();
    await db.transaction((txn) async {
      final existing = await txn.query(
        'reading_progress',
        where: 'ref = ?',
        whereArgs: [key],
        limit: 1,
      );
      if (existing.isEmpty) {
        await txn.insert('reading_progress', {
          'ref': key,
          'title': title,
          'line_index': lineIndex,
          'opened_at': now,
          'from_citation': fromCitation ? 1 : 0,
        });
        return;
      }
      final keepPosition = fromCitation && existing.first['from_citation'] == 0;
      await txn.update(
        'reading_progress',
        {
          'title': title,
          'opened_at': now,
          'open_count': (existing.first['open_count']! as num).toInt() + 1,
          if (!keepPosition) 'line_index': lineIndex,
          if (!fromCitation) 'from_citation': 0,
        },
        where: 'ref = ?',
        whereArgs: [key],
      );
    });
  }

  /// Saves the position while reading (callers throttle this).
  Future<void> updatePosition(
    LibraryRef ref,
    int lineIndex, {
    bool? finished,
  }) async {
    final db = await _database;
    await db.update(
      'reading_progress',
      {
        'line_index': lineIndex,
        if (finished != null) 'finished': finished ? 1 : 0,
      },
      where: 'ref = ?',
      whereArgs: [ref.toString()],
    );
  }

  Future<ReadingProgress?> progressOf(LibraryRef ref) async {
    final db = await _database;
    final rows = await db.query(
      'reading_progress',
      where: 'ref = ?',
      whereArgs: [ref.toString()],
      limit: 1,
    );
    return rows.isEmpty ? null : ReadingProgress.fromRow(rows.first);
  }

  /// Most recently opened first. [includeCitationOnly] adds items that were
  /// only opened from an answer's evidence chain.
  Future<List<ReadingProgress>> recent({
    int limit = 50,
    bool includeCitationOnly = true,
  }) async {
    final db = await _database;
    final rows = await db.query(
      'reading_progress',
      where: includeCitationOnly ? null : 'from_citation = 0',
      orderBy: 'opened_at DESC',
      limit: limit,
    );
    return rows.map(ReadingProgress.fromRow).toList();
  }

  /// Removes one item from the history, or all of it when [ref] is null.
  Future<void> clearHistory([LibraryRef? ref]) async {
    final db = await _database;
    await db.delete(
      'reading_progress',
      where: ref == null ? null : 'ref = ?',
      whereArgs: ref == null ? null : [ref.toString()],
    );
  }

  // ─── Bookmarks ──────────────────────────────────────────────────

  Future<void> saveBookmark(LibraryBookmark bookmark) async {
    final db = await _database;
    await db.insert(
      'bookmarks',
      {
        'id': bookmark.id,
        'ref': bookmark.ref,
        'title': bookmark.title,
        'line_start': bookmark.lineStart,
        'line_end': bookmark.lineEnd,
        'note': bookmark.note,
        'created_at': bookmark.createdAt.millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteBookmark(String id) async {
    final db = await _database;
    await db.delete('bookmarks', where: 'id = ?', whereArgs: [id]);
  }

  /// Newest first; only those of [ref] when given.
  Future<List<LibraryBookmark>> bookmarks({LibraryRef? ref}) async {
    final db = await _database;
    final rows = await db.query(
      'bookmarks',
      where: ref == null ? null : 'ref = ?',
      whereArgs: ref == null ? null : [ref.toString()],
      orderBy: 'created_at DESC',
    );
    return rows.map(LibraryBookmark.fromRow).toList();
  }
}
