import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_common/sqlite_api.dart' show DatabaseExecutor;

import '../agent/agent_provider.dart' show gameStoreProvider;
import '../gamedata/game.dart';
import '../llm/llm_provider.dart' show embeddingClientProvider;
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

/// Runs [action] on a knowledge base: [game]'s, else the one [id] belongs to
/// (`game.dart`), else the default one. Null when it is not installed or the
/// query fails (the pages then show their empty state).
Future<R?> _query<R>(
  Ref ref,
  Future<R> Function(DatabaseExecutor db) action, {
  String? id,
  Game? game,
}) async {
  final which = game ?? (id == null ? Game.arknights : gameOfId(id));
  try {
    return await ref.watch(gameStoreProvider(which)).withDatabase(action);
  } catch (_) {
    return null;
  }
}

/// Whether [game]'s library can be shown.
final gameLibraryStatusProvider =
    FutureProvider.autoDispose.family<LibraryStatus, Game>((ref, game) async {
  final ready = await _query(ref, (db) => hasEntryLayer(db), game: game);
  if (ready == null) return LibraryStatus.notInstalled;
  return ready ? LibraryStatus.ready : LibraryStatus.oldSchema;
});

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
    FutureProvider.autoDispose.family<List<ShelfSummary>, Game>(
  (ref, game) async =>
      await _query(ref, (db) => shelfSummaries(db), game: game) ?? const [],
);

final codexTypesProvider =
    FutureProvider.autoDispose.family<List<({String type, int count})>, Game>(
  (ref, game) async =>
      await _query(ref, (db) => codexTypes(db), game: game) ?? const [],
);

final collectionsOfKindProvider =
    FutureProvider.autoDispose.family<List<LibraryCollection>, String>(
  (ref, kind) async =>
      await _query(ref, (db) => collectionsOfKind(db, kind), id: kind) ??
      const [],
);

final collectionProvider =
    FutureProvider.autoDispose.family<LibraryCollection?, String>(
  (ref, id) async =>
      _query<LibraryCollection?>(ref, (db) => collectionById(db, id), id: id),
);

final collectionTypesProvider =
    FutureProvider.autoDispose.family<List<({String type, int count})>, String>(
  (ref, id) async =>
      await _query(ref, (db) => collectionTypes(db, id), id: id) ?? const [],
);

final collectionIntroProvider =
    FutureProvider.autoDispose.family<String?, String>(
  (ref, id) async =>
      _query<String?>(ref, (db) => collectionIntro(db, id), id: id),
);

final collectionInlineProvider =
    FutureProvider.autoDispose.family<List<LibraryEntry>, String>(
  (ref, id) async =>
      await _query(ref, (db) => inlineEntries(db, id), id: id) ?? const [],
);

final entryPartsProvider =
    FutureProvider.autoDispose.family<List<LibraryEntry>, String>(
  (ref, id) async =>
      await _query(ref, (db) => entryParts(db, id), id: id) ?? const [],
);

final collectionStoriesProvider =
    FutureProvider.autoDispose.family<List<LibraryEntry>, String>(
  (ref, id) async =>
      await _query(ref, (db) => storiesOf(db, id), id: id) ?? const [],
);

/// Which entries a list shows: one type, in a collection or (null) in the
/// codex, filtered by [query].
typedef EntryListKey = ({
  String type,
  String? collectionId,
  String query,
  String groups,
  Game game,
});

/// [EntryListKey.groups] for a set of groups (a null element is "no group"):
/// a plain string, so the key compares by value.
String groupsKey(List<String?>? groups) =>
    groups == null ? '' : groups.map((g) => g ?? '\u0000').join('\u0001');

List<String?>? _groupsOf(String key) => key.isEmpty
    ? null
    : [for (final g in key.split('\u0001')) g == '\u0000' ? null : g];

final entriesOfTypeProvider =
    FutureProvider.autoDispose.family<List<LibraryEntry>, EntryListKey>(
  (ref, key) async =>
      await _query(
        ref,
        (db) => entriesOfType(
          db,
          key.type,
          collectionId: key.collectionId,
          query: key.query,
          groups: _groupsOf(key.groups),
        ),
        game: key.game,
      ) ??
      const [],
);

/// The groups of one type's entries, for the menu above a long list.
typedef EntryGroupsKey = ({String type, String? collectionId, Game game});

final entryGroupsProvider = FutureProvider.autoDispose
    .family<List<({String? group, int count})>, EntryGroupsKey>(
  (ref, key) async =>
      await _query(
        ref,
        (db) => entryGroups(db, key.type, collectionId: key.collectionId),
        game: key.game,
      ) ??
      const [],
);

