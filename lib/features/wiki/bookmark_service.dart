import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

/// A single bookmark entry for a Wiki page.
class Bookmark {
  final String id;
  final String title;
  final String url;
  final String site;
  final int createdAt;

  const Bookmark({
    required this.id,
    required this.title,
    required this.url,
    required this.site,
    required this.createdAt,
  });

  /// Creates a new [Bookmark] with a generated UUID and current timestamp.
  factory Bookmark.create({
    required String title,
    required String url,
    required String site,
  }) {
    return Bookmark(
      id: const Uuid().v4(),
      title: title,
      url: url,
      site: site,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
  }

  factory Bookmark.fromMap(Map<String, dynamic> map) {
    return Bookmark(
      id: map['id'] as String,
      title: map['title'] as String,
      url: map['url'] as String,
      site: map['site'] as String,
      createdAt: map['created_at'] as int,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'url': url,
      'site': site,
      'created_at': createdAt,
    };
  }

  /// Human-readable site label.
  String get siteLabel => site == 'prts' ? 'PRTS Wiki' : 'Endfield Wiki';

  @override
  String toString() => 'Bookmark($title — $siteLabel)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Bookmark && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// Singleton service managing bookmark persistence via SQLite.
///
/// Uses a local `arklores_bookmarks.db` database with a `bookmarks` table.
class BookmarkService {
  /// Singleton instance.
  static final BookmarkService _instance = BookmarkService._();
  factory BookmarkService() => _instance;
  BookmarkService._();

  Database? _db;

  /// Returns the (cached) database, initialising it on first access.
  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDatabase();
    return _db!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = '$dbPath/arklores_bookmarks.db';
    return openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE bookmarks (
            id         TEXT PRIMARY KEY,
            title      TEXT NOT NULL,
            url        TEXT NOT NULL,
            site       TEXT NOT NULL,
            created_at INTEGER NOT NULL
          )
        ''');
      },
    );
  }

  // ─── CRUD ──────────────────────────────────────────────────────

  /// Inserts or replaces a bookmark.
  Future<void> insert(Bookmark bookmark) async {
    final db = await database;
    await db.insert(
      'bookmarks',
      bookmark.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Deletes a bookmark by its [id].
  Future<void> delete(String id) async {
    final db = await database;
    await db.delete('bookmarks', where: 'id = ?', whereArgs: [id]);
  }

  /// Deletes the bookmark for the given [url].
  Future<void> deleteByUrl(String url) async {
    final db = await database;
    await db.delete('bookmarks', where: 'url = ?', whereArgs: [url]);
  }

  /// Returns all bookmarks ordered by creation time (newest first).
  Future<List<Bookmark>> getAll() async {
    final db = await database;
    final maps = await db.query(
      'bookmarks',
      orderBy: 'created_at DESC',
    );
    return maps.map((m) => Bookmark.fromMap(m)).toList();
  }

  /// Returns the bookmark for [url], or `null` if not bookmarked.
  Future<Bookmark?> getByUrl(String url) async {
    final db = await database;
    final maps = await db.query(
      'bookmarks',
      where: 'url = ?',
      whereArgs: [url],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return Bookmark.fromMap(maps.first);
  }

  /// Returns the number of bookmarks currently stored.
  Future<int> count() async {
    final db = await database;
    final result = await db.rawQuery('SELECT COUNT(*) AS cnt FROM bookmarks');
    return Sqflite.firstIntValue(result) ?? 0;
  }
}
