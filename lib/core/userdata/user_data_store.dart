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
const int historyLimit = 1000;

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
  // v2: how far the item was read — its length and the furthest line reached
  // (the anchor is where the reader is, which can be earlier).
  (db) async {
    await db.execute(
      'ALTER TABLE reading_history '
      'ADD COLUMN total_lines INTEGER NOT NULL DEFAULT 0',
    );
    await db.execute(
      'ALTER TABLE reading_history '
      'ADD COLUMN furthest INTEGER NOT NULL DEFAULT 0',
    );
  },
  // v3: the user's own materials (notes, pasted texts).
  (db) async {
    await db.execute('''
      CREATE TABLE materials (
        id         TEXT PRIMARY KEY,
        title      TEXT NOT NULL,
        body       TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_materials_updated ON materials(updated_at)',
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
    this.totalLines = 0,
    this.furthest = 0,
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
        totalLines: (row['total_lines'] as num?)?.toInt() ?? 0,
        furthest: (row['furthest'] as num?)?.toInt() ?? 0,
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

  /// Length of the item when last read (0 = unknown) and the furthest
  /// 0-based line reached.
  final int totalLines;
  final int furthest;

  /// 0..1 share of the item read, or null when its length is unknown.
  double? get progress =>
      totalLines <= 0 ? null : ((furthest + 1) / totalLines).clamp(0.0, 1.0);

  /// Read to (nearly) the end.
  bool get finished => totalLines > 0 && furthest >= totalLines - 3;
}

/// A text the user wrote or pasted.
class UserMaterial {
  const UserMaterial({
    required this.id,
    required this.title,
    required this.body,
    required this.createdAt,
    required this.updatedAt,
  });

  factory UserMaterial.fromRow(Map<String, Object?> row) => UserMaterial(
        id: row['id']! as String,
        title: row['title']! as String,
        body: row['body']! as String,
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          (row['created_at']! as num).toInt(),
        ),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(
          (row['updated_at']! as num).toInt(),
        ),
      );

  final String id;
  final String title;
  final String body;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// The reference history and links use for this material.
  LibraryRef get ref => LibraryRef.user(id);
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
    int totalLines = 0,
  }) async {
    final db = await _database;
    final now = _clock().millisecondsSinceEpoch;
    final key = ref.toString();
    final cut = historySnippetOf(snippet);
    await db.transaction((txn) async {
      final changed = await txn.rawUpdate(
        'UPDATE reading_history SET title = ?, line_index = ?, snippet = ?, '
        'opened_at = ?, open_count = open_count + 1, '
        'total_lines = CASE WHEN ? > 0 THEN ? ELSE total_lines END '
        'WHERE ref = ?',
        [title, lineIndex, cut, now, totalLines, totalLines, key],
      );
      if (changed == 0) {
        await txn.insert('reading_history', {
          'ref': key,
          'title': title,
          'line_index': lineIndex,
          'snippet': cut,
          'opened_at': now,
          'total_lines': totalLines,
        });
      }
      await txn.rawDelete(
        'DELETE FROM reading_history WHERE ref NOT IN '
        '(SELECT ref FROM reading_history ORDER BY opened_at DESC LIMIT ?)',
        [historyLimit],
      );
    });
  }

  /// Saves where the reader is now (callers throttle this): the anchor
  /// ([lineIndex], the first line on screen) moves, the furthest line
  /// ([reached], the last line on screen) only grows. A visit that was not recorded
  /// first is ignored.
  Future<void> updateProgress(
    LibraryRef ref, {
    required int lineIndex,
    required String snippet,
    required int totalLines,
    int? reached,
  }) async {
    final db = await _database;
    await db.rawUpdate(
      'UPDATE reading_history SET line_index = ?, snippet = ?, '
      'total_lines = ?, furthest = MAX(furthest, ?) WHERE ref = ?',
      [
        lineIndex,
        historySnippetOf(snippet),
        totalLines,
        reached ?? lineIndex,
        ref.toString(),
      ],
    );
  }

  /// Every entry by reference, for progress marks on lists.
  Future<Map<String, ReadingEntry>> progressByRef() async {
    final db = await _database;
    final rows = await db.query('reading_history');
    return {
      for (final row in rows)
        row['ref']! as String: ReadingEntry.fromRow(row),
    };
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

  // ─── Materials ──────────────────────────────────────────────────

  /// Most recently changed first.
  Future<List<UserMaterial>> materials() async {
    final db = await _database;
    final rows = await db.query(
      'materials',
      orderBy: 'updated_at DESC, rowid DESC',
    );
    return rows.map(UserMaterial.fromRow).toList();
  }

  Future<UserMaterial?> material(String id) async {
    final db = await _database;
    final rows = await db.query(
      'materials',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : UserMaterial.fromRow(rows.first);
  }

  /// Creates a material (when [id] is null: with a new id) or replaces the
  /// title and text of [id]. Returns the saved material.
  Future<UserMaterial> saveMaterial({
    String? id,
    required String title,
    required String body,
  }) async {
    final db = await _database;
    final now = _clock().millisecondsSinceEpoch;
    final cleanTitle = title.trim().isEmpty ? _titleFrom(body) : title.trim();
    final key = id ?? 'm${now.toRadixString(36)}${_serial++}';
    final changed = id == null
        ? 0
        : await db.update(
            'materials',
            {'title': cleanTitle, 'body': body, 'updated_at': now},
            where: 'id = ?',
            whereArgs: [id],
          );
    if (changed == 0) {
      await db.insert('materials', {
        'id': key,
        'title': cleanTitle,
        'body': body,
        'created_at': now,
        'updated_at': now,
      });
    }
    return (await material(key))!;
  }

  Future<void> deleteMaterial(String id) async {
    final db = await _database;
    await db.delete('materials', where: 'id = ?', whereArgs: [id]);
    await clearHistory(LibraryRef.user(id));
  }

  int _serial = 0;

  /// First non-empty line of [body], shortened, as a default title.
  static String _titleFrom(String body) {
    for (final line in body.split('\n')) {
      final t = line.trim();
      if (t.isNotEmpty) return t.length <= 24 ? t : '${t.substring(0, 24)}…';
    }
    return '';
  }
}
