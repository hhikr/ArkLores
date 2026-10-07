// 0.12: builds the Endfield knowledge base (`arklores_endfield_zh.db`) from a
// local unpack of the game client.
//
//   dart run tools/build_endfield_database.dart \
//     --tables=<dir with the decoded game tables, e.g. <kit>/export_full/game/Table> \
//     [--story=<the research kit's Story publication: <kit>/webui/data>] \
//     [--version=<client version>] \
//     --output=build/endfield [--force]
//
// The tables give the operator archives, the PRTS archive, enemy, weapon and
// item flavour text; the Story publication gives the conversations grouped
// by mission (without it, conversations are read from the dialog tables).
// See docs/GAMEDATA_BUILD_PIPELINE.md (Endfield) and
// docs/KNOWLEDGE_BASE_LESSONS.md.
import 'dart:convert';
import 'dart:io';

import 'package:arklores/core/gamedata/build/endfield/endfield_importer.dart';
import 'package:arklores/core/gamedata/build/endfield/endfield_stories.dart';
import 'package:arklores/core/gamedata/build/endfield/endfield_tables.dart';
import 'package:arklores/core/gamedata/build/endfield/endfield_writer.dart';
import 'package:arklores/core/gamedata/build/gamedata_db_validator.dart';
import 'package:arklores/core/gamedata/game.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> main(List<String> args) async {
  sqfliteFfiInit();
  String? arg(String name) {
    for (final a in args) {
      if (a.startsWith('--$name=')) return a.substring(name.length + 3);
    }
    return null;
  }

  final tablesDir = arg('tables');
  final output = arg('output') ?? 'build/endfield';
  if (tablesDir == null) {
    stderr.writeln('usage: --tables=<dir> [--story=<dir>] --output=<dir> [--force]');
    exit(64);
  }
  final out = Directory(p.absolute(output));
  if (await out.exists()) {
    if (!args.contains('--force')) {
      stderr.writeln('Output exists; use --force: $output');
      exit(1);
    }
    await out.delete(recursive: true);
  }
  await out.create(recursive: true);
  final dbPath = p.join(out.path, Game.endfield.dbFileName);
  final db = await databaseFactoryFfi.openDatabase(dbPath);
  final watch = Stopwatch()..start();
  void log(String m) => stdout.writeln('[${watch.elapsed.inSeconds}s] $m');
  try {
    final writer = EndfieldWriter(db);
    await writer.createSchema(sourceVersion: arg('version') ?? 'unknown');
    final tables = EndfieldTables(Directory(tablesDir));
    final importer = EndfieldImporter(tables, writer, log: log);
    await importer.importTables();
    final story = arg('story');
    final stories = EndfieldStoryImporter(tables, writer, importer, log: log);
    if (story != null && Directory(story).existsSync()) {
      await stories.importPublication(Directory(story));
    } else {
      await stories.importDialogTables();
    }
    log('derived layers');
    await writer.finish();
    await validateGameDataDatabase(db);
    final manifest = {
      for (final r in await db.query('gamedata_manifest'))
        '${r['key']}': '${r['value']}',
    };
    await File(p.join(out.path, 'gamedata_manifest.json')).writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'game': 'endfield',
        'database': {'fileName': '${Game.endfield.dbFileName}.gz'},
        'manifest': manifest,
      }),
    );
    log('done: $dbPath');
    log('story lines ${manifest['story_line_count']}, records '
        '${manifest['normalized_record_count']}, entities ${manifest['entity_count']}');
  } finally {
    await db.close();
  }
}
