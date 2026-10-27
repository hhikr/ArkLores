import 'package:sqflite_common/sqlite_api.dart';

import 'gamedata_schema.dart';
import 'portrait_names.dart';

const storyLinePortraitsTable = 'story_line_portraits';
const portraitSpritesTable = 'portrait_sprites';
const portraitGroupsTable = 'portrait_groups';
const speakerPortraitsTable = 'speaker_portraits';
const speakerNamesTable = 'speaker_names';
const storyLinePortraitsIndexDdl =
    'CREATE INDEX IF NOT EXISTS story_line_portraits_sprite ON story_line_portraits(sprite)';
const portraitSpritesIndexDdl =
    'CREATE INDEX portrait_sprites_group ON portrait_sprites(group_id)';
const speakerPortraitsIndexDdl =
    'CREATE INDEX speaker_portraits_group ON speaker_portraits(group_id)';

const storyLinePortraitsDdl =
    '''CREATE TABLE IF NOT EXISTS story_line_portraits (
  story_id TEXT NOT NULL,
  line_index INTEGER NOT NULL,
  sprite TEXT NOT NULL,
  PRIMARY KEY (story_id, line_index)
) WITHOUT ROWID''';
const portraitSpritesDdl = '''CREATE TABLE portrait_sprites (
  sprite TEXT PRIMARY KEY,
  group_id TEXT NOT NULL,
  face INTEGER NOT NULL,
  body INTEGER NOT NULL,
  lines INTEGER NOT NULL
) WITHOUT ROWID''';
const portraitGroupsDdl = '''CREATE TABLE portrait_groups (
  group_id TEXT PRIMARY KEY,
  operator_entry_id TEXT,
  lines INTEGER NOT NULL,
  speakers INTEGER NOT NULL,
  sprites INTEGER NOT NULL,
  top_sprite TEXT NOT NULL
) WITHOUT ROWID''';
const speakerPortraitsDdl = '''CREATE TABLE speaker_portraits (
  speaker TEXT NOT NULL,
  group_id TEXT NOT NULL,
  lines INTEGER NOT NULL,
  stories INTEGER NOT NULL,
  top_sprite TEXT NOT NULL,
  PRIMARY KEY (speaker, group_id)
) WITHOUT ROWID''';
const speakerNamesDdl = '''CREATE TABLE speaker_names (
  speaker TEXT PRIMARY KEY,
  lines INTEGER NOT NULL,
  groups INTEGER NOT NULL,
  top_group TEXT NOT NULL,
  top_sprite TEXT NOT NULL,
  owns_group INTEGER NOT NULL,
  highlight INTEGER NOT NULL,
  mentions INTEGER NOT NULL
) WITHOUT ROWID''';

/// One character is too often part of other words to link.
const highlightMinNameLength = 2;
const _derived = {
  portraitSpritesTable: portraitSpritesDdl,
  portraitGroupsTable: portraitGroupsDdl,
  speakerPortraitsTable: speakerPortraitsDdl,
  speakerNamesTable: speakerNamesDdl,
};

Future<bool> _exists(DatabaseExecutor db, String table) async =>
    (await db.rawQuery(
      "SELECT 1 FROM sqlite_master WHERE type='table' AND name=?",
      [table],
    ))
        .isNotEmpty;

Future<void> ensurePortraitTables(DatabaseExecutor db) async {
  await db.execute(storyLinePortraitsDdl);
  await db.execute(storyLinePortraitsIndexDdl);
}

Future<void> deletePortraitRows(DatabaseExecutor db, String storyId) async {
  if (await _exists(db, storyLinePortraitsTable)) {
    await db.delete(
      storyLinePortraitsTable,
      where: 'story_id = ?',
      whereArgs: [storyId],
    );
  }
}

