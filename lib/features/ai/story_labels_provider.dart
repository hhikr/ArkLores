import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/agent/agent_provider.dart';
import '../../core/gamedata/story_catalog.dart';
import '../../core/gamedata/story_coverage_models.dart' show StoryLineEntry;
import '../../core/library/library_provider.dart'
    show attachedStoriesProvider, storyHostProvider;

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
    return await ref.watch(loreRetrievalProvider).storyCatalogEntries(ids);
  } catch (_) {
    return const {};
  }
});

/// R17d: the catalog entry of one story, cached per id, so an evidence chain
/// keeps its label while an answer streams in and more stories are cited.
/// Null when the knowledge base has no catalog entry for it.
final storyCatalogEntryProvider =
    FutureProvider.family<StoryCatalogEntry?, String>((ref, storyId) async {
  try {
    final entries =
        await ref.watch(loreRetrievalProvider).storyCatalogEntries([storyId]);
    return entries[storyId];
  } catch (_) {
    return null;
  }
});

/// The current readable label of one story. The reading history stores the
/// label from the day a story was opened, which can be an id from an older
/// knowledge base; lists show this one and keep the stored one as fallback.
/// Null when the knowledge base does not know the story (then the stored
/// title is the better name: a path-derived one is only a last resort).
final storyLabelProvider =
    FutureProvider.family<String?, String>((ref, storyId) async {
  final entry = await ref.watch(storyCatalogEntryProvider(storyId).future);
  return entry?.label;
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

/// R17b: every line of one story, for the reader opened from a citation.
/// Empty when the story or the store is unavailable.
final storyFullLinesProvider =
    FutureProvider.family<List<StoryLineEntry>, String>((ref, storyId) async {
  final store = storeOfId(ref, storyId);
  final lines = <StoryLineEntry>[];
  String? next;
  try {
    do {
      final page = await store.readStoryLines(
        storyId: storyId,
        maxLines: 500,
        pageToken: next,
      );
      lines.addAll(page.lines);
      next = page.nextPageToken;
    } while (next != null);
  } catch (_) {
    return const [];
  }
  return lines;
});

/// A story as the reader shows it: its own lines, then the in-battle dialogue
/// attached to it (each part under a `divider` line), and where the story the
/// reader was asked for begins in that text.
class StoryReading {
  const StoryReading({
    required this.hostId,
    required this.lines,
    this.offset = 0,
  });

  /// The story the text is the text of: the asked-for story, or the story its
  /// dialogue is attached to.
  final String hostId;
  final List<StoryLineEntry> lines;

  /// Added to a line number of the asked-for story to get its place in
  /// [lines] (not zero for attached dialogue opened by its own id).
  final int offset;
}

/// The text the reader shows for a story id (see [StoryReading]).
final storyReadingProvider =
    FutureProvider.family<StoryReading, String>((ref, storyId) async {
  String? host;
  try {
    host = await ref.watch(storyHostProvider(storyId).future);
  } catch (_) {}
  var hostId = host ?? storyId;
  var own = await ref.watch(storyFullLinesProvider(hostId).future);
  if (own.isEmpty && host != null) {
    host = null;
    hostId = storyId;
    own = await ref.watch(storyFullLinesProvider(hostId).future);
  }
  var children = const <String>[];
  try {
    children = [
      for (final c in await ref.watch(attachedStoriesProvider('story:$hostId').future))
        if (c.rawId != null) c.rawId!,
    ];
  } catch (_) {}
  if (own.isEmpty || children.isEmpty) {
    return StoryReading(hostId: hostId, lines: own);
  }
  final lines = [...own];
  var cursor = own.last.lineIndex + 1;
  var offset = 0;
  final parts = <(String, List<StoryLineEntry>)>[
    for (final id in children)
      (id, await ref.watch(storyFullLinesProvider(id).future)),
  ]..removeWhere((p) => p.$2.isEmpty);
  for (final (n, part) in parts.indexed) {
    lines.add(
      StoryLineEntry(
        lineIndex: cursor,
        content: '${n + 1}/${parts.length}',
        kind: 'divider',
      ),
    );
    if (part.$1 == storyId) offset = cursor + 1;
    for (final line in part.$2) {
      lines.add(
        StoryLineEntry(
          lineIndex: cursor + 1 + line.lineIndex,
          speaker: line.speaker,
          content: line.content,
          kind: line.kind,
          shownIndex: line.lineIndex,
        ),
      );
    }
    cursor += 1 + part.$2.last.lineIndex + 1;
  }
  return StoryReading(hostId: hostId, lines: lines, offset: offset);
});
/// R17: a cited non-story record (`record:<id>`): title and text.
final citedRecordProvider =
    FutureProvider.family<({String title, String content})?, String>(
        (ref, id) async {
  // Record ids are hex / word characters, Endfield's under ef/ (see the
  // citation pattern), so the literal is safe to inline.
  if (!RegExp(r'^[\w\-/]+$').hasMatch(id)) return null;
  try {
    final result = await storeOfId(ref, id).readOnlySql(
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
