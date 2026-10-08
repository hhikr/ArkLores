/// In-app GameData build orchestration (R2): source pull (first-time zip or
/// incremental raw downloads), background-isolate build, validation and swap.
library;

import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../background/background_work.dart';
import 'build/gamedata_build_isolate.dart';
import 'build/gamedata_build_service.dart';
import 'build/gamedata_schema.dart';
import 'build/source/arknights_source_client.dart';
import 'build/source/source_sync.dart';
import 'build/update_report.dart';
import 'gamedata_installer.dart';
import 'gamedata_provider.dart';

/// High-level build phases shown in the UI.
enum GameDataBuildPhase { idle, checking, downloading, extracting, building, swapping, done }

/// UI state of the in-app build flow.
class GameDataBuildUiState {
  const GameDataBuildUiState({
    required this.phase,
    this.stage = '',
    this.done = 0,
    this.total = 0,
    this.latestCommit,
    this.installedCommit,
    this.changedFileCount,
    this.incremental = false,
    this.error,
    this.changeSummary,
    this.report,
    this.noRelevantChanges = false,
  });
  final GameDataBuildPhase phase;
  final String stage;
  final int done;
  final int total;
  final String? latestCommit;
  final String? installedCommit;
  final int? changedFileCount;
  final bool incremental;
  final String? error;

  /// What the last update check found, by kind of file.
  final SourceChangeSummary? changeSummary;

  /// What the last incremental update changed.
  final UpdateReport? report;

  /// The last check or update found nothing that concerns the knowledge base.
  final bool noRelevantChanges;

  bool get busy =>
      phase == GameDataBuildPhase.checking ||
      phase == GameDataBuildPhase.downloading ||
      phase == GameDataBuildPhase.extracting ||
      phase == GameDataBuildPhase.building ||
      phase == GameDataBuildPhase.swapping;

  GameDataBuildUiState copyWith({
    GameDataBuildPhase? phase,
    String? stage,
    int? done,
    int? total,
    String? latestCommit,
    String? installedCommit,
    int? changedFileCount,
    bool? incremental,
    String? error,
    SourceChangeSummary? changeSummary,
    UpdateReport? report,
    bool? noRelevantChanges,
    bool clearReport = false,
  }) {
    return GameDataBuildUiState(
      phase: phase ?? this.phase,
      stage: stage ?? this.stage,
      done: done ?? this.done,
      total: total ?? this.total,
      latestCommit: latestCommit ?? this.latestCommit,
      installedCommit: installedCommit ?? this.installedCommit,
      changedFileCount: changedFileCount ?? this.changedFileCount,
      incremental: incremental ?? this.incremental,
      error: error ?? this.error,
      changeSummary: changeSummary ?? this.changeSummary,
      report: clearReport ? null : (report ?? this.report),
      noRelevantChanges: noRelevantChanges ?? this.noRelevantChanges,
    );
  }
}

final gameDataBuildProvider =
    StateNotifierProvider<GameDataBuildNotifier, GameDataBuildUiState>((ref) {
  return GameDataBuildNotifier(
    onInstalled: () => ref.invalidate(gameDataInstallStatusProvider),
  );
});

/// Extracts the whitelisted source subset in a background isolate.
///
/// Kept as a TOP-LEVEL function on purpose: closures created inside the
/// notifier (e.g. `onProgress` callbacks) capture `this`, and Dart may share
/// one closure-context object across closures of the same method (especially
/// under AOT), so an in-method `Isolate.run` closure can drag the whole
/// notifier — including its `onInstalled` callback, which captures the
/// riverpod `ref` and therefore the provider dependency graph with its
/// futures — into the isolate message, failing with "object is unsendable"
/// (see dart-lang/sdk#59866). This function's closure captures only plain
/// strings and nothing else.
Future<void> extractWhitelistedSourceInIsolate(
  String zipPath,
  String sourceDirPath,
) async {
  await Isolate.run(
    () => ArknightsSourceClient.extractWhitelistedZip(
      zipPath: zipPath,
      outputDir: Directory(sourceDirPath),
    ),
  );
}

class GameDataBuildNotifier extends StateNotifier<GameDataBuildUiState> {
  GameDataBuildNotifier({required this.onInstalled})
      : super(const GameDataBuildUiState(phase: GameDataBuildPhase.idle));
  final void Function() onInstalled;

  GameDataBuildRunner? _runner;
  String? _outputDbPath;

