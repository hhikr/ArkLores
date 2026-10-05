import 'package:arklores/core/userdata/library_ref.dart';
import 'package:arklores/core/userdata/user_data_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// A [UserDataStore] in memory. Real SQLite needs real async, which lets the
/// theme's font downloads run (and fail) inside widget tests; the real store
/// has its own tests in `user_data_store_test.dart`.
class MemoryUserStore extends UserDataStore {
  MemoryUserStore() : super(factory: databaseFactoryFfi, path: 'unused');

  final Map<String, ReadingEntry> rows = {};
  final Map<String, UserMaterial> items = {};
  var _tick = 0;

  DateTime _now() => DateTime(2026, 10, 5).add(Duration(minutes: _tick++));

  @override
  Future<void> recordOpen(
    LibraryRef ref, {
    required String title,
    required int lineIndex,
    required String snippet,
    int totalLines = 0,
  }) async {
    final old = rows[ref.toString()];
    rows[ref.toString()] = ReadingEntry(
      ref: ref.toString(),
      title: title,
      lineIndex: lineIndex,
      snippet: historySnippetOf(snippet),
      openedAt: _now(),
      openCount: (old?.openCount ?? 0) + 1,
      totalLines: totalLines > 0 ? totalLines : old?.totalLines ?? 0,
      furthest: old?.furthest ?? 0,
    );
  }

  @override
  Future<void> updateProgress(
    LibraryRef ref, {
    required int lineIndex,
    required String snippet,
    required int totalLines,
    int? reached,
  }) async {
    final old = rows[ref.toString()];
    if (old == null) return;
    final far = reached ?? lineIndex;
    rows[ref.toString()] = ReadingEntry(
      ref: old.ref,
      title: old.title,
      lineIndex: lineIndex,
      snippet: historySnippetOf(snippet),
      openedAt: old.openedAt,
      openCount: old.openCount,
      totalLines: totalLines,
      furthest: far > old.furthest ? far : old.furthest,
    );
  }

  @override
  Future<Map<String, ReadingEntry>> progressByRef() async => Map.of(rows);

  @override
  Future<List<ReadingEntry>> recent({int limit = 50}) async =>
      (rows.values.toList()..sort((a, b) => b.openedAt.compareTo(a.openedAt)))
          .take(limit)
          .toList();

  @override
  Future<void> clearHistory([LibraryRef? ref]) async =>
      ref == null ? rows.clear() : rows.remove(ref.toString());

  @override
  Future<List<UserMaterial>> materials() async =>
      items.values.toList()..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  @override
  Future<UserMaterial?> material(String id) async => items[id];

  @override
  Future<UserMaterial> saveMaterial({
    String? id,
    required String title,
    required String body,
  }) async {
    final now = _now();
    final key = id ?? 'm${items.length + 1}';
    final old = items[key];
    final saved = UserMaterial(
      id: key,
      title: title.trim().isEmpty ? body.trim().split('\n').first : title.trim(),
      body: body,
      createdAt: old?.createdAt ?? now,
      updatedAt: now,
    );
    items[key] = saved;
    return saved;
  }

  @override
  Future<void> deleteMaterial(String id) async {
    items.remove(id);
    rows.remove(LibraryRef.user(id).toString());
  }

  @override
  Future<void> close() async {}
}
