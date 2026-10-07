/// In-app GameData build service (R2): full rebuild and per-file incremental
/// update, sharing the exact importer/schema/coverage code with the desktop
/// release pipeline.
///
/// Design invariants:
///
/// - The currently installed database is never modified in place: incremental
///   updates copy it to a temp path first, and the caller swaps the validated
///   output over the installed file only at the end (`replaceInstalledDatabase`).
/// - SQLite access uses `databaseFactoryFfi` (pure FFI, bundled SQLite), so
///   the whole build can run inside a background isolate without platform
///   channels.
/// - Row ids are content-derived and stable, so re-imports are idempotent;
///   rows of changed source files are deleted by `source_path`/`story_id`
///   first, then re-imported per file. FTS and coverage layers are rebuilt
///   wholesale afterwards (deterministic, simple; per-row delta is a later
///   optimization).
library;

import 'dart:io';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../story_catalog.dart';
import 'arknights_importer.dart';
import 'entry_importer.dart';
import 'gamedata_db_validator.dart';
import 'gamedata_schema.dart';
import 'source/arknights_source_client.dart';
import 'story_catalog_importer.dart';
import 'story_coverage_builder.dart';
import 'update_report.dart';

/// Thrown when the user cancels a running build.
class GameDataBuildCancelledException implements Exception {
  const GameDataBuildCancelledException();
}

/// Options for one build/update run.
class GameDataBuildOptions {
  const GameDataBuildOptions({
    required this.sourceDir,
    required this.outputDbPath,
    required this.commitSha,
    this.existingDbPath,
    this.changedFiles = const [],
  });
  final String sourceDir;

  /// Temp path the built database is written to (never the installed file).
  final String outputDbPath;

  /// Source commit being built (recorded in the manifest).
  final String commitSha;

  /// Installed database path; when present with schema v3 and
  /// [changedFiles] non-empty, an incremental update is attempted.
  final String? existingDbPath;

  /// Importer-relevant source changes from the compare API.
  final List<SourceFileChange> changedFiles;
}

/// Result of a build/update run.
class GameDataBuildResult {
  const GameDataBuildResult({
    required this.outputDbPath,
    required this.incremental,
    required this.stats,
    this.report,
  });
  final String outputDbPath;
  final bool incremental;
  final BuildStats stats;

  /// What an incremental update changed (null for a full build).
  final UpdateReport? report;
}

/// Orchestrates full and incremental GameData builds.
class GameDataBuildService {
  /// Runs a build. Progress is reported as (stage, done, total); stages are
  /// `copy`, `profiles`, `voices`, `structured`, `stories`, `incremental`,
  /// `coverage`, `fts`. [shouldCancel] is polled between files/stages.
  Future<GameDataBuildResult> build(
    GameDataBuildOptions options, {
    void Function(String stage, int done, int total)? onProgress,
    bool Function()? shouldCancel,
  }) async {
    final existing = options.existingDbPath;
    final incremental = options.changedFiles.isNotEmpty &&
        existing != null &&
        await File(existing).exists() &&
        await _isSchemaV3(existing);
    if (!incremental) {
      return _fullBuild(
        Directory(options.sourceDir),
        options,
        onProgress: onProgress,
        shouldCancel: shouldCancel,
      );
    }
    return _incrementalBuild(
      Directory(options.sourceDir),
      existing,
      options,
      onProgress: onProgress,
      shouldCancel: shouldCancel,
    );
  }

  /// Swaps a validated built DB over the installed file. The installed DB is
  /// only replaced after the built one passed validation, so a failed build
  /// never destroys the working database.
  Future<void> replaceInstalledDatabase({
    required String builtPath,
    required String installPath,
  }) async {
    final built = File(builtPath);
    if (!await built.exists()) {
      throw StateError('Built database missing: $builtPath');
    }
    final target = File(installPath);
    if (await target.exists()) {
      await target.delete();
    }
    await built.rename(installPath);
    // The database is no longer the official asset the marker describes.
    final marker = File('$installPath.asset_sha256');
    if (await marker.exists()) await marker.delete();
  }