  Future<void> checkForUpdates({String? githubToken}) async {
    if (state.busy) return;
    state = state.copyWith(phase: GameDataBuildPhase.checking, error: null);
    try {
      final client = ArknightsSourceClient(githubToken: githubToken);
      final latest = await client.fetchLatestCommit();
      final installed = await _installedCommit();
      final changes = installed == null || installed == latest
          ? const <SourceFileChange>[]
          : await client.compareCommits(baseSha: installed, headSha: latest);
      final summary = SourceChangeSummary.of(changes);
      state = state.copyWith(
        phase: GameDataBuildPhase.idle,
        latestCommit: latest,
        installedCommit: installed,
        changedFileCount: changes.length,
        changeSummary: summary,
        noRelevantChanges: installed != null && summary.isEmpty,
      );
    } on GameDataSourceTooManyChangesException {
      // Not an error: the update becomes a full rebuild.
      state = state.copyWith(
        phase: GameDataBuildPhase.idle,
        changedFileCount: -1,
      );
    } catch (error) {
      state = state.copyWith(
        phase: GameDataBuildPhase.idle,
        error: 'check: $error',
      );
    }
  }

  /// Pulls source (incremental or first-time zip) and builds/updates the
  /// knowledge base in a background isolate, then swaps the validated output
  /// over the installed database.
  Future<void> buildFromSource({String? githubToken}) =>
      BackgroundWork.instance.run(
        BackgroundWork.text('正在构建知识库', 'Building the knowledge base'),
        () => _buildFromSource(githubToken: githubToken),
      );

  Future<void> _buildFromSource({String? githubToken}) async {
    if (state.busy) return;
    final dirs = await _dirs();
    await dirs.sourceDir.create(recursive: true);
    await dirs.tmpDir.create(recursive: true);
    final outputDbPath = p.join(
      dirs.tmpDir.path,
      'build_${DateTime.now().millisecondsSinceEpoch}.db',
    );
    _outputDbPath = outputDbPath;

    final client = ArknightsSourceClient(githubToken: githubToken);
    var changes = const <SourceFileChange>[];
    try {
      final latest = state.latestCommit ?? await client.fetchLatestCommit();
      final installed = await _installedCommit();
      final installedSchema = await _installedSchema();
      final sync = SourceSync(client: client, sourceDir: dirs.sourceDir);
      // An installed database of the current schema is updated from the
      // changed files only. Anything else (nothing installed, an older
      // schema) is built from the whole source.
      var incrementalOk = installed != null &&
          installedSchema == '$gamedataSchemaVersion';

      if (incrementalOk) {
        if (installed == latest) {
          state = state.copyWith(
            phase: GameDataBuildPhase.idle,
            noRelevantChanges: true,
          );
          return;
        }
        state = state.copyWith(
          phase: GameDataBuildPhase.downloading,
          stage: 'incremental',
          done: 0,
          total: 0,
          error: null,
          clearReport: true,
          noRelevantChanges: false,
        );
        try {
          final result = await sync.sync(
            installedSha: installed,
            latestSha: latest,
            onProgress: (stage, done, total) {
              state = state.copyWith(
                phase: GameDataBuildPhase.downloading,
                stage: stage == SourceSyncStage.contextTables
                    ? 'context'
                    : 'incremental',
                done: done,
                total: total,
              );
            },
          );
          changes = result.changes;
        } on GameDataSourceTooManyChangesException {
          // More than the compare API lists: a complete rebuild is the only
          // correct update.
          incrementalOk = false;
        }
        if (incrementalOk && changes.isEmpty) {
          // Upstream moved, but nothing that concerns the knowledge base.
          state = state.copyWith(
            phase: GameDataBuildPhase.idle,
            noRelevantChanges: true,
          );
          return;
        }
      }
      if (!incrementalOk) {
        // First-time (or complete) pull: one zip download and a
        // whitelist-filtered extraction.
        state = state.copyWith(
          phase: GameDataBuildPhase.downloading,
          stage: 'zip',
          error: null,
          clearReport: true,
        );
        final zh = Directory(p.join(dirs.sourceDir.path, 'zh_CN'));
        if (await zh.exists()) await zh.delete(recursive: true);
        await _pullFullSource(client, latest, dirs);
        changes = const <SourceFileChange>[];
      }

      // Background build.
      state = state.copyWith(
        phase: GameDataBuildPhase.building,
        stage: 'start',
        done: 0,
        total: 0,
        incremental: changes.isNotEmpty,
      );
      final runner = GameDataBuildRunner();
      _runner = runner;
      final completer = Completer<void>();
      late final StreamSubscription<GameDataBuildEvent> sub;
      sub = runner.events.listen(
        (event) async {
          try {
            switch (event.type) {
              case GameDataBuildEventType.progress:
                state = state.copyWith(
                  phase: GameDataBuildPhase.building,
                  stage: event.stage,
                  done: event.done,
                  total: event.total,
                );
              case GameDataBuildEventType.done:
                await _swapInBuiltDatabase(event, dirs.installPath);
                // The source directory now matches the installed database.
                await sync.markSynced(latest);
                if (!incrementalOk) {
                  // A complete build read the level files (500 MB); keep
                  // the disk free, an update fetches the ones that change.
                  final levels = Directory(
                    p.join(dirs.sourceDir.path, 'zh_CN', 'gamedata', 'levels'),
                  );
                  try {
                    if (await levels.exists()) {
                      await levels.delete(recursive: true);
                    }
                  } on FileSystemException {
                    // Best effort; the next build clears the folder anyway.
                  }
                }
                if (!completer.isCompleted) completer.complete();
              case GameDataBuildEventType.error:
                state = state.copyWith(
                  phase: GameDataBuildPhase.idle,
                  error: event.message ?? 'Build failed',
                );
                if (!completer.isCompleted) completer.complete();
              case GameDataBuildEventType.cancelled:
                if (!completer.isCompleted) completer.complete();
            }
          } catch (error) {
            state = state.copyWith(
              phase: GameDataBuildPhase.idle,
              error: '$error',
            );
            if (!completer.isCompleted) completer.complete();
          }
        },
        onDone: () {
          // Isolate exited without a terminal event (e.g. killed or crashed
          // before sending a message).
          if (!completer.isCompleted) {
            state = state.copyWith(
              phase: GameDataBuildPhase.idle,
              error: 'Build terminated unexpectedly',
            );
            completer.complete();
          }
        },
      );

      final options = GameDataBuildOptions(
        sourceDir: dirs.sourceDir.path,
        outputDbPath: outputDbPath,
        commitSha: latest,
        existingDbPath: installed != null ? dirs.installPath : null,
        changedFiles: changes,
      );
      await runner.start(options);
      await completer.future;
      await sub.cancel();
    } catch (error) {
      state = state.copyWith(phase: GameDataBuildPhase.idle, error: '$error');
      _cleanupTemp();
    }
  }

