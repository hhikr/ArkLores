// Re-runs the entry layer of an existing GameData database from a source
// directory: re-imports the entry tables, then rebuilds the derived layer
// (collections, story entries and their names, stage bindings) and the
// search index. Use it after a change to the entry importer to bring a
// database up to date without rebuilding the stories and vectors.
//
//   dart run tools/rederive_gamedata.dart \
//     --db=build/gamedata_v5/arklores_gamedata_zh.db \
//     --source=notes/src [--output=<new db>]   # default: <db>.rederived

import 'dart:io';

import 'package:arklores/core/gamedata/build/arknights_importer.dart';
import 'package:arklores/core/gamedata/build/entry_importer.dart';
import 'package:arklores/core/gamedata/build/gamedata_build_service.dart';
import 'package:arklores/core/gamedata/build/gamedata_schema.dart';
import 'package:arklores/core/gamedata/build/story_coverage_builder.dart';
import 'package:arklores/core/library/library_labels.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

String? _arg(List<String> args, String name) {
  for (final a in args) {
    if (a.startsWith('$name=')) return a.substring(name.length + 1);
  }
  return null;
}

Future<void> main(List<String> args) async {
  sqfliteFfiInit();
  final dbPath = _arg(args, '--db');
  final sourcePath = _arg(args, '--source');
  if (dbPath == null || sourcePath == null) {
    stderr.writeln('usage: dart run tools/rederive_gamedata.dart --db=<db> '
        '--source=<dir> [--output=<db>]');
    exitCode = 64;
    return;
  }
  final output = File(_arg(args, '--output') ?? '$dbPath.rederived').absolute;
  if (output.existsSync()) output.deleteSync();
  File(dbPath).absolute.copySync(output.path);

  final db = await databaseFactoryFfi.openDatabase(output.path);
  try {
    final stats = BuildStats();
    final importer = ArknightsImporter(
      sourceDir: Directory(sourcePath).absolute,
      db: db,
      stats: stats,
      storyLimit: 0,
    );
    // The script parser may have changed: stories whose lines differ from the
    // source are imported again (their vectors are dropped, see
    // deleteStoryRows; embed again with build_story_embeddings.dart).
    stdout.writeln('re-parse stories');
    final changed = await importer.reimportChangedStories();
    stdout.writeln('stories changed: ${changed.length}');
    if (changed.isNotEmpty) {
      stdout.writeln('rebuild coverage layer');
      await StoryCoverageBuilder(db: db, stats: stats).build();
    }
    final entries = importer.entryImporter;
    for (final path in EntryTables.all) {
      if (!entries.handles(path)) continue;
      stdout.writeln('re-import $path');
      await entries.importTable(path);
    }
    stdout.writeln('bind enemies to stages (level files)');
    await entries.importLevels();
    stdout.writeln('re-import character profiles');
    await importer.importCharacterTables();
    stdout.writeln('rebuild derived layer');
    await entries.rebuildDerived();
    stdout.writeln('rebuild search index');
    await rebuildGamedataFts(db);
    // Kinds of entries the interface has no name for: they show without a
    // heading until someone looks the name up (the tables rarely give it;
    // the wiki pages of the mode do).
    final unnamed = await db.rawQuery(
      'SELECT type, group_name, collection_id, COUNT(*) AS n FROM entries '
      "WHERE type LIKE 'roguelike%' AND group_name IS NOT NULL AND group_name <> '' "
      'GROUP BY 1, 2, 3 ORDER BY 3, 1, 2',
    );
    for (final r in unnamed) {
      if (groupLabel('${r['type']}', '${r['group_name']}') == null) {
        stdout.writeln('unnamed kind: ${r['collection_id']} ${r['type']} '
            '${r['group_name']} (${r['n']} entries)');
      }
    }
    await stats.refreshFrom(db);
    await writeGamedataManifest(db, {
      'built_at': DateTime.now().toUtc().toIso8601String(),
      ...countManifest(stats),
    });
  } finally {
    await db.close();
  }
  stdout.writeln('Wrote ${output.path}');
}
