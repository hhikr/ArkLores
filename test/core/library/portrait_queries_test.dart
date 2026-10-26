import 'package:arklores/core/gamedata/build/portrait_index.dart';
import 'package:arklores/core/library/portrait_queries.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/gamedata_fixture.dart';

void main() {
  late Database db;
  setUpAll(sqfliteFfiInit);
  setUp(() async => db = await createGameDataDb(inMemoryDatabasePath));
  tearDown(() => db.close());

  test('optional tables missing return empty results', () async {
    for (final table in [
      'portrait_groups',
      'speaker_names',
      'speaker_portraits',
      'story_line_portraits',
    ]) {
      await db.execute('DROP TABLE IF EXISTS $table');
    }
    expect(await hasPortraitIndex(db), isFalse);
    expect(await spriteOfLine(db, 'story', 1), isNull);
    expect(await speakerPortraits(db, 'speaker'), isNull);
    expect(await portraitGroup(db, 'group'), isNull);
    expect(await highlightNames(db), isEmpty);
  });

  test('reads rows and sorts ties deterministically', () async {
    for (final ddl in [
      storyLinePortraitsDdl,
      portraitGroupsDdl,
      speakerNamesDdl,
      speakerPortraitsDdl,
    ]) {
      await db.execute(ddl);
    }
    await db.insert('story_line_portraits',
        {'story_id': 'story', 'line_index': 1, 'sprite': 'sprite'},);
    for (final id in ['b', 'a', 'c']) {
      await db.insert('portrait_groups', {
        'group_id': id,
        'operator_entry_id': id == 'a' ? 'operator:test' : null,
        'lines': 20,
        'speakers': 3,
        'sprites': 4,
        'top_sprite': '$id#1\$1',
      });
    }
    for (final name in ['beta', 'alpha', 'gamma']) {
      await db.insert('speaker_names', {
        'speaker': name,
        'lines': 30,
        'groups': 3,
        // alpha's own portrait is the operator's (a); beta's is not.
        'top_group': name == 'beta' ? 'b' : 'a',
        'top_sprite': 'top',
        'owns_group': 1,
        'highlight': name == 'gamma' ? 0 : 1,
        'mentions': 10,
      });
      for (final id in ['b', 'a', 'c']) {
        await db.insert('speaker_portraits', {
          'speaker': name,
          'group_id': id,
          'lines': name == 'gamma' || id == 'c' ? 15 : 10,
          'stories': 2,
          'top_sprite': '$id#2\$1',
        });
      }
    }
    expect(await hasPortraitIndex(db), isTrue);
    expect(await spriteOfLine(db, 'story', 1), 'sprite');
    expect(await spriteOfLine(db, 'story', 2), isNull);
    expect(await speakerPortraits(db, 'absent'), isNull);
    final speaker = (await speakerPortraits(db, 'alpha'))!;
    expect(speaker.speaker, 'alpha');
    expect(speaker.lines, 30);
    expect(speaker.topSprite, 'top');
    expect(speaker.highlight, isTrue);
    expect(speaker.groups.map((g) => g.groupId), ['c', 'a', 'b']);
    expect(speaker.groups[1].operatorEntryId, 'operator:test');
    expect(speaker.groups.first.groupSpeakers, 3);
    expect(speaker.groups.first.stories, 2);
    expect(speaker.groups.first.topSprite, 'c#2\$1');
    expect(await portraitGroup(db, 'absent'), isNull);
    final group = (await portraitGroup(db, 'a'))!;
    expect(group.groupId, 'a');
    expect(group.lines, 20);
    expect(group.sprites, 4);
    expect(group.topSprite, 'a#1\$1');
    expect(group.operatorEntryId, 'operator:test');
    expect(group.speakers.map((s) => s.speaker), ['gamma', 'alpha', 'beta']);
    expect(group.speakers.first.lines, 15);
    expect(group.speakers.first.stories, 2);
    expect(await highlightNames(db), ['alpha', 'beta']);
    expect(await highlightNames(db, skipOperators: true), ['beta']);
  });
}
