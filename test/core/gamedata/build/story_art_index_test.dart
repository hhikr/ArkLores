import 'package:arklores/core/gamedata/build/story_art_index.dart';
import 'package:arklores/core/gamedata/build/story_script.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../support/sqlite.dart';

void main() {
  setUpAll(useSqfliteFfi);
  test('old tables gain nullable layer columns and migration is repeatable',
      () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);
    await db.execute(
        'CREATE TABLE story_art_events(story_id TEXT,seq INTEGER,at_line INTEGER,kind TEXT,image TEXT,layout TEXT,PRIMARY KEY(story_id,seq))',);
    await db.insert('story_art_events', {
      'story_id': 'old',
      'seq': 0,
      'at_line': 0,
      'kind': 'cg',
      'image': 'old',
    });
    await ensureStoryArtTable(db);
    await ensureStoryArtTable(db);
    final old = (await db.query('story_art_events')).single;
    expect(old['image'], 'old');
    expect(old['x'], isNull);
    await writeStoryArtRows(db, 'new', [
      const StoryArtEvent(1, StoryArtKind.item,
          image: 'actor', x: 20, y: -10, scale: 1.4, alpha: .5, layer: 2,),
    ]);
    final row = (await db
            .query('story_art_events', where: 'story_id=?', whereArgs: ['new']))
        .single;
    expect([row['x'], row['y'], row['scale'], row['alpha'], row['layer']],
        [20.0, -10.0, 1.4, .5, 2],);
  });
}
