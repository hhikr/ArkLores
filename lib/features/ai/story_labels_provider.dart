import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/agent/agent_provider.dart';

/// R14: readable labels (`巴别塔 BB-7 行动前《…》`) of the story ids cited in an
/// answer, keyed by the newline-joined sorted ids. Empty when the installed
/// knowledge base has no story catalog (the UI then derives names from the
/// path) or the store is unavailable.
final storyLabelsProvider =
    FutureProvider.family<Map<String, String>, String>((ref, key) async {
  final ids = [
    for (final id in key.split('\n'))
      if (id.trim().isNotEmpty) id.trim(),
  ];
  if (ids.isEmpty) return const {};
  try {
    final entries =
        await ref.watch(sharedGameDataStoreProvider).storyCatalogEntries(ids);
    return {
      for (final entry in entries.entries) entry.key: entry.value.label,
    };
  } catch (_) {
    return const {};
  }
});

/// Family key for [storyLabelsProvider].
String storyLabelsKey(Iterable<String> storyIds) =>
    (storyIds.toSet().toList()..sort()).join('\n');
