// Prints what a GameData knowledge base holds that a reader could show:
// stories by scope type, catalog coverage, documents and records by type.
// 0.11 (library page) uses it to size the reading catalog; it only reads.
//
//   dart run tools/library_inventory.dart --db=<absolute path to .db>
import 'dart:io';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> main(List<String> args) async {
  final dbArg = args.firstWhere(
    (a) => a.startsWith('--db='),
    orElse: () => '',
  );
  if (dbArg.isEmpty) {
    stderr.writeln('usage: dart run tools/library_inventory.dart --db=<path>');
    exitCode = 64;
    return;
  }
  sqfliteFfiInit();
  final db = await databaseFactoryFfi.openDatabase(
    File(dbArg.substring('--db='.length)).absolute.path,
    options: OpenDatabaseOptions(readOnly: true),
  );
  try {
    final tables = (await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name",
    ))
        .map((r) => r['name'] as String)
        .toSet();

    Future<void> section(String title, String sql) async {
      stdout.writeln('\n## $title');
      final rows = await db.rawQuery(sql);
      for (final row in rows) {
        stdout.writeln('  ${row.values.join(' | ')}');
      }
    }

    await section(
      'manifest',
      'SELECT key, substr(value, 1, 80) FROM gamedata_manifest ORDER BY key',
    );
    await section(
      'stories by scope type (scope_type | scopes | stories | lines | chars)',
      '''
      SELECT s.scope_type, COUNT(DISTINCT s.scope_id), COUNT(DISTINCT s.story_id),
             SUM(l.n), SUM(l.chars)
      FROM story_scopes s
      LEFT JOIN (SELECT story_id, COUNT(*) n, SUM(length(content)) chars
                 FROM story_lines GROUP BY story_id) l ON l.story_id = s.story_id
      GROUP BY s.scope_type ORDER BY 3 DESC
      ''',
    );
    await section(
      'obt scopes (scope_id | stories | lines)',
      '''
      SELECT s.scope_id, COUNT(*), SUM(l.n)
      FROM story_scopes s
      LEFT JOIN (SELECT story_id, COUNT(*) n FROM story_lines GROUP BY story_id) l
        ON l.story_id = s.story_id
      WHERE s.scope_type = 'obt' GROUP BY 1 ORDER BY 2 DESC
      ''',
    );
    await section(
      'stories with lines but no scope',
      '''
      SELECT COUNT(DISTINCT story_id) FROM story_lines
      WHERE story_id NOT IN (SELECT story_id FROM story_scopes)
      ''',
    );
    if (tables.contains('story_catalog')) {
      final cols = (await db.rawQuery('PRAGMA table_info(story_catalog)'))
          .map((r) => r['name'] as String)
          .toList();
      stdout.writeln('\n## story_catalog columns: ${cols.join(', ')}');
      // `start_time` arrived in R15; R14 catalogs lack it.
      final startTime = cols.contains('start_time')
          ? 'SUM(CASE WHEN start_time IS NOT NULL THEN 1 ELSE 0 END)'
          : "'-'";
      await section(
        'stories by scope type not in story_catalog',
        '''
        SELECT s.scope_type, COUNT(*) FROM story_scopes s
        WHERE s.story_id NOT IN (SELECT story_id FROM story_catalog)
        GROUP BY s.scope_type ORDER BY 2 DESC
        ''',
      );
      await section(
        'story_catalog by collection type '
            '(type | collections | stories | with synopsis | with start_time)',
        '''
        SELECT collection_type, COUNT(DISTINCT collection_id), COUNT(*),
               SUM(CASE WHEN ifnull(synopsis, '') <> '' THEN 1 ELSE 0 END),
               $startTime
        FROM story_catalog GROUP BY 1 ORDER BY 3 DESC
        ''',
      );
      await section(
        'stories not in story_catalog by scope (scope_id | stories)',
        '''
        SELECT s.scope_id, COUNT(*) FROM story_scopes s
        WHERE s.story_id NOT IN (SELECT story_id FROM story_catalog)
        GROUP BY 1 ORDER BY 2 DESC LIMIT 20
        ''',
      );
    } else {
      stdout.writeln('\n## story_catalog: absent');
    }
    await section(
      'entity_documents (entity_type | document_type | docs | chars)',
      '''
      SELECT entity_type, document_type, COUNT(*), SUM(length(content))
      FROM entity_documents GROUP BY 1, 2 ORDER BY 3 DESC
      ''',
    );
    await section(
      'normalized_records (category | subtype | content_type | rows | entities | chars)',
      '''
      SELECT category, subtype, content_type, COUNT(*), COUNT(DISTINCT entity_id),
             SUM(length(content))
      FROM normalized_records GROUP BY 1, 2, 3 ORDER BY 4 DESC
      ''',
    );
    await section(
      'entities by type',
      'SELECT entity_type, COUNT(*) FROM entities GROUP BY 1 ORDER BY 2 DESC',
    );
  } finally {
    await db.close();
  }
}
