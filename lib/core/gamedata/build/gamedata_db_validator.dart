/// Shared GameData database validation, used by the installer (release asset
/// path) and the in-app builder (built DB path) so both reject the same
/// broken or incompatible databases.
library;

import 'package:sqflite_common/sqlite_api.dart';

import 'gamedata_schema.dart';

/// Validates an OPEN GameData database: required tables (incl. the schema v3
/// coverage layer), `schema_version` and the key row counts.
///
/// Throws [StateError] with stable messages on any failure.
Future<void> validateGameDataDatabase(Database db) async {
  const requiredTables = {
    'gamedata_manifest',
    'entities',
    'entity_aliases',
    'entity_documents',
    'normalized_records',
    'story_lines',
    'story_scopes',
    'lore_chunks',
    'entity_documents_fts',
    'lore_chunks_fts',
    // Schema v3 coverage layer (R1 / AI retrieval P0).
    'entity_story_mentions',
    'story_chapter_profiles',
    'rare_terms',
    'story_lines_fts',
  };
  final tableRows = await db.rawQuery(
    '''
    SELECT name
    FROM sqlite_master
    WHERE type IN ('table', 'virtual') AND name IN (${List.filled(requiredTables.length, '?').join(',')})
    ''',
    requiredTables.toList(growable: false),
  );
  final presentTables = {
    for (final row in tableRows) '${row['name']}',
  };
  final missingTables = requiredTables.difference(presentTables);
  if (missingTables.isNotEmpty) {
    throw StateError(
      'Downloaded GameData database is missing required table(s): ${missingTables.join(', ')}',
    );
  }

  final manifest = {
    for (final row in await db.query('gamedata_manifest'))
      '${row['key']}': '${row['value']}',
  };
  final schemaVersion = manifest['schema_version'];
  if (schemaVersion == null || schemaVersion.trim().isEmpty) {
    throw StateError(
      'Downloaded GameData database manifest is missing schema_version.',
    );
  }
  if (schemaVersion != '$gamedataSchemaVersion') {
    throw StateError(
      'Downloaded GameData database schema_version $schemaVersion is incompatible; expected $gamedataSchemaVersion.',
    );
  }

  for (final entry in const {
    'entity_count': 'entities',
    'normalized_record_count': 'records',
    'lore_chunk_count': 'chunks',
    'story_line_count': 'story lines',
  }.entries) {
    final value = int.tryParse(manifest[entry.key] ?? '');
    if (value == null || value <= 0) {
      throw StateError(
        'Downloaded GameData database manifest has invalid ${entry.key} ${entry.value} count.',
      );
    }
  }
}
