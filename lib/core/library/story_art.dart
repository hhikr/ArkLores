import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_common/sqlite_api.dart';

import '../agent/agent_provider.dart' show gameStoreProvider;
import '../gamedata/game.dart';
import '../gamedata/gamedata_provider.dart';

class StoryArtEvent {
  const StoryArtEvent({
    required this.storyId,
    required this.seq,
    required this.at,
    required this.kind,
    this.image,
    this.layout,
    this.x,
    this.y,
    this.scale,
    this.alpha,
    this.layer,
  });
  final String storyId, kind;
  final int seq, at;
  final String? image, layout;
  final double? x, y, scale, alpha;
  final int? layer;
}

Future<List<StoryArtEvent>> readStoryArtEvents(
  DatabaseExecutor db,
  Iterable<String> storyIds,
) async {
  final tables = await db.rawQuery(
    "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'story_art_events'",
  );
  if (tables.isEmpty) return [];
  final result = <StoryArtEvent>[];
  for (final id in storyIds.toSet()) {
    final rows = await db.query(
      'story_art_events',
      where: 'story_id = ?',
      whereArgs: [id],
      orderBy: 'seq',
    );
    result.addAll(
      rows.map(
        (row) => StoryArtEvent(
          storyId: id,
          seq: row['seq'] as int,
          at: row['at_line'] as int,
          kind: row['kind'] as String,
          image: row['image'] as String?,
          layout: row['layout'] as String?,
          x: (row['x'] as num?)?.toDouble(),
          y: (row['y'] as num?)?.toDouble(),
          scale: (row['scale'] as num?)?.toDouble(),
          alpha: (row['alpha'] as num?)?.toDouble(),
          layer: row['layer'] as int?,
        ),
      ),
    );
  }
  return result;
}

/// Groups events by their original story and line, preserving sequence order.
Future<Map<({String storyId, int lineIndex}), List<StoryArtEvent>>>
    readStoryArtEventsForSources(
  DatabaseExecutor db,
  Iterable<({String storyId, int lineIndex})> sources,
) async {
  final keys = sources.toSet();
  final events = await readStoryArtEvents(db, keys.map((key) => key.storyId));
  final result = <({String storyId, int lineIndex}), List<StoryArtEvent>>{};
  for (final event in events) {
    final key = (storyId: event.storyId, lineIndex: event.at);
    if (keys.contains(key)) (result[key] ??= []).add(event);
  }
  return result;
}

final storyArtEventsProvider =
    FutureProvider.family<List<StoryArtEvent>, String>((ref, id) async {
  try {
    await ref.watch(gameDataInstallStatusProvider.future);
    return await ref
            .watch(gameStoreProvider(Game.arknights))
            .withDatabase((db) => readStoryArtEvents(db, [id])) ??
        [];
  } catch (_) {
    return [];
  }
});

class StoryArtLayer {
  const StoryArtLayer({
    required this.image,
    this.x = 0,
    this.y = 0,
    this.scale = 1,
    this.alpha = 1,
    this.layer = 0,
  });
  final String image;
  final double x, y, scale, alpha;
  final int layer;
}

class StoryArtShot {
  const StoryArtShot({
    required this.kind,
    required this.image,
    required this.at,
    this.layout,
    this.number,
    this.total,
    this.until,
    this.segment,
    this.titleGroup,
    this.missing = false,
    this.joined = false,
    this.layers = const [],
  });
  final String kind, image;
  final int at;
  final String? layout, titleGroup;
  final int? number, total, until;
  final int? segment;
  final bool missing;
  final List<StoryArtLayer> layers;

  /// A scene shown in one item with the scene before it: the stage changed
  /// again on the same line, with nothing said in between.
  final bool joined;

  StoryArtShot copyWith({
    int? at,
    int? number,
    int? total,
    int? until,
    int? segment,
    bool? joined,
  }) =>
      StoryArtShot(
        kind: kind,
        image: image,
        at: at ?? this.at,
        layout: layout,
        number: number ?? this.number,
        total: total ?? this.total,
        until: until ?? this.until,
        segment: segment ?? this.segment,
        titleGroup: titleGroup,
        missing: missing,
        joined: joined ?? this.joined,
        layers: layers,
      );
}

