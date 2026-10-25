import 'dart:io';

import 'package:arklores/core/gamedata/build/portrait_index.dart';
import 'package:arklores/core/gamedata/build/story_script.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> main(List<String> args) async {
  final options = <String, String>{};
  for (final arg in args) {
    final split = arg.indexOf('=');
    if (split > 0) options[arg.substring(0, split)] = arg.substring(split + 1);
  }
  if (args.contains('--help') ||
      !options.containsKey('--db') ||
      !options.containsKey('--source')) {
    stdout.writeln(
      'dart run tools/build_portrait_index.dart --db=<db> --source=<ArknightsGameData>',
    );
    if (!args.contains('--help')) exitCode = 64;
    return;
  }
  final file = File(options['--db']!);
  final root =
      Directory(p.join(options['--source']!, 'zh_CN', 'gamedata', 'story'));
  if (!file.existsSync() || !root.existsSync()) {
    stderr.writeln('Database or story source directory does not exist.');
    exitCode = 66;
    return;
  }
  final files = await root
      .list(recursive: true)
      .where(
        (f) =>
            f is File &&
            f.path.endsWith('.txt') &&
            !p
                .relative(f.path, from: root.path)
                .startsWith('[uc]info${p.separator}'),
      )
      .cast<File>()
      .toList();
  files.sort((a, b) => a.path.compareTo(b.path));
  sqfliteFfiInit();
  final db = await databaseFactoryFfi.openDatabase(file.absolute.path);
  try {
    var written = 0;
    final skipped = <String>[];
    await db.transaction((txn) async {
      await ensurePortraitTables(txn);
      for (final file in files) {
        final id =
            p.relative(file.path, from: root.path).replaceAll(p.separator, '/');
        final lines = parseStoryScript(await file.readAsString());
        final stored = await txn.query(
          'story_lines',
          columns: ['line_index', 'kind', 'speaker', 'content'],
          where: 'story_id=?',
          whereArgs: [id],
          orderBy: 'line_index',
        );
        String? reason;
        if (stored.isEmpty) {
          reason = 'story absent or empty';
        } else if (stored.length != lines.length) {
          reason = 'line count ${stored.length} != ${lines.length}';
        } else {
          for (var i = 0; i < lines.length; i++) {
            final row = stored[i];
            final line = lines[i];
            if (row['kind'] != line.kind.value ||
                row['speaker'] != line.speaker ||
                row['content'] != line.content) {
              reason = 'text differs at line ${row['line_index']}';
              break;
            }
          }
        }
        if (reason != null) {
          skipped.add('$id: $reason');
          continue;
        }
        await deletePortraitRows(txn, id);
        final batch = txn.batch();
        for (var i = 0; i < lines.length; i++) {
          if (lines[i].portrait != null) {
            batch.insert(storyLinePortraitsTable, {
              'story_id': id,
              'line_index': stored[i]['line_index'],
              'sprite': lines[i].portrait,
            });
          }
        }
        await batch.commit(noResult: true);
        written++;
      }
    });
    await rebuildPortraitIndex(db);
    stdout.writeln('Stories total: ${files.length}');
    stdout.writeln('Stories written: $written');
    stdout.writeln('Stories skipped: ${skipped.length}');
    for (final skip in skipped.take(20)) {
      stdout.writeln('  $skip');
    }
    for (final table in [
      storyLinePortraitsTable,
      portraitSpritesTable,
      portraitGroupsTable,
      speakerPortraitsTable,
      speakerNamesTable,
    ]) {
      final exists = await db.rawQuery(
        "SELECT 1 FROM sqlite_master WHERE type='table' AND name=?",
        [table],
      );
      final count = exists.isEmpty
          ? 0
          : (await db.rawQuery('SELECT COUNT(*) AS n FROM $table')).single['n'];
      stdout.writeln('$table: $count');
    }
  } finally {
    await db.close();
  }
}