/// Replaces only portrait-derived data, with lexical tie breaking throughout.
Future<void> rebuildPortraitIndex(Database db) async {
  await db.transaction((txn) async {
    for (final table in _derived.keys) {
      await txn.execute('DROP TABLE IF EXISTS $table');
    }
    await txn.delete(
      'gamedata_manifest',
      where: "substr(key, 1, 9) = 'portrait_'",
    );
    if (!await _exists(txn, storyLinePortraitsTable) ||
        (await txn.rawQuery('SELECT 1 FROM story_line_portraits LIMIT 1'))
            .isEmpty) {
      return;
    }
    for (final ddl in _derived.values) {
      await txn.execute(ddl);
    }
    await txn.execute(portraitSpritesIndexDdl);
    await txn.execute(speakerPortraitsIndexDdl);
    final batch = txn.batch();
    for (final row in await txn.rawQuery(
      'SELECT sprite, COUNT(*) AS lines FROM story_line_portraits GROUP BY sprite',
    )) {
      final sprite = row['sprite'] as String;
      final name = SpriteName.parse(sprite);
      if (name == null) throw StateError('Invalid canonical sprite: $sprite');
      batch.insert(portraitSpritesTable, {
        'sprite': sprite,
        'group_id': name.group,
        'face': name.face,
        'body': name.body,
        'lines': row['lines'],
      });
    }
    await batch.commit(noResult: true);
    // Aggregate once per speaker/sprite before selecting representative sprites.
    await txn.execute('''CREATE TEMP TABLE portrait_lines AS
      SELECT trim(l.speaker) AS speaker, s.group_id, p.sprite,
        p.story_id
      FROM story_line_portraits p JOIN story_lines l
        ON l.story_id=p.story_id AND l.line_index=p.line_index
      JOIN portrait_sprites s ON s.sprite=p.sprite
      WHERE trim(COALESCE(l.speaker, '')) <> '' ''');
    await txn.execute(
      'CREATE INDEX temp.portrait_lines_speaker ON portrait_lines(speaker, group_id)',
    );
    await txn.execute('''CREATE TEMP TABLE portrait_counts AS
      SELECT speaker, group_id, sprite, COUNT(*) AS lines FROM portrait_lines
      GROUP BY speaker, group_id, sprite''');
    await txn.execute(
      'CREATE INDEX temp.portrait_counts_speaker ON portrait_counts(speaker, group_id)',
    );
    try {
      await txn.execute('''INSERT INTO speaker_portraits
        SELECT c.speaker, c.group_id, SUM(c.lines),
          (SELECT COUNT(DISTINCT p.story_id) FROM portrait_lines p
           WHERE p.speaker=c.speaker AND p.group_id=c.group_id),
          (SELECT d.sprite FROM portrait_counts d
           WHERE d.speaker=c.speaker AND d.group_id=c.group_id
           ORDER BY d.lines DESC, d.sprite LIMIT 1)
        FROM portrait_counts c GROUP BY c.speaker, c.group_id''');
      await txn.execute('''INSERT INTO portrait_groups
        SELECT s.group_id, NULL, SUM(s.lines),
          (SELECT COUNT(*) FROM speaker_portraits p WHERE p.group_id=s.group_id),
          COUNT(*), (SELECT t.sprite FROM portrait_sprites t WHERE t.group_id=s.group_id
          ORDER BY t.lines DESC, t.sprite LIMIT 1)
        FROM portrait_sprites s GROUP BY s.group_id''');
      final operatorPattern = RegExp(r'^(?:char|avg)_(\d+)_([a-z0-9]+)');
      final operators = {
        for (final r in await txn
            .rawQuery("SELECT id FROM entries WHERE id LIKE 'operator:%'"))
          r['id'],
      };
      final updates = txn.batch();
      for (final row
          in await txn.query(portraitGroupsTable, columns: ['group_id'])) {
        final m = operatorPattern.firstMatch(row['group_id'] as String);
        if (m == null) continue;
        final candidate = 'operator:char_${m[1]}_${m[2]}';
        if (operators.contains(candidate)) {
          updates.update(
            portraitGroupsTable,
            {'operator_entry_id': candidate},
            where: 'group_id=?',
            whereArgs: [row['group_id']],
          );
        }
      }
      await updates.commit(noResult: true);
      await txn.execute('''INSERT INTO speaker_names
        SELECT p.speaker, SUM(p.lines), COUNT(*),
          (SELECT q.group_id FROM speaker_portraits q WHERE q.speaker=p.speaker
           ORDER BY q.lines DESC, q.group_id LIMIT 1),
          (SELECT c.sprite FROM portrait_counts c WHERE c.speaker=p.speaker
           ORDER BY c.lines DESC, c.sprite LIMIT 1),
          EXISTS(SELECT 1 FROM speaker_portraits q JOIN portrait_groups g ON g.group_id=q.group_id
            WHERE q.speaker=p.speaker AND q.lines*2 >= g.lines
            AND q.speaker=(SELECT r.speaker FROM speaker_portraits r WHERE r.group_id=q.group_id
              ORDER BY r.lines DESC, r.speaker LIMIT 1)), 0, 0
        FROM speaker_portraits p GROUP BY p.speaker''');
      final letters = RegExp(r'\p{L}', unicode: true);
      final combined = RegExp(r'[&＆/]');
      // Every speaker with a portrait is highlighted, titles, crowds, shared
      // portraits, often used words and `<name>？` included (developer,
      // 2026-10-27): left out are one character, no letters and joint
      // labels.
      bool named(String name) =>
          letters.hasMatch(name) && !combined.hasMatch(name);
      final candidates = <String, Map<String, Object?>>{
        for (final row in await txn.query(speakerNamesTable))
          if ((row['speaker'] as String).runes.length >=
                  highlightMinNameLength &&
              named(row['speaker'] as String))
            row['speaker'] as String: row,
      };
      final mentions = await _countMentions(txn, candidates.keys);
      final highlights = txn.batch();
      for (final speaker in candidates.keys) {
        highlights.update(
          speakerNamesTable,
          {'mentions': mentions[speaker]!, 'highlight': 1},
          where: 'speaker=?',
          whereArgs: [speaker],
        );
      }
      await highlights.commit(noResult: true);
    } finally {
      await txn.execute('DROP TABLE portrait_counts');
      await txn.execute('DROP TABLE portrait_lines');
    }
    final counts = await txn.rawQuery(
      'SELECT (SELECT COUNT(*) FROM story_line_portraits) AS lines, (SELECT COUNT(*) FROM portrait_groups) AS groups',
    );
    await writeGamedataManifest(txn, {
      'portrait_index_version': '7',
      'portrait_line_count': '${counts.single['lines']}',
      'portrait_group_count': '${counts.single['groups']}',
    });
  });
}

/// How many times each of [names] occurs in the dialogue and narration text,
/// inside longer words too.
Future<Map<String, int>> _countMentions(
  DatabaseExecutor db,
  Iterable<String> names,
) async {
  final counts = {for (final name in names) name: 0};
  final byFirst = <int, List<String>>{};
  for (final name in counts.keys) {
    (byFirst[name.codeUnitAt(0)] ??= []).add(name);
  }
  if (byFirst.isEmpty) return counts;
  for (final row in await db.rawQuery(
    "SELECT content FROM story_lines WHERE kind IN ('dialogue', 'narration')",
  )) {
    final text = row['content'] as String;
    for (var i = 0; i < text.length; i++) {
      final starting = byFirst[text.codeUnitAt(i)];
      if (starting == null) continue;
      for (final name in starting) {
        if (text.startsWith(name, i)) counts[name] = counts[name]! + 1;
      }
    }
  }
  return counts;
}
