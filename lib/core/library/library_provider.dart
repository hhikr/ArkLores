import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_common/sqlite_api.dart' show DatabaseExecutor;

import '../agent/agent_provider.dart' show sharedGameDataStoreProvider;
import '../userdata/user_data_provider.dart';
import '../userdata/user_data_store.dart';
import 'library_queries.dart';

/// Whether the library can be shown.
enum LibraryStatus {
  /// No knowledge base installed.
  notInstalled,

  /// An installed knowledge base from before the entry layer (schema 4).
  oldSchema,
  ready,
}

/// Runs [action] on the knowledge base; null when none is installed or the
/// query fails (the pages then show their empty state).
Future<R?> _query<R>(
  Ref ref,
  Future<R> Function(DatabaseExecutor db) action,
) async {
  try {
    return await ref.watch(sharedGameDataStoreProvider).withDatabase(action);
  } catch (_) {
    return null;
  }
}

final libraryStatusProvider =
    FutureProvider.autoDispose<LibraryStatus>((ref) async {
  final ready = await _query(ref, (db) => hasEntryLayer(db));
  if (ready == null) {
    // Distinguish "no database" from a failed query: with a store, a query
    // error is reported as not installed too — the page offers the
    // knowledge base page either way.
    return LibraryStatus.notInstalled;
  }
  return ready ? LibraryStatus.ready : LibraryStatus.oldSchema;
});

final shelfSummariesProvider =
    FutureProvider.autoDispose<List<ShelfSummary>>((ref) async =>
        await _query(ref, (db) => shelfSummaries(db)) ?? const [],);

final codexTypesProvider =
    FutureProvider.autoDispose<List<({String type, int count})>>((ref) async =>
        await _query(ref, (db) => codexTypes(db)) ?? const [],);

final collectionsOfKindProvider = FutureProvider.autoDispose
    .family<List<LibraryCollection>, String>((ref, kind) async =>
        await _query(ref, (db) => collectionsOfKind(db, kind)) ?? const [],);

final collectionProvider = FutureProvider.autoDispose
    .family<LibraryCollection?, String>((ref, id) async =>
        _query<LibraryCollection?>(ref, (db) => collectionById(db, id)),);

final collectionTypesProvider = FutureProvider.autoDispose
    .family<List<({String type, int count})>, String>((ref, id) async =>
        await _query(ref, (db) => collectionTypes(db, id)) ?? const [],);

final collectionIntroProvider = FutureProvider.autoDispose
    .family<String?, String>((ref, id) async =>
        _query<String?>(ref, (db) => collectionIntro(db, id)),);

final collectionInlineProvider = FutureProvider.autoDispose
    .family<List<LibraryEntry>, String>((ref, id) async =>
        await _query(ref, (db) => inlineEntries(db, id)) ?? const [],);

final entryPartsProvider = FutureProvider.autoDispose
    .family<List<LibraryEntry>, String>((ref, id) async =>
        await _query(ref, (db) => entryParts(db, id)) ?? const [],);

final collectionStoriesProvider = FutureProvider.autoDispose
    .family<List<LibraryEntry>, String>((ref, id) async =>
        await _query(ref, (db) => storiesOf(db, id)) ?? const [],);

/// Which entries a list shows: one type, in a collection or (null) in the
/// codex, filtered by [query].
typedef EntryListKey = ({
  String type,
  String? collectionId,
  String query,
  String groups,
});

/// [EntryListKey.groups] for a set of groups (a null element is "no group"):
/// a plain string, so the key compares by value.
String groupsKey(List<String?>? groups) => groups == null
    ? ''
    : groups.map((g) => g ?? '\u0000').join('\u0001');

List<String?>? _groupsOf(String key) => key.isEmpty
    ? null
    : [for (final g in key.split('\u0001')) g == '\u0000' ? null : g];

