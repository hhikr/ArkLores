import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/agent/agent_provider.dart';
import '../../core/gamedata/story_catalog.dart';
import '../../core/gamedata/story_coverage_models.dart' show StoryLineEntry;

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

/// R17: the original lines of one cited range, read from the knowledge base
/// when the reader opens the citation (key: [citedLinesKey]). Empty when
/// the store is unavailable.
final citedLinesProvider =
    FutureProvider.family<List<StoryLineEntry>, String>((ref, key) async {
  final parts = key.split('\n');
  if (parts.length != 3) return const [];
  final start = int.tryParse(parts[1]) ?? 0;
  final end = int.tryParse(parts[2]) ?? start;
  try {
    final page = await ref.watch(sharedGameDataStoreProvider).readStoryLines(
          storyId: parts[0],
          startLine: start,
          endLine: end,
          maxLines: (end - start + 1).clamp(1, 500),
        );
    return page.lines;
  } catch (_) {
    return const [];
  }
});

String citedLinesKey(String storyId, int start, int end) =>
    '$storyId\n$start\n$end';

/// R17: a cited non-story record (`record:<id>`): title and text.
final citedRecordProvider =
    FutureProvider.family<({String title, String content})?, String>(
        (ref, id) async {
  // Record ids are hex / word characters (see the citation pattern), so the
  // literal is safe to inline.
  if (!RegExp(r'^[\w\-]+$').hasMatch(id)) return null;
  try {
    final result = await ref.watch(sharedGameDataStoreProvider).readOnlySql(
          'SELECT title, category, subtype, entity_name, content '
          "FROM normalized_records WHERE id = '$id'",
          maxRows: 1,
        );
    if (result.rows.isEmpty) return null;
    final row = {
      for (final (i, c) in result.columns.indexed) c: result.rows.first[i],
    };
    final title = [
      row['entity_name'],
      row['title'],
    ].where((v) => v != null && '$v'.trim().isNotEmpty).toSet().join(' · ');
    return (title: title, content: '${row['content'] ?? ''}');
  } catch (_) {
    return null;
  }
});
