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

/// The reading history, newest first. Invalidate after changing it.
final recentReadingProvider =
    FutureProvider.autoDispose<List<ReadingEntry>>((ref) async {
  final store = await ref.watch(userDataStoreProvider.future);
  return store.recent(limit: historyLimit);
});
