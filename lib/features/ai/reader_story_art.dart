import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/gamedata/game.dart';
import '../../core/gamedata/story_art_pack.dart';
import '../../core/gamedata/story_art_pack_provider.dart';
import '../../core/gamedata/story_coverage_models.dart';
import '../../core/library/story_art.dart';

typedef ReaderArtKey = ({
  String storyId,
  List<StoryLineEntry> lines,
  Map<int, ({String storyId, int lineIndex})> sources,
});

class ReaderStoryArt {
  const ReaderStoryArt(this.shots, this.info, this.titles);

  final List<StoryArtShot> shots;
  final Map<(String, String), StoryArtInfo> info;
  final Map<String, StoryArtTitle?> titles;
}

/// Source boundaries reset stage state, but numbering spans the reader.
final readerStoryArtProvider = FutureProvider.autoDispose
    .family<ReaderStoryArt?, ReaderArtKey>((ref, key) async {
  if (gameOfId(key.storyId) != Game.arknights || key.lines.isEmpty) return null;
  final pack = await ref.watch(storyArtPackProvider.future);
  if (!await pack.installed) return null;

  final groups = <({String id, int start, int end, List<int> sourceLines})>[];
  for (var i = 0; i < key.lines.length;) {
    final line = key.lines[i];
    if (line.kind == 'divider') {
      i++;
      continue;
    }
    final source = key.sources[line.lineIndex];
    final id = source?.storyId ?? key.storyId;
    final start = i;
    final sourceLines = <int>[];
    while (i < key.lines.length) {
      final current = key.lines[i];
      if (current.kind == 'divider') break;
      final origin = key.sources[current.lineIndex];
      if ((origin?.storyId ?? key.storyId) != id) break;
      sourceLines.add(origin?.lineIndex ?? current.lineIndex);
      i++;
    }
    groups.add((id: id, start: start, end: i, sourceLines: sourceLines));
  }
  final eventsById = <String, List<StoryArtEvent>>{};
  for (final id in groups.map((g) => g.id).toSet()) {
    eventsById[id] = await ref.watch(storyArtEventsProvider(id).future);
  }
  final events = eventsById.values.expand((e) => e).toList();
  if (events.isEmpty) return null;
  final info = await pack.artInfo([
    for (final event in events)
      if (event.image != null) (event.image!, event.kind),
  ]);
  final titles = <String, StoryArtTitle?>{};
  for (final id in events
      .where((e) => e.kind == 'cg' && e.image != null)
      .map((e) => e.image!)
      .toSet()) {
    titles[id] = await pack.artTitle(id);
  }

  final shots = <StoryArtShot>[];
  var segmentOffset = 0, sceneOffset = 0;
  for (final group in groups) {
    final mapped = <StoryArtEvent>[];
    for (final e in eventsById[group.id]!) {
      final offset = group.sourceLines.indexWhere((line) => line >= e.at);
      final at = offset < 0 ? group.end : group.start + offset;
      mapped.add(
        StoryArtEvent(
          storyId: e.storyId,
          seq: e.seq,
          at: at,
          kind: e.kind,
          image: e.image,
          layout: e.layout,
          x: e.x,
          y: e.y,
          scale: e.scale,
          alpha: e.alpha,
          layer: e.layer,
        ),
      );
    }
    final arranged = arrangeStoryArt(
      mapped,
      (image, kind) => info[(image, kind)]?.solid,
      titleGroup: (image) => titles[image]?.groupKey,
    );
    shots.addAll(
      arranged.map(
        (s) => s.copyWith(
          number: s.kind == 'scene' ? s.number! + sceneOffset : null,
          segment: s.segment == null ? null : s.segment! + segmentOffset,
          until: s.kind == 'cg' ? s.until ?? group.end : null,
        ),
      ),
    );
    sceneOffset += arranged
        .where((s) => s.kind == 'scene')
        .map((s) => s.number!)
        .fold(0, (a, b) => a > b ? a : b);
    segmentOffset += mapped.where((event) => event.kind == 'cg').length;
  }
  if (shots.isEmpty) return null;
  final sceneCount = sceneOffset;
  final cgNumbers = <String, int>{};
  for (final s in shots.where((s) => s.kind == 'cg')) {
    cgNumbers.putIfAbsent(s.image, () => cgNumbers.length + 1);
  }

  return ReaderStoryArt(
    [
      for (final s in shots)
        s.copyWith(
          number: s.kind == 'scene' ? s.number : cgNumbers[s.image],
          total: s.kind == 'scene'
              ? sceneCount
              : s.kind == 'cg'
                  ? cgNumbers.length
                  : null,
        ),
    ],
    info,
    titles,
  );
});
