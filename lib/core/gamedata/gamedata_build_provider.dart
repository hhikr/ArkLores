/// In-app GameData build orchestration (R2): source pull (first-time zip or
/// incremental raw downloads), background-isolate build, validation and swap.
library;

import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'build/gamedata_build_isolate.dart';
import 'build/gamedata_build_service.dart';
import 'build/source/arknights_source_client.dart';
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
    );
  }
}

final gameDataBuildProvider =
    StateNotifierProvider<GameDataBuildNotifier, GameDataBuildUiState>((ref) {
  return GameDataBuildNotifier(
    onInstalled: () => ref.invalidate(gameDataInstallStatusProvider),
  );
});

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
      state = state.copyWith(
        phase: GameDataBuildPhase.idle,
        latestCommit: latest,
        installedCommit: installed,
        changedFileCount: changes.length,
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
  Future<void> buildFromSource({String? githubToken}) async {
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
      final hasSource =
          await File(p.join(dirs.sourceDir.path, 'zh_CN')).exists();

      if (hasSource) {
        // Incremental source pull: compare + raw download of changed files.
        state = state.copyWith(
          phase: GameDataBuildPhase.downloading,
          stage: 'incremental',
          done: 0,
          total: 0,
          error: null,
        );
        try {
          changes = installed == null || installed == latest
              ? const <SourceFileChange>[]
              : await client.compareCommits(
                  baseSha: installed,
                  headSha: latest,
                );
        } on GameDataSourceRateLimitedException {
          // GitHub API quota exhausted on this egress IP (403/429). Fall
          // back to a full zip pull: codeload is a non-API endpoint and is
          // not quota-limited.
          state = state.copyWith(
            phase: GameDataBuildPhase.downloading,
            stage: 'zip',
            error: null,
          );
          final zh = Directory(p.join(dirs.sourceDir.path, 'zh_CN'));
          if (await zh.exists()) await zh.delete(recursive: true);
          await _pullFullSource(client, latest, dirs);
          changes = const <SourceFileChange>[];
        }
        for (var i = 0; i < changes.length; i++) {
          final change = changes[i];
          final target = File(p.join(dirs.sourceDir.path, change.path));
          if (change.isRemoval) {
            if (await target.exists()) await target.delete();
          } else {
            await client.downloadFile(
              sha: latest,
              path: change.path,
              outputPath: target.path,
            );
          }
          state = state.copyWith(
            phase: GameDataBuildPhase.downloading,
            stage: 'incremental',
            done: i + 1,
            total: changes.length,
          );
        }
      } else {
        // First-time pull: one zip download + whitelist-filtered extraction.
        state = state.copyWith(
          phase: GameDataBuildPhase.downloading,
          stage: 'zip',
          error: null,
        );
        await _pullFullSource(client, latest, dirs);
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
    final sourceDirPath = dirs.sourceDir.path;
    await Isolate.run(
      () => ArknightsSourceClient.extractWhitelistedZip(
        zipPath: zipPath,
        outputDir: Directory(sourceDirPath),
      ),
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
