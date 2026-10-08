/// Builds ArkLores GameData SQLite database from community unpack repositories.
///
/// Initial scope: Chinese Arknights data from Kengxxiao/ArknightsGameData.
///
/// The schema and the four-stage importer live in
/// `lib/core/gamedata/build/` so that the desktop release pipeline and the
/// in-app builder (R2) share the same build logic.
///
/// Usage:
///   dart run tools/build_gamedata_database.dart \
///     --arknights-source=/path/to/ArknightsGameData \
///     --output=build/gamedata \
///     --force
library;

import 'dart:convert';
import 'dart:io';

import 'package:arklores/core/gamedata/build/arknights_importer.dart';
import 'package:arklores/core/gamedata/build/gamedata_build_service.dart';
import 'package:arklores/core/gamedata/build/gamedata_schema.dart';
import 'package:arklores/core/gamedata/build/story_catalog_importer.dart';
import 'package:arklores/core/gamedata/build/story_coverage_builder.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> main(List<String> args) async {
  sqfliteFfiInit();
  final cfg = _Config.parse(args);

  final out = Directory(p.absolute(cfg.outputDir));
  if (await out.exists()) {
    if (!cfg.force) {
      stderr.writeln(
        'Output directory exists. Use --force to rebuild: ${cfg.outputDir}',
      );
      exit(1);
    }
    await out.delete(recursive: true);
  }
  await out.create(recursive: true);

  final dbPath = p.join(out.path, 'arklores_gamedata_zh.db');
  final db = await databaseFactoryFfi.openDatabase(dbPath);
  final stats = BuildStats();

  try {
    await createGamedataSchema(db);
    await writeGamedataManifest(
      db,
      {
        'schema_version': '$gamedataSchemaVersion',
        'language': gamedataLanguage,
        'source_arknights_repo': arknightsSourceRepoUrl,
        'source_arknights_branch': 'master',
        'source_arknights_commit': cfg.sourceCommit ?? await _gitCommit(cfg.arknightsSource),
        'built_at': DateTime.now().toUtc().toIso8601String(),
      },
    );

    final importer = ArknightsImporter(
      sourceDir: Directory(cfg.arknightsSource),
      db: db,
      stats: stats,
      storyLimit: cfg.storyLimit,
    );
    await importer.importAll();

    // Schema v3 coverage layer: entity mention runs, chapter profiles and
    // rare character bigrams (AI retrieval P0).
    await StoryCoverageBuilder(db: db, stats: stats).build();

    // R14: story names / order / official synopses (optional table).
    final catalog =
        await importStoryCatalog(db, Directory(cfg.arknightsSource));
    stdout.writeln(
      catalog == null
          ? 'Story catalog: skipped (no story_review_table.json)'
          : 'Story catalog: ${catalog.entries} entries, '
              '${catalog.withSynopsis} with synopsis, '
              '${catalog.matchedStories} matched story files',
    );

    // 0.11: owners, story entries and the bindings derived from them.
    await importer.entryImporter.rebuildDerived();

    await rebuildGamedataFts(db);
    await stats.refreshFrom(db);
    await writeGamedataManifest(db, countManifest(stats));
  } finally {
    await db.close();
  }

  final manifest = {
    'schemaVersion': gamedataSchemaVersion,
    'language': gamedataLanguage,
    'database': {
      'fileName': 'arklores_gamedata_zh.db.gz',
      'uncompressedFileName': 'arklores_gamedata_zh.db',
      'delivery': 'release-asset',
    },
    'sources': {
      'arknights': {
        'repo': arknightsSourceRepoUrl,
        'branch': 'master',
        'commit': cfg.sourceCommit ?? await _gitCommit(cfg.arknightsSource),
        'languagePath': 'zh_CN',
      },
    },
    'counts': stats.toJson(),
  };
  await File(p.join(out.path, 'gamedata_manifest.json')).writeAsString(
    const JsonEncoder.withIndent('  ').convert(manifest),
    flush: true,
  );
  await File(p.join(out.path, 'gamedata_build_report.json')).writeAsString(
    const JsonEncoder.withIndent('  ').convert({
      'status': 'ok',
      'database': dbPath,
      'counts': stats.toJson(),
    }),
    flush: true,
  );

  stdout.writeln('GameData DB built: $dbPath');
  stdout.writeln('Entities: ${stats.entities}');
  stdout.writeln('Entity documents: ${stats.entityDocuments}');
  stdout.writeln('Story lines: ${stats.storyLines}');
  stdout.writeln('Lore chunks: ${stats.loreChunks}');
  stdout.writeln('Coverage mentions: ${stats.storyCoverageMentions}');
  stdout.writeln('Chapter profiles: ${stats.storyProfiles}');
  stdout.writeln('Rare terms: ${stats.rareTerms}');
}

Future<String> _gitCommit(String path) async {
  final result = await Process.run(
    'git',
    ['-C', path, 'rev-parse', 'HEAD'],
  );
  if (result.exitCode != 0) return 'unknown';
  return (result.stdout as String).trim();
}

class _Config {
  const _Config({
    required this.arknightsSource,
    required this.outputDir,
    required this.force,
    required this.storyLimit,
    this.sourceCommit,
  });
  final String arknightsSource;

  /// Commit recorded in the manifest when the source is not a git checkout.
  final String? sourceCommit;
  final String outputDir;
  final bool force;
  final int storyLimit;

  static _Config parse(List<String> args) {
    String? arknightsSource;
    var outputDir = 'build/gamedata';
    var force = false;
    var storyLimit = 0;
    String? sourceCommit;

    for (final arg in args) {
      if (arg.startsWith('--arknights-source=')) {
        arknightsSource = arg.substring('--arknights-source='.length);
      } else if (arg.startsWith('--output=')) {
        outputDir = arg.substring('--output='.length);
      } else if (arg == '--force') {
        force = true;
      } else if (arg.startsWith('--source-commit=')) {
        sourceCommit = arg.substring('--source-commit='.length);
      } else if (arg.startsWith('--story-limit=')) {
        storyLimit = int.parse(arg.substring('--story-limit='.length));
      } else if (arg == '--help' || arg == '-h') {
        _printUsageAndExit();
      } else {
        stderr.writeln('Unknown argument: $arg');
        _printUsageAndExit(exitCode: 1);
      }
    }

    if (arknightsSource == null || arknightsSource.trim().isEmpty) {
      stderr.writeln('Missing --arknights-source');
      _printUsageAndExit(exitCode: 1);
    }

    return _Config(
      arknightsSource: arknightsSource,
      outputDir: outputDir,
      force: force,
      storyLimit: storyLimit,
      sourceCommit: sourceCommit,
    );
  }

  static Never _printUsageAndExit({int exitCode = 0}) {
    stdout.writeln('''
Usage:
  dart run tools/build_gamedata_database.dart \\
    --arknights-source=/path/to/ArknightsGameData \\
    --output=build/gamedata \\
    --force

Options:
  --story-limit=N  Import only N story txt files for smoke tests.
  --source-commit=SHA  Commit to record when the source is not a git checkout.
''');
    exit(exitCode);
  }
}