  Future<GameDataBuildResult> _fullBuild(
    Directory sourceDir,
    GameDataBuildOptions options, {
    void Function(String stage, int done, int total)? onProgress,
    bool Function()? shouldCancel,
  }) async {
    final db = await databaseFactoryFfi.openDatabase(options.outputDbPath);
    final stats = BuildStats();
    try {
      await createGamedataSchema(db);
      await writeGamedataManifest(db, {
        'schema_version': '$gamedataSchemaVersion',
        'language': gamedataLanguage,
        'source_arknights_repo': arknightsSourceRepoUrl,
        'source_arknights_branch': 'master',
        'source_arknights_commit': options.commitSha,
        'built_at': DateTime.now().toUtc().toIso8601String(),
      });
      final importer = ArknightsImporter(
        sourceDir: sourceDir,
        db: db,
        stats: stats,
        storyLimit: 0,
        onProgress: onProgress,
      );
      await importer.importAll();
      _checkCancel(shouldCancel);
      await StoryCoverageBuilder(
        db: db,
        stats: stats,
        onProgress: onProgress,
      ).build();
      await _refreshStoryCatalog(db, sourceDir);
      await importer.entryImporter.rebuildDerived();
      _checkCancel(shouldCancel);
      onProgress?.call('fts', 0, 1);
      await rebuildGamedataFts(db);
      onProgress?.call('fts', 1, 1);
      await stats.refreshFrom(db);
      await writeGamedataManifest(db, countManifest(stats));
    } finally {
      await db.close();
    }
    await validateGameDataDatabaseFile(options.outputDbPath);
    return GameDataBuildResult(
      outputDbPath: options.outputDbPath,
      incremental: false,
      stats: stats,
    );
  }

  Future<GameDataBuildResult> _incrementalBuild(
    Directory sourceDir,
    String existingPath,
    GameDataBuildOptions options, {
    void Function(String stage, int done, int total)? onProgress,
    bool Function()? shouldCancel,
  }) async {
    onProgress?.call('copy', 0, 1);
    await File(existingPath).copy(options.outputDbPath);
    onProgress?.call('copy', 1, 1);
    _checkCancel(shouldCancel);

    final db = await databaseFactoryFfi.openDatabase(options.outputDbPath);
    final stats = BuildStats();
    UpdateReport? report;
    try {
      final before = await DbSnapshot.take(db);
      final importer = ArknightsImporter(
        sourceDir: sourceDir,
        db: db,
        stats: stats,
        storyLimit: 0,
      );
      // Tables first (they define stages and owners), then level files
      // (they bind enemies to those stages), then stories.
      final changes = [...options.changedFiles]
        ..sort((a, b) => _order(a.path).compareTo(_order(b.path)));
      for (var i = 0; i < changes.length; i++) {
        _checkCancel(shouldCancel);
        onProgress?.call('incremental', i + 1, changes.length);
        await _applyChange(db, importer, changes[i]);
      }
      // A changed owner table (activities, zones, stages …) moves the owners
      // of the tables that read it, changed or not.
      final applied = {
        for (final c in changes)
          if (!c.isRemoval) c.path,
      };
      if (applied.any(EntryTables.contextTables.contains)) {
        // All entry tables in a complete build's order: the first table to
        // write an id keeps it, so the order decides.
        await importer.entryImporter.importAllTables();
      }
      await StoryCoverageBuilder(
        db: db,
        stats: stats,
        onProgress: onProgress,
      ).build();
      await _refreshStoryCatalog(db, sourceDir);
      await importer.entryImporter.rebuildDerived();
      _checkCancel(shouldCancel);
      onProgress?.call('fts', 0, 1);
      await rebuildGamedataFts(db);
      onProgress?.call('fts', 1, 1);
      await stats.refreshFrom(db);
      await writeGamedataManifest(db, {
        'source_arknights_commit': options.commitSha,
        'built_at': DateTime.now().toUtc().toIso8601String(),
        ...countManifest(stats),
      });
      report = UpdateReport.compute(
        before: before,
        after: await DbSnapshot.take(db),
        changes: changes,
      );
    } finally {
      await db.close();
    }
    await validateGameDataDatabaseFile(options.outputDbPath);
    return GameDataBuildResult(
      outputDbPath: options.outputDbPath,
      incremental: true,
      stats: stats,
      report: report,
    );
  }

  /// Order in which changed files are applied: data tables, level files,
  /// then story files.
  static int _order(String path) {
    if (ArknightsSourcePaths.isStoryFile(path)) return 2;
    if (ArknightsSourcePaths.isLevelFile(path)) return 1;
    return 0;
  }

