import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' as sqflite;

import 'user_data_store.dart';

/// The app's user database, in `<documents>/userdata/` — a different
/// directory from the knowledge base, so replacing or deleting the knowledge
/// base can never touch it. Tests override this provider.
final userDataStoreProvider = FutureProvider<UserDataStore>((ref) async {
  final docs = await getApplicationDocumentsDirectory();
  final dir = Directory(p.join(docs.path, 'userdata'));
  await dir.create(recursive: true);
  final store = UserDataStore(
    factory: sqflite.databaseFactory,
    path: p.join(dir.path, userDataFileName),
  );
  ref.onDispose(store.close);
  return store;
});

/// Items per page of the reading history.
const int historyPageSize = 15;

/// The latest few items, for the front page of the library. Invalidate after
/// changing the history.
final recentReadingProvider =
    FutureProvider.autoDispose<List<ReadingEntry>>((ref) async {
  final store = await ref.watch(userDataStoreProvider.future);
  return store.recent(limit: 5);
});

/// Size of the whole reading history.
final readingCountProvider = FutureProvider.autoDispose<int>((ref) async {
  final store = await ref.watch(userDataStoreProvider.future);
  return store.historyCount();
});

/// One page (0-based) of the reading history, newest first: only that page is
/// read from the database.
final readingPageProvider =
    FutureProvider.autoDispose.family<List<ReadingEntry>, int>((ref, page) async {
  final store = await ref.watch(userDataStoreProvider.future);
  return store.recent(limit: historyPageSize, offset: page * historyPageSize);
});
