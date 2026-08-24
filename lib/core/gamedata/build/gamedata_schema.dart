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
/// v3 (R1, AI retrieval P0) is additive over v2: it adds the deterministic
/// coverage layer tables (`entity_story_mentions`, `story_chapter_profiles`,
/// `rare_terms`) and the `story_lines_fts` external-content FTS index. No
/// existing table or column is modified.
const int gamedataSchemaVersion = 3;

/// Language of the Arknights knowledge base build.
const String gamedataLanguage = 'zh';

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
      source_path TEXT
    )
  ''');
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
      updated_at     INTEGER
    )
  ''');
  await db.execute('''
    CREATE TABLE entity_relations (
      id               TEXT PRIMARY KEY,
      source_entity_id TEXT NOT NULL,
      target_entity_id TEXT NOT NULL,
      relation_type    TEXT NOT NULL,
      source_path      TEXT,
      raw_id           TEXT
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
  await db.execute('''
    CREATE TABLE lore_chunks (
      id             TEXT PRIMARY KEY,
      game           TEXT NOT NULL,
      source_type    TEXT NOT NULL,
      content_category TEXT,
      content_subtype  TEXT,
      content_type     TEXT,
      entity_id      TEXT,
      story_id       TEXT,
      scope_type     TEXT,
      scope_id       TEXT,
      page_title     TEXT,
      section        TEXT,
      content        TEXT NOT NULL,
      source_path    TEXT,
      source_url     TEXT,
      line_start     INTEGER,
      line_end       INTEGER,
      speaker        TEXT,
      language       TEXT NOT NULL DEFAULT 'zh',
      game_version   TEXT,
      updated_at     INTEGER,
      raw_id         TEXT,
      retrieval_hint TEXT
    )
  ''');
  await db.execute('''
    CREATE VIRTUAL TABLE entity_documents_fts USING fts5(
      entity_name,
      entity_type,
      document_type,
      title,
      summary,
      content,
      content='entity_documents',
      content_rowid='rowid',
      tokenize='trigram'
    )
  ''');
  await db.execute('''
    CREATE VIRTUAL TABLE lore_chunks_fts USING fts5(
      page_title,
      section,
      speaker,
      content,
      content='lore_chunks',
      content_rowid='rowid'
    )
  ''');
  // --- Schema v3 additive coverage layer (R1 / AI retrieval P0) ---
  await db.execute('''
    CREATE TABLE entity_story_mentions (
      entity_id     TEXT NOT NULL,
      story_id      TEXT NOT NULL,
      scope_id      TEXT NOT NULL,
      line_start    INTEGER NOT NULL,
      line_end      INTEGER NOT NULL,
      mention_count INTEGER NOT NULL,
      matched_alias TEXT,
      PRIMARY KEY (entity_id, story_id, line_start)
    )
  ''');
  await db.execute(
    'CREATE INDEX idx_mentions_scope ON entity_story_mentions(scope_id, story_id)',
  );
  await db.execute('''
    CREATE TABLE story_chapter_profiles (
      story_id       TEXT PRIMARY KEY,
      scope_id       TEXT NOT NULL,
      title          TEXT,
      line_start     INTEGER NOT NULL,
      line_end       INTEGER NOT NULL,
      speaker_set    TEXT,
      entity_density TEXT,
      summary        TEXT,
      keyword_hits   TEXT
    )
  ''');
  await db.execute(
    'CREATE INDEX idx_profiles_scope ON story_chapter_profiles(scope_id)',
  );
  await db.execute('''
    CREATE TABLE rare_terms (
      term     TEXT PRIMARY KEY,
      doc_freq INTEGER NOT NULL
    )
  ''');
  await db.execute('''
    CREATE VIRTUAL TABLE story_lines_fts USING fts5(
      content,
      content='story_lines',
      content_rowid='rowid'
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
    'CREATE INDEX idx_lore_chunks_source_type ON lore_chunks(source_type)',
  );
  await db.execute(
    'CREATE INDEX idx_lore_chunks_content_type ON lore_chunks(content_type)',
  );
  await db.execute(
    'CREATE INDEX idx_lore_chunks_entity_id ON lore_chunks(entity_id)',
  );
  await db.execute(
    'CREATE INDEX idx_lore_chunks_scope ON lore_chunks(scope_type, scope_id)',
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
}

/// Upserts key/value rows into `gamedata_manifest`.
Future<void> writeGamedataManifest(
  Database db,
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

/// Rebuilds all FTS5 external-content indexes over their base tables.
///
/// The `rebuild` command is executed by the FTS5 virtual table itself; the
/// external content tables do not store duplicate text. v3 adds the
/// `story_lines_fts` index over `story_lines`.
Future<void> rebuildGamedataFts(Database db) async {
  await db.execute(
    "INSERT INTO entity_documents_fts(entity_documents_fts) VALUES('rebuild')",
  );
  await db.execute(
    "INSERT INTO lore_chunks_fts(lore_chunks_fts) VALUES('rebuild')",
  );
  await db.execute(
    "INSERT INTO story_lines_fts(story_lines_fts) VALUES('rebuild')",
  );
}
