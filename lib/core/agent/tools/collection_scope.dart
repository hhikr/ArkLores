import '../../gamedata/game_retrieval.dart';

/// R16: the story ids of a catalog collection named as a search scope when
/// the collection is not a scope of its own — main chapters (`main_9`, all
/// under `obt:main`) and operator records. The overview and OUTLINE show
/// these ids, so the planner uses them as scopes; they used to match
/// nothing ("No story line matches … in activity:main_9").
///
/// Null when [raw] is empty, already a scope key (`obt:main`,
/// `activity:x`, `activities/x`), an activity id (its own scope), or not
/// a collection.
Future<Set<String>?> collectionScopeStories(
  GameDataRetrieval store,
  String? raw,
) async {
  var value = (raw ?? '').trim();
  if (value.startsWith('@')) value = value.substring(1).trim();
  if (value.isEmpty || value.contains(':') || value.contains('/')) return null;
  final collection = await store.storyCollection(value);
  if (collection == null || collection.collectionId != value) return null;
  final ids = {for (final e in collection.entries) e.storyId};
  if (ids.isEmpty || ids.every((id) => id.startsWith('activities/$value/'))) {
    return null;
  }
  return ids;
}
