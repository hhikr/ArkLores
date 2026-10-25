/// Shared GameData database validation, used by the installer (release asset
/// path) and the in-app builder (built DB path) so both reject the same
/// broken or incompatible databases.
library;

import 'package:sqflite_common/sqlite_api.dart';

import 'gamedata_schema.dart';

/// Validates an OPEN GameData database: the tables the app reads,
/// `schema_version` and the key row counts. Tables of earlier builds that
/// nothing reads (`obsoleteGamedataTables`) may or may not be there.
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
    // Schema v5 entry layer (0.11).
    'collections',
    'entries',
    'entry_links',
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

  final portraits = await db.rawQuery(
    "SELECT 1 FROM sqlite_master WHERE type='table' AND name='portrait_groups'",
  );
  if (portraits.isNotEmpty &&
      (await db.rawQuery('SELECT 1 FROM portrait_groups LIMIT 1')).isEmpty) {
    throw StateError('Downloaded GameData database has empty portrait_groups.');
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
