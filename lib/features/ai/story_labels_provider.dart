import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/agent/agent_provider.dart';
import '../../core/gamedata/story_catalog.dart';

/// R15: catalog entries (collection, chapter, order) of the story ids cited
/// in an answer, keyed by the newline-joined sorted ids. Empty when the
/// installed knowledge base has no story catalog (the UI then derives names
/// from the path) or the store is unavailable.
final storyCatalogEntriesProvider =
    FutureProvider.family<Map<String, StoryCatalogEntry>, String>(
        (ref, key) async {
  final ids = [
    for (final id in key.split('\n'))
      if (id.trim().isNotEmpty) id.trim(),
  ];
  if (ids.isEmpty) return const {};
  try {
    return await ref.watch(sharedGameDataStoreProvider).storyCatalogEntries(ids);
  } catch (_) {
    return const {};
  }
});

/// R14: readable labels (`巴别塔 BB-7 行动前《…》`) of the same ids.
final storyLabelsProvider =
    FutureProvider.family<Map<String, String>, String>((ref, key) async {
  final entries = await ref.watch(storyCatalogEntriesProvider(key).future);
  return {
    for (final entry in entries.entries) entry.key: entry.value.label,
  };
});

/// Family key for [storyLabelsProvider] / [storyCatalogEntriesProvider].
String storyLabelsKey(Iterable<String> storyIds) =>
    (storyIds.toSet().toList()..sort()).join('\n');