  /// Downloads the full source zip at [sha] and extracts only whitelisted
  /// entries into the source directory (first-time pull or rate-limit
  /// fallback). codeload is a non-API endpoint, so it is not quota-limited.
  Future<void> _pullFullSource(
    ArknightsSourceClient client,
    String sha,
    ({Directory sourceDir, Directory tmpDir, String installPath}) dirs,
  ) async {
    final zipPath = p.join(dirs.tmpDir.path, 'source.zip');
    await client.downloadZip(
      sha: sha,
      outputPath: zipPath,
      onProgress: (received, total) {
        state = state.copyWith(
          phase: GameDataBuildPhase.downloading,
          stage: 'zip',
          done: received,
          total: total ?? 0,
        );
      },
    );
    state = state.copyWith(
      phase: GameDataBuildPhase.extracting,
      stage: 'zip',
    );
    // Top-level helper: the Isolate.run closure must not capture this
    // notifier (its closure context would drag riverpod provider futures into
    // the isolate message and fail as "object is unsendable").
    await extractWhitelistedSourceInIsolate(
      zipPath,
      dirs.sourceDir.path,
    );
    final zip = File(zipPath);
    if (await zip.exists()) await zip.delete();
  }

  Future<void> _swapInBuiltDatabase(
    GameDataBuildEvent event,
    String installPath,
  ) async {
    state = state.copyWith(phase: GameDataBuildPhase.swapping);
    await GameDataBuildService().replaceInstalledDatabase(
      builtPath: event.outputPath!,
      installPath: installPath,
    );
    _outputDbPath = null;
    onInstalled();
    state = state.copyWith(
      phase: GameDataBuildPhase.done,
      error: null,
      incremental: event.incremental,
      report: event.report,
      noRelevantChanges: false,
    );
  }

  /// Aborts a running build: kills the isolate and removes temp files. The
  /// installed database is untouched.
  void cancel() {
    _runner?.kill();
    _runner = null;
    _cleanupTemp();
    state = state.copyWith(phase: GameDataBuildPhase.idle, error: null);
  }

  void dismissDone() {
    state = state.copyWith(phase: GameDataBuildPhase.idle);
  }

  void _cleanupTemp() {
    final output = _outputDbPath;
    if (output != null) {
      try {
        final file = File(output);
        if (file.existsSync()) file.deleteSync();
      } on FileSystemException {
        // Best-effort cleanup; the temp dir is pruned on next build.
      }
      _outputDbPath = null;
    }
  }

  Future<String?> _installedCommit() async {
    final status = await GameDataInstaller().getStatus();
    return status.manifest['source_arknights_commit'];
  }

  Future<String?> _installedSchema() async {
    final status = await GameDataInstaller().getStatus();
    return status.manifest['schema_version'];
  }

  Future<({Directory sourceDir, Directory tmpDir, String installPath})>
      _dirs() async {
    Directory dir = await getApplicationDocumentsDirectory();
    if (Platform.isAndroid) {
      final ext = await getExternalStorageDirectory();
      if (ext != null) dir = ext;
    }
    return (
      sourceDir: Directory(p.join(dir.path, 'gamedata_source')),
      tmpDir: Directory(p.join(dir.path, 'gamedata_build_tmp')),
      installPath: p.join(dir.path, 'arklores_gamedata_zh.db'),
    );
  }
}
