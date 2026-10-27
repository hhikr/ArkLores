import 'package:sqflite_common/sqlite_api.dart';
import 'gamedata_schema.dart';
import 'story_script.dart';

const storyArtEventsTable = 'story_art_events';
Future<void> ensureStoryArtTable(DatabaseExecutor db) async {
  await db.execute('''CREATE TABLE IF NOT EXISTS story_art_events (
  story_id TEXT NOT NULL, seq INTEGER NOT NULL, at_line INTEGER NOT NULL,
  kind TEXT NOT NULL, image TEXT, layout TEXT, PRIMARY KEY (story_id, seq)
)''');
  await db.execute(
      'CREATE INDEX IF NOT EXISTS story_art_events_image ON story_art_events(image)',);
}

Future<void> deleteStoryArtRows(DatabaseExecutor db, String storyId) async {
  final exists = await db.rawQuery(
      "SELECT 1 FROM sqlite_master WHERE type='table' AND name=?",
      [storyArtEventsTable],);
  if (exists.isNotEmpty) {
    await db.delete(storyArtEventsTable,
        where: 'story_id = ?', whereArgs: [storyId],);
  }
}

Future<void> writeStoryArtRows(
    DatabaseExecutor db, String storyId, List<StoryArtEvent> events,) async {
  final batch = db.batch();
  for (var i = 0; i < events.length; i++) {
    final e = events[i];
    batch.insert(storyArtEventsTable, {
      'story_id': storyId,
      'seq': i,
      'at_line': e.atLine,
      'kind': e.kind.value,
      'image': e.image,
      'layout': e.layout,
    });
  }
  await batch.commit(noResult: true);
}

Future<void> updateStoryArtManifest(DatabaseExecutor db) async {
  final exists = await db.rawQuery(
      "SELECT 1 FROM sqlite_master WHERE type='table' AND name=?",
      [storyArtEventsTable],);
  if (exists.isEmpty) return;
  final count =
      (await db.rawQuery('SELECT COUNT(*) AS n FROM story_art_events'))
          .single['n'];
  await writeGamedataManifest(
      db, {'story_art_index_version': '1', 'story_art_event_count': '$count'},);
}
