// Updates an installed GameData database to the latest upstream commit,
// incrementally, and brings its story vectors up to date. The same code the
// app runs (`SourceSync`, `GameDataBuildService`, `updateStoryVectors`).
//
//   dart run tools/update_gamedata.dart \
//     --db=build/gamedata_v5/arklores_gamedata_zh.db \
//     --source=notes/src            # a directory with zh_CN/gamedata/{excel,story[,levels]}
//     [--output=<new db>]           # default: <db>.updated
//     [--replace]                   # move the updated db over --db (old kept as .previous)
//     [--embed]                     # embed the missing story vectors (costs money)
//     [--vectors-only]              # skip the data update, only plan/embed vectors
//
// Without --embed the vector step only prints what it would embed (chunks,
// tokens, estimated cost). The GitHub token is read from the gitignored
// tools/github_pat or $GITHUB_TOKEN and never printed; the embedding key from
// the gitignored tools/embedding-apiKey.csv.
//
// The source directory is brought up to date from the compare of the
// installed and the latest commit: changed story/table/level files plus any
// context table it lacks. Level files are only followed when the directory
// already has them (a first copy of `levels/` is ~500 MB; see
// docs/GAMEDATA_BUILD_PIPELINE.md).

import 'dart:io';

import 'package:arklores/core/gamedata/build/gamedata_build_service.dart';
import 'package:arklores/core/gamedata/build/gamedata_schema.dart';
import 'package:arklores/core/gamedata/build/source/arknights_source_client.dart';
import 'package:arklores/core/gamedata/build/source/source_sync.dart';
import 'package:arklores/core/gamedata/story_vector_updater.dart';
import 'package:arklores/core/llm/embedding_client.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> main(List<String> args) async {
  sqfliteFfiInit();
  final dbPath = _arg(args, '--db');
  if (dbPath == null) {
    stderr.writeln('usage: dart run tools/update_gamedata.dart --db=<db> '
        '--source=<dir> [--output=<db>] [--replace] [--embed] [--vectors-only]');
    exitCode = 64;
    return;
  }
  final dbFile = File(dbPath).absolute;
  if (!dbFile.existsSync()) {
    stderr.writeln('database not found: ${dbFile.path}');
    exitCode = 2;
    return;
  }
  var workingDb = dbFile.path;

  if (!args.contains('--vectors-only')) {
    final sourcePath = _arg(args, '--source');
    if (sourcePath == null) {
      stderr.writeln('--source=<dir> is required for a data update');
      exitCode = 64;
      return;
    }
    final updated = await _updateData(
      dbFile: dbFile,
      sourceDir: Directory(sourcePath).absolute,
      outputPath: _arg(args, '--output') ?? '${dbFile.path}.updated',
    );
    if (updated == null) {
      stdout.writeln('The database is up to date.');
    } else {
      workingDb = updated;
    }
  }

  await _vectors(
    workingDb,
    embed: args.contains('--embed'),
    model: _arg(args, '--model'),
  );

  if (args.contains('--replace') && workingDb != dbFile.path) {
    final previous = File('${dbFile.path}.previous');
    if (previous.existsSync()) previous.deleteSync();
    dbFile.renameSync(previous.path);
    File(workingDb).renameSync(dbFile.path);
    stdout.writeln('Replaced ${dbFile.path} (old kept as ${previous.path}).');
  } else if (workingDb != dbFile.path) {
    stdout.writeln('Updated database: $workingDb');
  }
}

/// Runs the incremental data update. Returns the new database path, or null
/// when nothing relevant changed.
Future<String?> _updateData({
  required File dbFile,
  required Directory sourceDir,
  required String outputPath,
}) async {
  final manifest = await _manifest(dbFile.path);
  final installed = manifest['source_arknights_commit'];
  if (manifest['schema_version'] != '$gamedataSchemaVersion' ||
      installed == null ||
      installed.length < 7) {
    throw StateError(
      'Only a schema $gamedataSchemaVersion database can be updated '
      'incrementally (this one: ${manifest['schema_version']}); '
      'build it completely with tools/build_gamedata_database.dart.',
    );
  }
  final client = ArknightsSourceClient(githubToken: _githubToken());
  final latest = await client.fetchLatestCommit();
  stdout.writeln('Installed ${_short(installed)} -> latest ${_short(latest)}');
  if (latest == installed) return null;

  final sync = SourceSync(client: client, sourceDir: sourceDir);
  final result = await sync.sync(
    installedSha: installed,
    latestSha: latest,
    onProgress: (stage, done, total) {
      if (total > 0 && (done == total || done % 25 == 0)) {
        stdout.writeln('  ${stage.name}: $done/$total');
      }
    },
  );
  final summary = result.summary;
  stdout.writeln(
    'Changes: ${summary.storyFiles} story files, ${summary.tables.length} '
    'tables, ${summary.levelFiles} level files '
    '(${result.contextTablesDownloaded} context tables downloaded).',
  );
  if (result.upToDate) {
    // Upstream moved but nothing concerns the database.
    return null;
  }
  // Level files are only applied where the directory has the `levels/` tree
  // (the importer needs none of the unchanged ones, but a first copy of the
  // tree is what lets a *new* stage get its enemies).
  final output = File(outputPath);
  if (output.existsSync()) output.deleteSync();
  final built = await GameDataBuildService().build(
    GameDataBuildOptions(
      sourceDir: sourceDir.path,
      outputDbPath: output.path,
      existingDbPath: dbFile.path,
      commitSha: latest,
      changedFiles: result.changes,
    ),
    onProgress: (stage, done, total) {
      if (total > 0 && (done == total || done % 50 == 0)) {
        stdout.writeln('  build $stage: $done/$total');
      }
    },
  );
  await sync.markSynced(latest);
  stdout.writeln('\nWhat changed:\n${built.report?.describe() ?? '(full build)'}');
  return built.outputDbPath;
}

