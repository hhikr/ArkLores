// Removes from an existing GameData database what earlier builds wrote and
// nothing reads (`dropObsoleteGamedataData`: the chunked copy of the text,
// the full-text indexes, the tables derived from the story text, the story
// text kept a second time as records, the entities made of speakers' names),
// then compacts the file. The same step an update in the app runs; the
// vectors and everything the app reads stay as they are.
//
//   dart run tools/compact_gamedata.dart --db=<db> [--output=<new db>]
//   # default output: <db>.compact
import 'dart:io';

import 'package:arklores/core/gamedata/build/gamedata_build_service.dart';
import 'package:arklores/core/gamedata/build/gamedata_schema.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> main(List<String> args) async {
  sqfliteFfiInit();
  String? arg(String name) {
    for (final a in args) {
      if (a.startsWith('$name=')) return a.substring(name.length + 1);
    }
    return null;
  }

  final dbPath = arg('--db');
  if (dbPath == null) {
    stderr.writeln(
      'usage: dart run tools/compact_gamedata.dart --db=<db> [--output=<db>]',
    );
    exitCode = 64;
    return;
  }
  final source = File(dbPath).absolute;
  final output = File(arg('--output') ?? '$dbPath.compact').absolute;
  if (output.existsSync()) output.deleteSync();
  source.copySync(output.path);

  final db = await databaseFactoryFfi.openDatabase(output.path);
  try {
    if (await dropObsoleteGamedataData(db)) {
      // The counts the manifest keeps (records, entities) changed.
      Future<String> count(String table) async =>
          '${(await db.rawQuery('SELECT COUNT(*) AS n FROM $table')).first['n']}';
      await writeGamedataManifest(db, {
        'entity_count': await count('entities'),
        'normalized_record_count': await count('normalized_records'),
      });
      await db.execute('VACUUM');
    } else {
      stdout.writeln('nothing to remove');
    }
  } finally {
    await db.close();
  }
  await validateGameDataDatabaseFile(output.path);
  String mb(File f) => (f.lengthSync() / (1024 * 1024)).toStringAsFixed(1);
  stdout.writeln('${mb(source)} MB -> ${mb(output)} MB: ${output.path}');
}