final entryProvider = FutureProvider.autoDispose.family<LibraryEntry?, String>(
  (ref, id) async =>
      _query<LibraryEntry?>(ref, (db) => entryById(db, id), id: id),
);

final entryTextsProvider =
    FutureProvider.autoDispose.family<List<EntryTextBlock>, LibraryEntry>(
  (ref, entry) async =>
      await _query(ref, (db) => entryTexts(db, entry), id: entry.id) ??
      const [],
);

final entryBindingsProvider =
    FutureProvider.autoDispose.family<List<EntryBinding>, String>(
  (ref, id) async =>
      await _query(ref, (db) => entryBindings(db, id), id: id) ?? const [],
);

final operatorMemoriesProvider =
    FutureProvider.autoDispose.family<List<LibraryCollection>, String>(
  (ref, id) async =>
      await _query(ref, (db) => collectionsOwnedBy(db, id), id: id) ?? const [],
);

final operatorOwnedProvider =
    FutureProvider.autoDispose.family<List<LibraryEntry>, String>(
  (ref, id) async =>
      await _query(ref, (db) => entriesOwnedBy(db, id), id: id) ?? const [],
);

/// The alternate versions of an operator (and its original).
final samePersonProvider =
    FutureProvider.autoDispose.family<List<LibraryEntry>, String>(
  (ref, id) async =>
      await _query(ref, (db) => samePersonOf(db, id), id: id) ?? const [],
);

/// The in-battle dialogue attached to a stage or story entry, in order.
final attachedStoriesProvider =
    FutureProvider.autoDispose.family<List<LibraryEntry>, String>(
  (ref, id) async =>
      await _query(ref, (db) => attachedStories(db, id), id: id) ?? const [],
);

/// The story whose end holds [storyId]'s dialogue (its file id), if any.
final storyHostProvider = FutureProvider.autoDispose.family<String?, String>(
  (ref, storyId) async =>
      _query<String?>(ref, (db) => storyHostOf(db, storyId), id: storyId),
);
final storyPlaceProvider =
    FutureProvider.autoDispose.family<StoryPlace?, String>(
  (ref, storyId) async =>
      _query<StoryPlace?>(ref, (db) => storyPlace(db, storyId), id: storyId),
);

/// One search: the query, where it looks, whether the texts are searched
/// even when names match.
typedef LibrarySearchKey = ({String query, LibraryScope scope, bool text});

final librarySearchProvider = FutureProvider.autoDispose
    .family<LibrarySearchResult, LibrarySearchKey>((ref, key) async {
  // A page's scope is in one game; the whole library is every game's.
  final games =
      key.scope == everywhere ? Game.values : [gameOfScope(key.scope)];
  final results = [
    for (final game in games)
      await _query(
        ref,
        (db) =>
            searchLibraryIn(db, key.query, scope: key.scope, text: key.text),
        game: game,
      ),
  ].whereType<LibrarySearchResult>().toList();
  return results.isEmpty
      ? const LibrarySearchResult()
      : results.reduce((a, b) => a.merge(b));
});

/// Why the semantic search cannot run.
enum SemanticSearchProblem { noService, noVectors, otherModel }

class SemanticSearchUnavailable implements Exception {
  const SemanticSearchUnavailable(this.problem);
  final SemanticSearchProblem problem;
}

/// Stories close in meaning to the query (the story vectors): the query is
/// sent to the embedding service, so the page runs it only on request.
/// Fails with [SemanticSearchUnavailable] when it cannot run.
final librarySemanticProvider = FutureProvider.autoDispose
    .family<List<LibraryTextHit>, ({String query, LibraryScope scope})>(
        (ref, key) async {
  final client = ref.watch(embeddingClientProvider);
  if (client == null) {
    throw const SemanticSearchUnavailable(SemanticSearchProblem.noService);
  }
  final store = ref.watch(gameStoreProvider(gameOfScope(key.scope)));
  final info = await store.storyVectorInfo;
  if (info == null) {
    throw const SemanticSearchUnavailable(SemanticSearchProblem.noVectors);
  }
  if (info.model != client.model || info.dims != client.dimensions) {
    throw const SemanticSearchUnavailable(SemanticSearchProblem.otherModel);
  }
  final vector = (await client.embed([key.query])).single;
  // A page's scope keeps a part of the hits: look further down the list.
  final hits = await store.searchStoryChunksByVector(
    vector,
    topK: key.scope == everywhere ? 60 : 400,
  );
  return await store.withDatabase(
        (db) => storyChunkEntries(
          db,
          [
            for (final h in hits)
              (storyId: h.storyId, lineStart: h.lineStart, lineEnd: h.lineEnd),
          ],
          scope: key.scope,
        ),
      ) ??
      const [];
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

final materialProvider =
    FutureProvider.autoDispose.family<UserMaterial?, String>((ref, id) async {
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
