import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../agent/agent_provider.dart' show gameStoreProvider;
import '../gamedata/game.dart';
import '../gamedata/gamedata_provider.dart';
import '../gamedata/story_art_pack_provider.dart';
import 'library_provider.dart';
import 'library_queries.dart';
import 'story_art.dart';

class CollectionArtShot {
  const CollectionArtShot(this.storyId, this.storyTitle, this.shot);
  final String storyId, storyTitle;
  final StoryArtShot shot;
}

/// A story as the story list names it: code, name and the part it is
/// (`<code> <name> / <part>`), so the stories of one stage stay apart.
String collectionStoryLabel(LibraryEntry story) => [
      story.code ?? '',
      story.name,
      if (story.group != null && !story.name.contains(story.group!))
        '/ ${story.group}',
    ].where((s) => s.isNotEmpty).join(' ');

/// One picture per base and set of layers: the same layers moved, scaled or
/// faded during a scene look alike in a gallery, so the first stays.
List<CollectionArtShot> groupCollectionArt(
  List<LibraryEntry> stories,
  List<StoryArtEvent> events,
  bool? Function(String, String) solid,
) {
  final byStory = <String, List<StoryArtEvent>>{};
  for (final event in events) {
    (byStory[event.storyId] ??= []).add(event);
  }
  final seen = <String>{};
  return [
    for (final story in stories)
      for (final shot in arrangeStoryArt(byStory[story.rawId] ?? [], solid))
        if (seen.add(
          jsonEncode([
            shot.kind,
            shot.image,
            shot.layout,
            for (final layer in shot.layers) layer.image,
          ]),
        ))
          CollectionArtShot(story.rawId!, collectionStoryLabel(story), shot),
  ];
}

final collectionStoryArtProvider = FutureProvider.autoDispose
    .family<List<CollectionArtShot>, String>((ref, id) async {
  if (gameOfId(id) != Game.arknights) return [];
  final pack = await ref.watch(storyArtPackProvider.future);
  if (!await pack.installed) return [];
  await ref.watch(gameDataInstallStatusProvider.future);
  final stories = await ref.watch(collectionStoriesProvider(id).future);
  final events =
      await ref.watch(gameStoreProvider(Game.arknights)).withDatabase(
                (db) => readStoryArtEvents(
                  db,
                  stories.map((s) => s.rawId).whereType<String>(),
                ),
              ) ??
          <StoryArtEvent>[];
  final info = await pack.artInfo([
    for (final event in events)
      if (event.image != null)
        (event.image!, event.kind == 'background' ? 'scene' : event.kind),
  ]);
  return groupCollectionArt(
    stories,
    events,
    (image, kind) =>
        info[(image, kind == 'background' ? 'scene' : kind)]?.solid,
  );
});