  Future<void> _applyChange(
    Database db,
    ArknightsImporter importer,
    SourceFileChange change,
  ) async {
    final relevant = ArknightsSourcePaths.isImporterRelevant(change.path) ||
        (change.previousPath != null &&
            ArknightsSourcePaths.isImporterRelevant(change.previousPath!));
    if (!relevant) return;

    for (final stalePath in change.stalePaths) {
      if (ArknightsSourcePaths.isImporterRelevant(stalePath)) {
        await _deletePathRows(db, stalePath);
      }
    }
    if (change.isRemoval) return;

    final path = change.path;
    // R14: catalog sources are rebuilt wholesale after the per-file changes;
    // the [uc]info synopsis stubs are not story text and must never be
    // imported as a story.
    if (isStoryCatalogSource(path)) return;
    if (ArknightsSourcePaths.isStoryFile(path)) {
      await importer.importStoryFile(path);
    } else if (path == 'zh_CN/gamedata/excel/character_table.json') {
      await importer.importCharacterTables();
    } else if (path == 'zh_CN/gamedata/excel/char_meta_table.json') {
      await importer.importCharacterTables();
    } else if (path == 'zh_CN/gamedata/excel/handbook_info_table.json') {
      await importer.importCharacterTables();
      await importer.entryImporter.importTable(path);
    } else if (path == 'zh_CN/gamedata/excel/charword_table.json') {
      await importer.importVoiceTable();
    } else if (EntryTables.isLevelFile(path)) {
      await importer.entryImporter.importLevelFile(path);
    } else {
      await importer.entryImporter.importTable(path);
    }
  }

  Future<void> _deletePathRows(Database db, String path) async {
    if (isStoryCatalogSource(path)) return;
    if (ArknightsSourcePaths.isStoryFile(path)) {
      await deleteStoryRows(db, path);
    } else {
      await db.delete(
        'normalized_records',
        where: 'source_path = ?',
        whereArgs: [path],
      );
      await db.delete(
        'lore_chunks',
        where: 'source_path = ?',
        whereArgs: [path],
      );
      // Entry layer: the entries and bindings this file produced.
      await db.delete(
        'entries',
        where: 'source_path = ?',
        whereArgs: [path],
      );
      await db.delete(
        'entry_links',
        where: 'source_path = ?',
        whereArgs: [path],
      );
      // Aggregated operator documents reference both character tables in
      // their source_paths JSON; drop any document built from this path so
      // the re-import rebuilds it.
      await db.delete(
        'entity_documents',
        where: 'source_paths LIKE ?',
        whereArgs: ['%$path%'],
      );
    }
  }

  /// R14: rebuilds the optional story catalog from the source tree and
  /// relabels the chapter profiles (the coverage build rewrites them with
  /// file names). A source tree without the review table keeps the DB's
  /// existing catalog and only re-applies its labels.
  Future<void> _refreshStoryCatalog(Database db, Directory sourceDir) async {
    final result = await importStoryCatalog(db, sourceDir);
    if (result != null || !await hasStoryCatalog(db)) return;
    final rows = await db.query(storyCatalogTable);
    await applyStoryCatalogToProfiles(
      db,
      [for (final row in rows) StoryCatalogEntry.fromRow(row)],
    );
  }

  Future<bool> _isSchemaV3(String dbPath) async {
    Database? db;
    try {
      db = await databaseFactoryFfi.openDatabase(dbPath);
      final rows = await db.query('gamedata_manifest');
      for (final row in rows) {
        if (row['key'] == 'schema_version') {
          return '${row['value']}' == '$gamedataSchemaVersion';
        }
      }
      return false;
    } catch (_) {
      return false;
    } finally {
      await db?.close();
    }
  }

  void _checkCancel(bool Function()? shouldCancel) {
    if (shouldCancel != null && shouldCancel()) {
      throw const GameDataBuildCancelledException();
    }
  }
}

/// Validates a built database FILE (opens read-only via the FFI factory).
Future<void> validateGameDataDatabaseFile(String dbPath) async {
  final db = await databaseFactoryFfi.openDatabase(dbPath);
  try {
    await validateGameDataDatabase(db);
  } finally {
    await db.close();
  }
}

/// Manifest count keys derived from [stats] (shared with the CLI).
Map<String, String> countManifest(BuildStats stats) => {
      'entity_count': '${stats.entities}',
      'story_line_count': '${stats.storyLines}',
      'normalized_record_count': '${stats.normalizedRecords}',
      'entity_document_count': '${stats.entityDocuments}',
      'lore_chunk_count': '${stats.loreChunks}',
      'arknights_profile_chunk_count': '${stats.profileChunks}',
      'arknights_story_chunk_count': '${stats.storyChunks}',
      'arknights_structured_chunk_count': '${stats.structuredChunks}',
      'story_coverage_mention_count': '${stats.storyCoverageMentions}',
      'story_profile_count': '${stats.storyProfiles}',
      'rare_term_count': '${stats.rareTerms}',
    };