/// Snapshots are emitted after every command at a dialogue boundary is applied.
List<StoryArtShot> arrangeStoryArt(
  List<StoryArtEvent> events,
  bool? Function(String image, String kind) solid, {
  String? Function(String image)? titleGroup,
}) {
  final shots = <StoryArtShot>[];
  final cgNumbers = <String, int>{};
  final layers = <String, StoryArtLayer>{};
  final order = <String, int>{};
  var serial = 0, sceneNumber = 0, segment = 0, segmentStart = 0;
  String? background, backgroundLayout, displayed, displayedLayout, cg;
  List<StoryArtLayer> snapshot() {
    final sorted = layers.values.toList()
      ..sort((a, b) {
        final depth = a.layer.compareTo(b.layer);
        return depth != 0 ? depth : order[a.image]!.compareTo(order[b.image]!);
      });
    return List.unmodifiable(sorted);
  }

  void scene(int at, {bool changed = false}) {
    final newScene = background != null &&
        background != displayed &&
        solid(background, 'background') != true;
    if (newScene) {
      displayed = background;
      displayedLayout = backgroundLayout;
      sceneNumber++;
    }
    if (!newScene && !changed) return;
    // The last layers went: show the scene bare again, unless the stage
    // under them is flat or cleared (the story ending says the same).
    if (!newScene &&
        layers.isEmpty &&
        (background == null || background != displayed)) {
      return;
    }
    // A flat background still forms the stage under visible layers.
    final image = changed ? background ?? '' : displayed!;
    shots.add(
      StoryArtShot(
        kind: 'scene',
        image: image,
        layout: changed ? backgroundLayout : displayedLayout,
        at: at,
        number: sceneNumber,
        layers: snapshot(),
        missing: solid(image, 'background') == null,
      ),
    );
  }

  for (var i = 0; i < events.length;) {
    final at = events[i].at;
    var changed = false, cgChanged = false, backgroundChanged = false;
    final wasCovered = cg != null;
    while (i < events.length && events[i].at == at) {
      final e = events[i++];
      switch (e.kind) {
        case 'background':
          backgroundChanged =
              background != e.image || backgroundLayout != e.layout;
          background = e.image;
          backgroundLayout = e.layout;
        case 'cg':
          if (e.image != null) {
            cg = e.image;
            cgChanged = true;
          }
        case 'cg_off':
          cg = null;
        case 'item':
          if (e.image == null) break;
          if ((e.alpha ?? 1) <= .01) {
            changed = layers.remove(e.image) != null || changed;
            order.remove(e.image);
          } else {
            order.putIfAbsent(e.image!, () => serial++);
            layers[e.image!] = StoryArtLayer(
              image: e.image!,
              x: e.x ?? 0,
              y: e.y ?? 0,
              scale: e.scale ?? 1,
              alpha: e.alpha ?? 1,
              layer: e.layer ?? 0,
            );
            changed = true;
          }
        case 'item_off':
          if (e.image == null) {
            changed = layers.isNotEmpty || changed;
            layers.clear();
            order.clear();
          } else {
            changed = layers.remove(e.image) != null || changed;
            order.remove(e.image);
          }
      }
    }
    if (wasCovered && cg == null) {
      for (var j = segmentStart; j < shots.length; j++) {
        if (shots[j].kind == 'cg') shots[j] = shots[j].copyWith(until: at);
      }
    }
    if (cg != null) {
      if (!wasCovered) {
        segment++;
        segmentStart = shots.length;
      }
      if (cgChanged || changed) {
        final number = cgNumbers.putIfAbsent(cg, () => cgNumbers.length + 1);
        shots.add(
          StoryArtShot(
            kind: 'cg',
            image: cg,
            at: at,
            number: number,
            segment: segment,
            titleGroup: titleGroup?.call(cg),
            layers: snapshot(),
            missing: solid(cg, 'cg') == null,
          ),
        );
      }
    } else {
      scene(at, changed: changed || (backgroundChanged && layers.isNotEmpty));
    }
  }
  return [
    for (final shot in shots)
      shot.copyWith(
        total: shot.kind == 'scene' ? sceneNumber : cgNumbers.length,
      ),
  ];
}