/// Prints what the vector step would do and, with [embed], does it.
Future<void> _vectors(
  String dbPath, {
  required bool embed,
  String? model,
}) async {
  final db = await databaseFactoryFfi.openDatabase(dbPath);
  try {
    final plan = await planVectorUpdate(db);
    stdout.writeln('\nStory vectors: ${plan.existingVectors} existing '
        '(${plan.storiesWithVectors} stories'
        '${plan.model == null ? '' : ', ${plan.model}@${plan.dims}'}).');
    if (plan.nothingToDo) {
      stdout.writeln('Every story has vectors.');
      return;
    }
    stdout.writeln(
      'To embed: ${plan.pendingStories} stories, ~${plan.pendingChunks} chunks, '
      '~${plan.pendingChars} chars, ~${plan.estimatedTokens} tokens, '
      '~¥${plan.estimatedYuan().toStringAsFixed(3)} at Bailian\'s price '
      '(an estimate; your bill decides).',
    );
    if (plan.isFirstBuild) {
      stdout.writeln('This is a first, complete vector build.');
    }
    if (!embed) {
      stdout.writeln('Not embedding (pass --embed to do it).');
      return;
    }
    final config = _embeddingConfig(model);
    if (!config.isValid) {
      stderr.writeln('No embedding configuration '
          '(tools/embedding-apiKey.csv with openAiCompatible and apiKey).');
      exitCode = 2;
      return;
    }
    final client = OpenAICompatibleEmbeddingClient(config: config);
    try {
      final stopwatch = Stopwatch()..start();
      final result = await updateStoryVectors(
        db: db,
        client: client,
        onProgress: (done, total, chunks) {
          if (done % 100 == 0 || done == total) {
            stdout.writeln('  embedded $done/$total stories ($chunks chunks)');
          }
        },
      );
      stdout.writeln('Wrote ${result.chunks} vectors for ${result.stories} '
          'stories; the provider counted ${result.tokensUsed} tokens '
          '(${stopwatch.elapsed.inSeconds}s).');
    } finally {
      client.dispose();
    }
  } finally {
    await db.close();
  }
}

Future<Map<String, String>> _manifest(String dbPath) async {
  final db = await databaseFactoryFfi.openDatabase(
    dbPath,
    options: OpenDatabaseOptions(readOnly: true),
  );
  try {
    return {
      for (final r in await db.rawQuery('SELECT key, value FROM gamedata_manifest'))
        '${r['key']}': '${r['value']}',
    };
  } finally {
    await db.close();
  }
}

String? _githubToken() {
  final fromEnv = Platform.environment['GITHUB_TOKEN'];
  if (fromEnv != null && fromEnv.trim().isNotEmpty) return fromEnv.trim();
  final file = File(p.join('tools', 'github_pat'));
  return file.existsSync() ? file.readAsStringSync().trim() : null;
}

EmbeddingConfig _embeddingConfig(String? model) {
  final file = File(p.join('tools', 'embedding-apiKey.csv'));
  final csv = <String, String>{
    if (file.existsSync())
      for (final line in file.readAsLinesSync())
        if (line.contains(','))
          line.substring(0, line.indexOf(',')).trim():
              line.substring(line.indexOf(',') + 1).trim(),
  };
  return EmbeddingConfig(
    baseUrl: csv['openAiCompatible'] ?? '',
    apiKey: csv['apiKey'] ?? '',
    model: model ?? defaultEmbeddingConfig.model,
  );
}

String _short(String sha) => sha.length <= 7 ? sha : sha.substring(0, 7);

String? _arg(List<String> args, String name) {
  for (final a in args) {
    if (a.startsWith('$name=')) return a.substring(name.length + 1);
  }
  return null;
}
