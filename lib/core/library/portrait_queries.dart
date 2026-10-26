import 'package:sqflite_common/sqlite_api.dart';
import '../gamedata/story_catalog.dart';

Future<List<String>> portraitSprites(
  DatabaseExecutor db,
  String groupId,
) async {
  if (!await _hasTable(db, 'portrait_sprites')) return const [];
  return [
    for (final row in await db.query(
      'portrait_sprites',
      columns: ['sprite'],
      where: 'group_id = ?',
      whereArgs: [groupId],
      orderBy: 'body ASC, face ASC, sprite ASC',
    ))
      row['sprite'] as String,
  ];
}

class PortraitStory {
  const PortraitStory({
    required this.storyId,
    required this.firstLine,
    required this.lines,
    this.catalog,
  });
  final String storyId;
  final int firstLine, lines;
  final StoryCatalogEntry? catalog;
}

Future<List<PortraitStory>> portraitStories(
  DatabaseExecutor db,
  String speaker,
  String groupId,
) async {
  if (!await _hasTable(db, 'story_line_portraits') ||
      !await _hasTable(db, 'portrait_sprites')) {
    return const [];
  }
  final rows = await db.rawQuery(
    '''
    SELECT p.story_id, MIN(p.line_index) AS first_line, COUNT(*) AS lines
    FROM portrait_sprites s
    JOIN story_line_portraits p ON p.sprite = s.sprite
    JOIN story_lines l ON l.story_id = p.story_id AND l.line_index = p.line_index
    WHERE s.group_id = ? AND TRIM(l.speaker) = ?
    GROUP BY p.story_id
  ''',
    [groupId, speaker.trim()],
  );
  final catalog = <String, StoryCatalogEntry>{};
  if (rows.isNotEmpty && await _hasTable(db, 'story_catalog')) {
    final ids = rows.map((r) => r['story_id']).toList();
    for (final row in await db.rawQuery(
      'SELECT * FROM story_catalog WHERE story_id IN (${List.filled(ids.length, '?').join(',')})',
      ids,
    )) {
      final entry = StoryCatalogEntry.fromRow(row);
      catalog[entry.storyId] = entry;
    }
  }
  final result = [
    for (final row in rows)
      PortraitStory(
        storyId: row['story_id'] as String,
        firstLine: row['first_line'] as int,
        lines: row['lines'] as int,
        catalog: catalog[row['story_id']],
      ),
  ];
  result.sort((a, b) {
    if (a.catalog != null && b.catalog != null) {
      final order = compareStoryReleaseKeys(
        storyReleaseKey(a.catalog!),
        storyReleaseKey(b.catalog!),
      );
      if (order != 0) return order;
    } else if (a.catalog != null || b.catalog != null) {
      return a.catalog != null ? -1 : 1;
    }
    return a.storyId.compareTo(b.storyId);
  });
  return result;
}

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
  DatabaseExecutor db,
  String storyId,
  int lineIndex,
) async {
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
  const GroupSpeaker({
    required this.speaker,
    required this.lines,
    required this.stories,
  });
  final String speaker;
  final int lines, stories;
}

Future<bool> _hasGroups(DatabaseExecutor db) async =>
    await hasPortraitIndex(db) && await _hasTable(db, 'speaker_portraits');

Future<SpeakerPortraits?> speakerPortraits(
  DatabaseExecutor db,
  String speaker,
) async {
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
  DatabaseExecutor db,
  String groupId,
) async {
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

/// Names an Ask answer may highlight (speaker_names.highlight = 1). With
/// [skipOperators], not the names whose most used portrait
/// (`speaker_names.top_group`) is an operator's
/// (`portrait_groups.operator_entry_id`, from the tables' ids).
Future<List<String>> highlightNames(
  DatabaseExecutor db, {
  bool skipOperators = false,
}) async {
  if (!await _hasTable(db, 'speaker_names')) return const [];
  final operatorFilter = skipOperators && await hasPortraitIndex(db)
      ? ' AND NOT EXISTS (SELECT 1 FROM portrait_groups g'
          ' WHERE g.group_id = n.top_group'
          ' AND g.operator_entry_id IS NOT NULL)'
      : '';
  return [
    for (final row in await db.rawQuery(
      'SELECT n.speaker FROM speaker_names n WHERE n.highlight = 1'
      '$operatorFilter ORDER BY n.speaker ASC',
    ))
      row['speaker'] as String,
  ];
}
