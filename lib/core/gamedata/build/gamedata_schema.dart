/// GameData build schema definitions shared by the desktop CLI builder and the
/// in-app builder (R0: extracted from `tools/build_gamedata_database.dart`).
///
/// This library is pure SQL + constants: no importer logic, no file I/O.
/// The same `createGamedataSchema` runs on the desktop FFI backend and on the
/// mobile `sqflite` backend, so desktop releases and in-app builds stay
/// schema-consistent.
library;

import 'package:sqflite_common/sqlite_api.dart';

/// Current GameData schema version produced by the builder.
///
/// The app installer rejects databases whose manifest schema_version differs
/// from this value (see `GameDataInstaller._validateDatabase`).
///
/// v3 added tables derived from the story text and a full-text index over
/// story lines; 0.14 removed them again (see [obsoleteGamedataTables]) without
/// a version change: nothing read them, so a database with or without them
/// is the same to the app.
///
/// v4 (R3 follow-up, data fix) changes no tables: the importer now skips the
/// upstream repo's `[uc]info/` one-line story-stub tree (previously imported
/// alongside the real full-text tree, duplicating every story under a
/// `[uc]info` scope) and groups `obt/<group>/...` stories under `obt:<group>`
/// scopes (previously all lumped under `obt:obt`). v3 databases built before
/// this fix contain stub rows that incremental updates cannot purge, so the
/// version bump forces a clean rebuild.
///
/// v5 (0.11) reshapes the knowledge base around entries:
/// - `story_lines.kind` tells dialogue from narration, scene captions,
///   in-scene documents, player choices, headings and tutorial text; the
///   story parser now reads every text-bearing command, not only
///   `[name="X"]` lines (`story_script.dart`);
/// - `collections` (activity, main chapter, operator record, roguelike
///   topic, sandbox …) own `entries` (one row per official item: story,
///   operator, enemy, stage, relic, event, ending, archive document …);
///   `entry_links` binds them (enemy ↔ stage, operator ↔ record set,
///   story ↔ stage …). `normalized_records.entry_id` points each citable
///   record at its entry. Gameplay text (skills, mechanics, rules,
///   obtain methods, ability descriptions) is not imported.
const int gamedataSchemaVersion = 5;

/// Language of the Arknights knowledge base build.
const String gamedataLanguage = 'zh';

/// Index of `story_lines` by chapter and line. Builds from v0.10.7 on carry
/// it; a knowledge base built earlier gets it from `GameDataKnowledgeStore`
/// the first time it is opened.
const String storyLinesIndexName = 'idx_story_lines_story_line';
const String storyLinesIndexSql =
    'CREATE INDEX IF NOT EXISTS $storyLinesIndexName '
    'ON story_lines(story_id, line_index)';

/// Game id recorded for Arknights rows.
const String gamedataGame = 'arknights';

/// Source repository URL recorded in manifest rows and normalized records.
const String arknightsSourceRepoUrl =
    'https://github.com/Kengxxiao/ArknightsGameData';

