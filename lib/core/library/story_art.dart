import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_common/sqlite_api.dart';

import '../agent/agent_provider.dart' show gameStoreProvider;
import '../gamedata/game.dart';
import '../gamedata/gamedata_provider.dart';

class StoryArtEvent {
  const StoryArtEvent(
      {required this.storyId,
      required this.seq,
      required this.at,
      required this.kind,
      this.image,
      this.layout,});
  final String storyId, kind;
  final int seq, at;
  final String? image, layout;
}

Future<List<StoryArtEvent>> readStoryArtEvents(
    DatabaseExecutor db, Iterable<String> storyIds,) async {
  final tables = await db.rawQuery(
      "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'story_art_events'",);
  if (tables.isEmpty) return [];
  final result = <StoryArtEvent>[];
  for (final id in storyIds.toSet()) {
    final rows = await db.query('story_art_events',
        where: 'story_id = ?', whereArgs: [id], orderBy: 'seq',);
    result.addAll(rows.map((row) => StoryArtEvent(
        storyId: id,
        seq: row['seq'] as int,
        at: row['at_line'] as int,
        kind: row['kind'] as String,
        image: row['image'] as String?,
        layout: row['layout'] as String?,),),);
  }
  return result;
}

/// Groups events by their original story and line, preserving sequence order.
Future<Map<({String storyId, int lineIndex}), List<StoryArtEvent>>>
    readStoryArtEventsForSources(DatabaseExecutor db,
        Iterable<({String storyId, int lineIndex})> sources,) async {
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

class StoryArtShot {
  const StoryArtShot(
      {required this.kind,
      required this.image,
      required this.at,
      this.layout,
      this.number,
      this.total,
      this.until,
      this.titleGroup,
      this.missing = false,});
  final String kind, image;
  final int at;
  final String? layout, titleGroup;
  final int? number, total, until;
  final bool missing;
}

List<StoryArtShot> arrangeStoryArt(
    List<StoryArtEvent> events, bool? Function(String image, String kind) solid,
    {String? Function(String image)? titleGroup,}) {
  final shots = <StoryArtShot>[];
  final cgNumbers = <String, int>{};
  String? background, backgroundLayout, displayed;
  bool covered = false;
  int segmentStart = 0;
  void scene(int at) {
    if (background == null ||
        background == displayed ||
        solid(background, 'background') != false) {
      return;
    }
    displayed = background;
    shots.add(StoryArtShot(
        kind: 'scene', image: background, layout: backgroundLayout, at: at,),);
  }

  for (final e in events) {
    switch (e.kind) {
      case 'background':
        background = e.image;
        backgroundLayout = e.layout;
        if (!covered) scene(e.at);
      case 'cg':
        if (e.image == null) break;
        if (!covered) {
          covered = true;
          segmentStart = shots.length;
        }
        final number =
            cgNumbers.putIfAbsent(e.image!, () => cgNumbers.length + 1);
        shots.add(StoryArtShot(
            kind: 'cg',
            image: e.image!,
            layout: e.layout,
            at: e.at,
            number: number,
            titleGroup: titleGroup?.call(e.image!),
            missing: solid(e.image!, 'cg') == null,),);
      case 'cg_off':
        if (covered) {
          for (var i = segmentStart; i < shots.length; i++) {
            final s = shots[i];
            if (s.kind == 'cg') {
              shots[i] = StoryArtShot(
                  kind: s.kind,
                  image: s.image,
                  layout: s.layout,
                  at: s.at,
                  number: s.number,
                  until: e.at,
                  titleGroup: s.titleGroup,
                  missing: s.missing,);
            }
          }
          covered = false;
          scene(e.at);
        }
      case 'item':
        // A flat tint laid over the stage is not a picture to look at.
        if (e.image != null && solid(e.image!, 'item') != true) {
          shots.add(StoryArtShot(
              kind: 'item',
              image: e.image!,
              layout: e.layout,
              at: e.at,
              missing: solid(e.image!, 'item') == null,),);
        }
    }
  }
  final sceneTotal = shots.where((s) => s.kind == 'scene').length;
  var sceneNumber = 0;
  return [
    for (final s in shots)
      StoryArtShot(
          kind: s.kind,
          image: s.image,
          layout: s.layout,
          at: s.at,
          number: s.kind == 'scene' ? ++sceneNumber : s.number,
          total: s.kind == 'scene'
              ? sceneTotal
              : s.kind == 'cg'
                  ? cgNumbers.length
                  : null,
          until: s.until,
          titleGroup: s.titleGroup,
          missing: s.missing,),
  ];
}