final entriesOfTypeProvider = FutureProvider.autoDispose
    .family<List<LibraryEntry>, EntryListKey>((ref, key) async =>
        await _query(
          ref,
          (db) => entriesOfType(
            db,
            key.type,
            collectionId: key.collectionId,
            query: key.query,
            groups: _groupsOf(key.groups),
          ),
        ) ??
        const [],);

/// The groups of one type's entries, for the menu above a long list.
typedef EntryGroupsKey = ({String type, String? collectionId});

final entryGroupsProvider = FutureProvider.autoDispose
    .family<List<({String? group, int count})>, EntryGroupsKey>(
        (ref, key) async =>
            await _query(
              ref,
              (db) => entryGroups(db, key.type, collectionId: key.collectionId),
            ) ??
            const [],);

final entryProvider = FutureProvider.autoDispose
    .family<LibraryEntry?, String>((ref, id) async =>
        _query<LibraryEntry?>(ref, (db) => entryById(db, id)),);

final entryTextsProvider = FutureProvider.autoDispose
    .family<List<EntryTextBlock>, LibraryEntry>((ref, entry) async =>
        await _query(ref, (db) => entryTexts(db, entry)) ?? const [],);

final entryBindingsProvider = FutureProvider.autoDispose
    .family<List<EntryBinding>, String>((ref, id) async =>
        await _query(ref, (db) => entryBindings(db, id)) ?? const [],);

final operatorMemoriesProvider = FutureProvider.autoDispose
    .family<List<LibraryCollection>, String>((ref, id) async =>
        await _query(ref, (db) => collectionsOwnedBy(db, id)) ?? const [],);

final operatorOwnedProvider = FutureProvider.autoDispose
    .family<List<LibraryEntry>, String>((ref, id) async =>
        await _query(ref, (db) => entriesOwnedBy(db, id)) ?? const [],);

/// The in-battle dialogue attached to a stage or story entry, in order.
final attachedStoriesProvider = FutureProvider.autoDispose
    .family<List<LibraryEntry>, String>((ref, id) async =>
        await _query(ref, (db) => attachedStories(db, id)) ?? const [],);

/// The story whose end holds [storyId]'s dialogue (its file id), if any.
final storyHostProvider = FutureProvider.autoDispose
    .family<String?, String>((ref, storyId) async =>
        _query<String?>(ref, (db) => storyHostOf(db, storyId)),);
final storyPlaceProvider =FutureProvider.autoDispose
    .family<StoryPlace?, String>((ref, storyId) async =>
        _query<StoryPlace?>(ref, (db) => storyPlace(db, storyId)),);

final librarySearchProvider = FutureProvider.autoDispose.family<
    ({List<LibraryCollection> collections, List<LibraryEntry> entries}),
    String>((ref, query) async {
  final result = await _query(ref, (db) => searchLibrary(db, query));
  return result ??
      (collections: const <LibraryCollection>[], entries: const <LibraryEntry>[]);
});

/// Reading progress of every story the user opened, by `story:<id>`.
final readingProgressProvider =
    FutureProvider.autoDispose<Map<String, ReadingEntry>>((ref) async {
  try {
    final store = await ref.watch(userDataStoreProvider.future);
    return await store.progressByRef();
  } catch (_) {
    return const {};
  }
});

final materialsProvider =
    FutureProvider.autoDispose<List<UserMaterial>>((ref) async {
  final store = await ref.watch(userDataStoreProvider.future);
  return store.materials();
});

final materialProvider = FutureProvider.autoDispose
    .family<UserMaterial?, String>((ref, id) async {
  final store = await ref.watch(userDataStoreProvider.future);
  return store.material(id);
});

/// Call after the reading history changed.
void invalidateReading(WidgetRef ref) {
  ref
    ..invalidate(recentReadingProvider)
    ..invalidate(readingCountProvider)
    ..invalidate(readingPageProvider)
    ..invalidate(readingProgressProvider);
}