/// Creates the complete schema 2 GameData database layout.
Future<void> createGamedataSchema(Database db) async {
  await db.execute('PRAGMA foreign_keys = ON');
  await db.execute('''
    CREATE TABLE gamedata_manifest (
      key   TEXT PRIMARY KEY,
      value TEXT NOT NULL
    )
  ''');
  await db.execute('''
    CREATE TABLE entities (
      id           TEXT PRIMARY KEY,
      name         TEXT NOT NULL,
      aliases      TEXT,
      entity_type  TEXT NOT NULL,
      source_type  TEXT NOT NULL,
      game         TEXT NOT NULL,
      source_path  TEXT,
      game_version TEXT,
      updated_at   INTEGER
    )
  ''');
  await db.execute('''
    CREATE TABLE entity_aliases (
      alias       TEXT NOT NULL,
      entity_id   TEXT NOT NULL,
      alias_type  TEXT NOT NULL,
      confidence  REAL NOT NULL DEFAULT 1.0,
      source_path TEXT,
      PRIMARY KEY (alias, entity_id, alias_type),
      FOREIGN KEY (entity_id) REFERENCES entities(id)
    )
  ''');
  await db.execute('''
    CREATE TABLE story_lines (
      id          TEXT PRIMARY KEY,
      game        TEXT NOT NULL,
      story_id    TEXT NOT NULL,
      episode_id  TEXT,
      event_id    TEXT,
      speaker     TEXT,
      content     TEXT NOT NULL,
      line_index  INTEGER,
      language    TEXT NOT NULL DEFAULT 'zh',
      source_path TEXT,
      kind        TEXT NOT NULL DEFAULT 'dialogue'
    )
  ''');
  // Reading a chapter (`WHERE story_id = ? AND line_index ...`) scanned all
  // ~410k lines without this (~0.45 s a read); with it the read is instant.
  await db.execute(storyLinesIndexSql);
  await db.execute('''
    CREATE TABLE normalized_records (
      id             TEXT PRIMARY KEY,
      game           TEXT NOT NULL,
      language       TEXT NOT NULL DEFAULT 'zh',
      category       TEXT NOT NULL,
      subtype        TEXT NOT NULL,
      content_type   TEXT NOT NULL,
      entity_id      TEXT,
      entity_name    TEXT,
      parent_id      TEXT,
      parent_type    TEXT,
      title          TEXT,
      section        TEXT,
      speaker        TEXT,
      content        TEXT NOT NULL,
      source_path    TEXT NOT NULL,
      raw_id         TEXT,
      line_start     INTEGER,
      line_end       INTEGER,
      source_repo    TEXT,
      source_commit  TEXT,
      game_version   TEXT,
      updated_at     INTEGER,
      entry_id       TEXT,
      collection_id  TEXT
    )
  ''');
  await db.execute('''
    CREATE TABLE entity_documents (
      id                TEXT PRIMARY KEY,
      game              TEXT NOT NULL,
      language          TEXT NOT NULL DEFAULT 'zh',
      entity_id         TEXT NOT NULL,
      entity_name       TEXT NOT NULL,
      entity_type       TEXT NOT NULL,
      document_type     TEXT NOT NULL,
      title             TEXT NOT NULL,
      summary           TEXT,
      content           TEXT NOT NULL,
      source_paths      TEXT,
      source_record_ids TEXT,
      updated_at        INTEGER
    )
  ''');
  await db.execute('''
    CREATE TABLE story_scopes (
      story_id    TEXT PRIMARY KEY,
      scope_type  TEXT NOT NULL,
      scope_id    TEXT NOT NULL,
      source_path TEXT NOT NULL
    )
  ''');
  await db.execute(
    'CREATE INDEX idx_entities_name ON entities(name)',
  );
  await db.execute(
    'CREATE INDEX idx_normalized_records_type ON normalized_records(content_type)',
  );
  await db.execute(
    'CREATE INDEX idx_normalized_records_entity ON normalized_records(entity_id)',
  );
  await db.execute(
    'CREATE INDEX idx_entity_aliases_alias ON entity_aliases(alias)',
  );
  await db.execute(
    'CREATE INDEX idx_entity_aliases_entity ON entity_aliases(entity_id)',
  );
  await db.execute(
    'CREATE INDEX idx_entity_documents_entity ON entity_documents(entity_id)',
  );
  await db.execute(
    'CREATE INDEX idx_entity_documents_type ON entity_documents(document_type)',
  );
  // --- Schema v5 entry layer (0.11) ---
  await db.execute(collectionsDdl);
  await db.execute(entriesDdl);
  await db.execute(entryLinksDdl);
  for (final sql in entryLayerIndexes) {
    await db.execute(sql);
  }
  await db.execute(collectionEnemiesView);
}

/// Owners of entries: a main chapter, an activity, an operator's record set,
/// a roguelike topic, a sandbox … (`kind`). The unit "same story set / same
/// topic / same activity" of the library page and of attribution queries.
const String collectionsDdl = '''
  CREATE TABLE collections (
    id          TEXT PRIMARY KEY,
    kind        TEXT NOT NULL,
    name        TEXT,
    parent_id   TEXT,
    sort_key    INTEGER,
    start_time  INTEGER,
    source_path TEXT
  )
''';

/// One row per official item (story file, operator, enemy, stage, relic,
/// event, ending, archive document …). `record_id` is the citable
/// `normalized_records` row that carries the item's text.
const String entriesDdl = '''
  CREATE TABLE entries (
    id            TEXT PRIMARY KEY,
    type          TEXT NOT NULL,
    name          TEXT,
    code          TEXT,
    collection_id TEXT,
    group_name    TEXT,
    sort_key      INTEGER,
    entity_id     TEXT,
    raw_id        TEXT,
    record_id     TEXT,
    source_path   TEXT
  )
''';

/// Directed bindings between entries (`relation` is a stable verb such as
/// `appears_in`, `belongs_to`, `memory_of`). Binding is deterministic: it is
/// derived from ids in the source tables and never from names or guesses.
const String entryLinksDdl = '''
  CREATE TABLE entry_links (
    src         TEXT NOT NULL,
    relation    TEXT NOT NULL,
    dst         TEXT NOT NULL,
    source_path TEXT,
    PRIMARY KEY (src, relation, dst)
  )
''';

