/// R14: adds (or replaces) the optional `story_catalog` table of an existing
/// GameData DB in place, without a full rebuild (story lines, coverage and
/// the optional vectors are untouched; only the catalog table, the manifest
/// count and the chapter-profile titles/summaries change).
///
/// The source only needs `zh_CN/gamedata/excel/story_review_table.json` and
/// `zh_CN/gamedata/story/[uc]info/**`, e.g. a sparse checkout:
///
///   git clone --depth 1 --filter=blob:none --sparse --no-checkout \
///     https://github.com/Kengxxiao/ArknightsGameData.git agd
///   cd agd && git sparse-checkout set --no-cone \
///     "/zh_CN/gamedata/excel/story_review_table.json" \
///     "/zh_CN/gamedata/story/[[]uc]info/" && git checkout
///
/// Usage:
/// ```text
/// dart run tools/build_story_catalog.dart --db=<path.db> --source=<agd>
/// ```
library;

import 'dart:io';

import 'package:arklores/core/gamedata/build/story_catalog_importer.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> main(List<String> args) async {
  String? dbPath;
  String? source;
  for (final arg in args) {
    if (arg.startsWith('--db=')) dbPath = arg.substring(5);
    if (arg.startsWith('--source=')) source = arg.substring(9);
    if (arg == '--help' || arg == '-h') {
      stdout.writeln('dart run tools/build_story_catalog.dart --db=<db> --source=<ArknightsGameData>');
      return;
    }
  }
  if (dbPath == null || source == null) {
    stderr.writeln('Missing --db or --source (see --help).');
    exit(64);
  }
  if (!File(dbPath).existsSync()) {
    stderr.writeln('DB not found: $dbPath');
    exit(66);
  }
  sqfliteFfiInit();
  final db = await databaseFactoryFfi.openDatabase(File(dbPath).absolute.path);
  try {
    final result = await db.transaction(
      (txn) => importStoryCatalog(txn, Directory(source!)),
    );
    if (result == null) {
      stderr.writeln('story_review_table.json not found under $source');
      exit(66);
    }
    stdout.writeln('Story catalog: ${result.entries} entries, '
        '${result.withSynopsis} with synopsis, '
        '${result.matchedStories} matched story files.');
  } finally {
    await db.close();
  }
}
