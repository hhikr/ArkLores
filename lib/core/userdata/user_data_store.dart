/// 0.11: the user database (`userdata/arklores_user.db`).
///
/// Everything the user creates lives here — reading history now, imported
/// materials later — and nowhere else. The official knowledge base stays
/// read-only and is replaced as a whole on update; the two files are never
/// `ATTACH`ed and share no foreign keys. Items are addressed with
/// [LibraryRef] strings, so a knowledge base update cannot break or delete
/// user data.
///
/// The schema evolves through [userDataMigrations] (`PRAGMA user_version`):
/// append a step, never edit a released one.
library;

import 'package:sqflite_common/sqlite_api.dart';

import 'library_ref.dart';

/// File name of the user database inside its own `userdata/` directory.
const String userDataFileName = 'arklores_user.db';

/// Longest snippet kept per history entry, in characters.
const int historySnippetLength = 60;

/// Entries kept in the history; the oldest are dropped beyond this.
const int historyLimit = 200;

/// Ordered schema steps; step `i` upgrades `user_version` i → i + 1.
final List<Future<void> Function(DatabaseExecutor db)> userDataMigrations = [
  // v1: reading history — one row per item: its title, one anchor line and
  // that line's text, so the place can be found again after the knowledge
  // base changed.
  (db) async {
    await db.execute('''
      CREATE TABLE reading_history (
        ref        TEXT PRIMARY KEY,
        title      TEXT NOT NULL,
        line_index INTEGER NOT NULL DEFAULT 0,
        snippet    TEXT NOT NULL DEFAULT '',
        opened_at  INTEGER NOT NULL,
        open_count INTEGER NOT NULL DEFAULT 1
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_reading_history_opened ON reading_history(opened_at)',
    );
  },
];

/// Schema version produced by [userDataMigrations].
int get userDataSchemaVersion => userDataMigrations.length;

/// One item the user read: where, and what the line there said.
class ReadingEntry {
  const ReadingEntry({
    required this.ref,
    required this.title,
    required this.lineIndex,
    required this.snippet,
    required this.openedAt,
    required this.openCount,
  });

  factory ReadingEntry.fromRow(Map<String, Object?> row) => ReadingEntry(
        ref: row['ref']! as String,
        title: row['title']! as String,
        lineIndex: (row['line_index']! as num).toInt(),
        snippet: row['snippet']! as String,
        openedAt: DateTime.fromMillisecondsSinceEpoch(
          (row['opened_at']! as num).toInt(),
        ),
        openCount: (row['open_count']! as num).toInt(),
      );

  /// Serialized [LibraryRef]; parse with [LibraryRef.tryParse].
  final String ref;

  /// Item title as shown when it was read ("collection · chapter").
  final String title;

  /// 0-based anchor line when it was read.
  final int lineIndex;

  /// Start of the anchor line's text (up to [historySnippetLength] chars).
  final String snippet;
  final DateTime openedAt;
  final int openCount;
}

/// The text kept for an anchor line.
String historySnippetOf(String content) {
  final text = content.trim();
  return text.length <= historySnippetLength
      ? text
      : text.substring(0, historySnippetLength);
}

/// Finds the anchor again in the current [lines] (their texts, in order).
///
/// The knowledge base can change between two visits: a story gains or loses
/// lines. The anchor line is [lineIndex] when it still starts with [snippet];
/// otherwise the nearest line that does; otherwise [lineIndex] clamped into
/// the story (the place is approximate then, `exact` is false). Returns null
/// for an empty story.
({int index, bool exact})? reanchorLine(
  List<String> lines,
  int lineIndex,
  String snippet,
) {
  if (lines.isEmpty) return null;
  final want = snippet.trim();
  bool matches(int i) => want.isNotEmpty && lines[i].trim().startsWith(want);
  final clamped = lineIndex.clamp(0, lines.length - 1);
  if (lineIndex >= 0 && lineIndex < lines.length && matches(lineIndex)) {
    return (index: lineIndex, exact: true);
  }
  for (var d = 1; d < lines.length; d++) {
    for (final i in [clamped - d, clamped + d]) {
      if (i >= 0 && i < lines.length && matches(i)) {
        return (index: i, exact: true);
      }
    }
  }
  return (index: clamped, exact: want.isEmpty && lineIndex == clamped);
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
    // The version is managed here, not by sqflite: when a newer app wrote
    // this file, sqflite would stamp the older version number back on it and
    // the newer app would then re-run steps that already happened.
    final db = await factory.openDatabase(path);
    final from = await db.getVersion();
    if (from < userDataSchemaVersion) {
      await db.transaction((txn) async {
        for (var v = from; v < userDataSchemaVersion; v++) {
          await userDataMigrations[v](txn);
        }
        await txn.execute('PRAGMA user_version = $userDataSchemaVersion');
      });
    }
    // A newer file keeps its extra tables and columns; this version only
    // touches what it knows.
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

  /// Records that [ref] was read at [lineIndex] (whose text is [snippet]).
  /// Reading the same item again replaces its anchor and counts the visit.
  Future<void> recordOpen(
    LibraryRef ref, {
    required String title,
    required int lineIndex,
    required String snippet,
  }) async {
    final db = await _database;
    final now = _clock().millisecondsSinceEpoch;
    final key = ref.toString();
    final cut = historySnippetOf(snippet);
    await db.transaction((txn) async {
      final changed = await txn.rawUpdate(
        'UPDATE reading_history SET title = ?, line_index = ?, snippet = ?, '
        'opened_at = ?, open_count = open_count + 1 WHERE ref = ?',
        [title, lineIndex, cut, now, key],
      );
      if (changed == 0) {
        await txn.insert('reading_history', {
          'ref': key,
          'title': title,
          'line_index': lineIndex,
          'snippet': cut,
          'opened_at': now,
        });
      }
      await txn.rawDelete(
        'DELETE FROM reading_history WHERE ref NOT IN '
        '(SELECT ref FROM reading_history ORDER BY opened_at DESC LIMIT ?)',
        [historyLimit],
      );
    });
  }

  /// Most recently read first.
  Future<List<ReadingEntry>> recent({int limit = 50}) async {
    final db = await _database;
    final rows = await db.query(
      'reading_history',
      orderBy: 'opened_at DESC, rowid DESC',
      limit: limit,
    );
    return rows.map(ReadingEntry.fromRow).toList();
  }

  /// Removes one item from the history, or all of it when [ref] is null.
  Future<void> clearHistory([LibraryRef? ref]) async {
    final db = await _database;
    await db.delete(
      'reading_history',
      where: ref == null ? null : 'ref = ?',
      whereArgs: ref == null ? null : [ref.toString()],
    );
  }
}