/// Enemies per collection (activity, main chapter, roguelike topic …): the
/// enemies that appear in any stage the collection owns.
const String collectionEnemiesView = '''
  CREATE VIEW collection_enemies AS
  SELECT DISTINCT s.collection_id AS collection_id, l.src AS enemy_id
  FROM entry_links l JOIN entries s ON s.id = l.dst
  WHERE l.relation = 'appears_in' AND s.collection_id IS NOT NULL
''';

const List<String> entryLayerIndexes = [
  'CREATE INDEX idx_entries_type ON entries(type)',
  'CREATE INDEX idx_entries_collection ON entries(collection_id, type, sort_key)',
  'CREATE INDEX idx_entries_name ON entries(name)',
  'CREATE INDEX idx_entries_source ON entries(source_path)',
  'CREATE INDEX idx_entries_entity ON entries(entity_id)',
  'CREATE INDEX idx_entry_links_dst ON entry_links(dst, relation)',
  'CREATE INDEX idx_entry_links_source ON entry_links(source_path)',
  'CREATE INDEX idx_collections_kind ON collections(kind, sort_key)',
  'CREATE INDEX idx_records_entry ON normalized_records(entry_id)',
  'CREATE INDEX idx_records_collection ON normalized_records(collection_id)',
];

/// Upserts key/value rows into `gamedata_manifest`.
Future<void> writeGamedataManifest(
  DatabaseExecutor db,
  Map<String, String> values,
) async {
  for (final entry in values.entries) {
    await db.insert(
      'gamedata_manifest',
      {'key': entry.key, 'value': entry.value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}

/// Tables earlier builds wrote that nothing reads (0.14): the chunked copy
/// of every text and its index, two more full-text indexes (the one over
/// story lines could not match Chinese inside a sentence), a relation table
/// that only tied an operator to its own voice lines, and the "coverage"
/// tables derived from the story text (name mentions, rare bigrams, a
/// profile per story). A database that has them loses them when it is
/// updated ([dropObsoleteGamedataData]).
const List<String> obsoleteGamedataTables = [
  'lore_chunks_fts',
  'entity_documents_fts',
  'story_lines_fts',
  'lore_chunks',
  'entity_relations',
  'entity_story_mentions',
  'story_chapter_profiles',
  'rare_terms',
];

/// Manifest keys that counted rows of [obsoleteGamedataTables].
const List<String> obsoleteGamedataManifestKeys = [
  'lore_chunk_count',
  'arknights_profile_chunk_count',
  'arknights_story_chunk_count',
  'arknights_structured_chunk_count',
  'story_coverage_mention_count',
  'story_profile_count',
  'rare_term_count',
];

/// Removes what earlier builds wrote and nothing reads: the
/// [obsoleteGamedataTables], the story text kept a second time as records
/// (`parent_type = 'story_file'`; the text is `story_lines`) with their
/// vectors, and the entities made of story speakers' names. Returns whether
/// anything was removed (the caller may then `VACUUM`; not possible inside a
/// transaction).
Future<bool> dropObsoleteGamedataData(Database db) async {
  Future<bool> has(String table) async => (await db.rawQuery(
        "SELECT 1 FROM sqlite_master WHERE type IN ('table', 'view') "
        'AND name = ?',
        [table],
      ))
          .isNotEmpty;
  var removed = false;
  for (final table in obsoleteGamedataTables) {
    if (!await has(table)) continue;
    await db.execute('DROP TABLE $table');
    removed = true;
  }
  if (await has('record_chunk_vectors')) {
    removed |= await db.rawDelete(
          'DELETE FROM record_chunk_vectors WHERE record_id IN '
          "(SELECT id FROM normalized_records WHERE parent_type = 'story_file')",
        ) >
        0;
  }
  removed |= await db.delete(
        'normalized_records',
        where: 'parent_type = ?',
        whereArgs: ['story_file'],
      ) >
      0;
  await db.rawDelete(
    'DELETE FROM entity_aliases WHERE entity_id IN '
    "(SELECT id FROM entities WHERE source_type = 'story_speaker')",
  );
  removed |= await db.delete(
        'entities',
        where: 'source_type = ?',
        whereArgs: ['story_speaker'],
      ) >
      0;
  await db.delete(
    'gamedata_manifest',
    where:
        'key IN (${List.filled(obsoleteGamedataManifestKeys.length, '?').join(',')})',
    whereArgs: obsoleteGamedataManifestKeys,
  );
  return removed;
}
