/// R14: builds the optional `story_catalog` table from a source checkout
/// (`excel/story_review_table.json` + `story/[uc]info/**`). Shared by the
/// full build, the incremental build and `tools/build_story_catalog.dart`.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite_common/sqlite_api.dart';

import '../story_catalog.dart';

/// Outcome of a catalog import.
class StoryCatalogImportResult {
  const StoryCatalogImportResult({
    required this.entries,
    required this.withSynopsis,
    required this.matchedStories,
  });

  /// Catalog rows written.
  final int entries;

  /// Rows that have an official synopsis.
  final int withSynopsis;

  /// Rows whose story id exists in `story_lines` (the rest are listed in the
  /// review table but absent from the text dump; kept for completeness).
  final int matchedStories;
}

/// Imports the catalog from [sourceDir] (the directory holding `zh_CN/`).
/// Returns null without touching the DB when the review table is missing
/// (older source trees), so an existing catalog is kept.
Future<StoryCatalogImportResult?> importStoryCatalog(
  DatabaseExecutor db,
  Directory sourceDir,
) async {
  final tableFile = File(p.join(sourceDir.path, storyReviewTablePath));
  if (!await tableFile.exists()) return null;
  final table = decodeStoryReviewTable(await tableFile.readAsString());
  final entries = parseStoryReviewTable(table, (storyInfo) {
    final file = File(p.joinAll([sourceDir.path, ...synopsisPathFor(storyInfo).split('/')]));
    return file.existsSync() ? file.readAsStringSync() : null;
  });
  await writeStoryCatalog(db, entries);
  final matched = await db.rawQuery(
    'SELECT COUNT(*) AS n FROM $storyCatalogTable c '
    'WHERE EXISTS (SELECT 1 FROM story_scopes s WHERE s.story_id = c.story_id)',
  );
  return StoryCatalogImportResult(
    entries: entries.length,
    withSynopsis: entries.where((e) => (e.synopsis ?? '').isNotEmpty).length,
    matchedStories: (matched.first['n'] as num).toInt(),
  );
}

/// Whether a changed source path feeds the catalog (incremental builds
/// rebuild the whole catalog for these instead of importing a story file).
bool isStoryCatalogSource(String path) =>
    path == storyReviewTablePath || path.startsWith('$storyInfoRoot/');
