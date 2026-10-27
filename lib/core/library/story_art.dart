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
      this.segment,
      this.titleGroup,
      this.missing = false,
      this.joined = false,});
  final String kind, image;
  final int at;
  final String? layout, titleGroup;
  final int? number, total, until;
  final int? segment;
  final bool missing;

  /// A scene shown in one item with the scene before it: the stage changed
  /// again on the same line, with nothing said in between.
  final bool joined;

  StoryArtShot copyWith(
          {int? at, int? number, int? total, int? until, int? segment,
          bool? joined,}) =>
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
          joined: joined ?? this.joined,);
}

/// Close-ups put up just before a CG on the same line (no CG taken down in
/// between) are laid over that CG: they move to just after it.
List<StoryArtEvent> _closeUpsAfterTheirCg(List<StoryArtEvent> events) {
  bool cgFollows(int i) {
    for (var j = i + 1;
        j < events.length && events[j].at == events[i].at;
        j++) {
      if (events[j].kind == 'cg_off') return false;
      if (events[j].kind == 'cg' && events[j].image != null) return true;
    }
    return false;
  }

  final result = <StoryArtEvent>[];
  final held = <StoryArtEvent>[];
  for (var i = 0; i < events.length; i++) {
    final e = events[i];
    if (e.kind == 'item' && cgFollows(i)) {
      held.add(e);
      continue;
    }
    result.add(e);
    if (e.kind == 'cg' && e.image != null) {
      result.addAll(held);
      held.clear();
    }
  }
  return result..addAll(held);
}

List<StoryArtShot> arrangeStoryArt(
    List<StoryArtEvent> events, bool? Function(String image, String kind) solid,
    {String? Function(String image)? titleGroup,}) {
  final shots = <StoryArtShot>[];
  final cgNumbers = <String, int>{};
  String? background, backgroundLayout, displayed;
  bool covered = false;
  int segmentStart = 0;
  var segment = 0;
  void scene(int at) {
    if (background == null ||
        background == displayed ||
        solid(background, 'background') == true) {
      return;
    }
    displayed = background;
    shots.add(StoryArtShot(
        kind: 'scene', image: background, layout: backgroundLayout, at: at,
        missing: solid(background, 'background') == null,),);
  }

  for (final e in _closeUpsAfterTheirCg(events)) {
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
          segment++;
        }
        final number =
            cgNumbers.putIfAbsent(e.image!, () => cgNumbers.length + 1);
        shots.add(StoryArtShot(
            kind: 'cg',
            image: e.image!,
            layout: e.layout,
            at: e.at,
            number: number,
            segment: segment,
            titleGroup: titleGroup?.call(e.image!),
            missing: solid(e.image!, 'cg') == null,),);
      case 'cg_off':
        if (covered) {
          for (var i = segmentStart; i < shots.length; i++) {
            final s = shots[i];
            if (s.kind == 'cg') shots[i] = s.copyWith(until: e.at);
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
              segment: covered ? segment : null,
              missing: solid(e.image!, 'item') == null,),);
        }
    }
  }
  final sceneTotal = shots.where((s) => s.kind == 'scene').length;
  var sceneNumber = 0;
  return [
    for (final (i, s) in shots.indexed)
      s.copyWith(
          number: s.kind == 'scene' ? ++sceneNumber : null,
          total: s.kind == 'scene'
              ? sceneTotal
              : s.kind == 'cg'
                  ? cgNumbers.length
                  : null,
          joined: s.kind == 'scene' &&
              i > 0 &&
              shots[i - 1].kind == 'scene' &&
              shots[i - 1].at == s.at,),
  ];
}
