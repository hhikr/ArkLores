import 'package:sqflite_common/sqlite_api.dart';

Future<bool> _hasTable(DatabaseExecutor db, String name) async =>
    (await db.rawQuery(
      "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?",
      [name],
    ))
        .isNotEmpty;

/// Whether this knowledge base has the portrait tables (0.20).
Future<bool> hasPortraitIndex(DatabaseExecutor db) =>
    _hasTable(db, 'portrait_groups');

Future<String?> spriteOfLine(
    DatabaseExecutor db, String storyId, int lineIndex,) async {
  if (!await _hasTable(db, 'story_line_portraits')) return null;
  final rows = await db.query(
    'story_line_portraits',
    columns: ['sprite'],
    where: 'story_id = ? AND line_index = ?',
    whereArgs: [storyId, lineIndex],
  );
  return rows.firstOrNull?['sprite'] as String?;
}

class SpeakerPortraits {
  const SpeakerPortraits({
    required this.speaker,
    required this.lines,
    required this.topSprite,
    required this.highlight,
    required this.groups,
  });
  final String speaker;
  final int lines;
  final String topSprite;
  final bool highlight;
  final List<SpeakerGroup> groups;
}

class SpeakerGroup {
  const SpeakerGroup({
    required this.groupId,
    required this.lines,
    required this.stories,
    required this.topSprite,
    required this.groupSpeakers,
    this.operatorEntryId,
  });
  final String groupId;
  final int lines, stories, groupSpeakers;
  final String topSprite;
  final String? operatorEntryId;
}

class PortraitGroup {
  const PortraitGroup({
    required this.groupId,
    required this.lines,
    required this.sprites,
    required this.topSprite,
    this.operatorEntryId,
    required this.speakers,
  });
  final String groupId;
  final int lines, sprites;
  final String topSprite;
  final String? operatorEntryId;
  final List<GroupSpeaker> speakers;
}

class GroupSpeaker {
  const GroupSpeaker(
      {required this.speaker, required this.lines, required this.stories,});
  final String speaker;
  final int lines, stories;
}

Future<bool> _hasGroups(DatabaseExecutor db) async =>
    await hasPortraitIndex(db) && await _hasTable(db, 'speaker_portraits');

Future<SpeakerPortraits?> speakerPortraits(
    DatabaseExecutor db, String speaker,) async {
  if (!await _hasTable(db, 'speaker_names') || !await _hasGroups(db)) {
    return null;
  }
  final rows = await db
      .query('speaker_names', where: 'speaker = ?', whereArgs: [speaker]);
  if (rows.isEmpty) return null;
  final row = rows.single;
  final groups = await db.rawQuery(
    '''
    SELECT p.*, g.speakers, g.operator_entry_id FROM speaker_portraits p
    JOIN portrait_groups g ON g.group_id = p.group_id
    WHERE p.speaker = ? ORDER BY p.lines DESC, p.group_id ASC
  ''',
    [speaker],
  );
  return SpeakerPortraits(
    speaker: speaker,
    lines: row['lines'] as int,
    topSprite: row['top_sprite'] as String,
    highlight: row['highlight'] == 1,
    groups: [
      for (final g in groups)
        SpeakerGroup(
          groupId: g['group_id'] as String,
          lines: g['lines'] as int,
          stories: g['stories'] as int,
          topSprite: g['top_sprite'] as String,
          groupSpeakers: g['speakers'] as int,
          operatorEntryId: g['operator_entry_id'] as String?,
        ),
    ],
  );
}

Future<PortraitGroup?> portraitGroup(
    DatabaseExecutor db, String groupId,) async {
  if (!await _hasGroups(db)) return null;
  final rows = await db
      .query('portrait_groups', where: 'group_id = ?', whereArgs: [groupId]);
  if (rows.isEmpty) return null;
  final row = rows.single;
  final speakers = await db.query(
    'speaker_portraits',
    where: 'group_id = ?',
    whereArgs: [groupId],
    orderBy: 'lines DESC, speaker ASC',
  );
  return PortraitGroup(
    groupId: groupId,
    lines: row['lines'] as int,
    sprites: row['sprites'] as int,
    topSprite: row['top_sprite'] as String,
    operatorEntryId: row['operator_entry_id'] as String?,
    speakers: [
      for (final s in speakers)
        GroupSpeaker(
          speaker: s['speaker'] as String,
          lines: s['lines'] as int,
          stories: s['stories'] as int,
        ),
    ],
  );
}

Future<List<String>> highlightNames(DatabaseExecutor db) async {
  if (!await _hasTable(db, 'speaker_names')) return const [];
  return [
    for (final row in await db.query(
      'speaker_names',
      columns: ['speaker'],
      where: 'highlight = 1',
      orderBy: 'speaker ASC',
    ))
      row['speaker'] as String,
  ];
}
