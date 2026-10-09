/// UI state of the story vector update (what is missing, what it costs, and
/// the run itself). The work is in `story_vector_updater.dart`.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart' as sqflite;

import '../../shared/providers/settings_provider.dart';
import '../background/background_work.dart';
import '../llm/embedding_client.dart';
import 'gamedata_installer.dart';
import 'story_vector_updater.dart';

/// Where the vector update stands.
class StoryVectorUiState {
  const StoryVectorUiState({
    this.plan,
    this.loading = false,
    this.running = false,
    this.doneStories = 0,
    this.totalStories = 0,
    this.doneChunks = 0,
    this.result,
    this.error,
    this.mismatch,
  });

  final VectorPlan? plan;
  final bool loading;
  final bool running;
  final int doneStories;
  final int totalStories;
  final int doneChunks;

  /// The last finished run.
  final VectorUpdateResult? result;
  final String? error;

  /// `have@dims` / `want@dims` when the configured model differs from the
  /// one of the existing vectors.
  final ({String have, String want})? mismatch;

  StoryVectorUiState copyWith({
    VectorPlan? plan,
    bool? loading,
    bool? running,
    int? doneStories,
    int? totalStories,
    int? doneChunks,
    VectorUpdateResult? result,
    String? error,
    bool clearError = false,
    ({String have, String want})? mismatch,
    bool clearMismatch = false,
  }) =>
      StoryVectorUiState(
        plan: plan ?? this.plan,
        loading: loading ?? this.loading,
        running: running ?? this.running,
        doneStories: doneStories ?? this.doneStories,
        totalStories: totalStories ?? this.totalStories,
        doneChunks: doneChunks ?? this.doneChunks,
        result: result ?? this.result,
        error: clearError ? null : (error ?? this.error),
        mismatch: clearMismatch ? null : (mismatch ?? this.mismatch),
      );
}

final storyVectorProvider =
    StateNotifierProvider<StoryVectorNotifier, StoryVectorUiState>((ref) {
  return StoryVectorNotifier(() => ref.read(embeddingConfigProvider));
});

class StoryVectorNotifier extends StateNotifier<StoryVectorUiState> {
  StoryVectorNotifier(this._config) : super(const StoryVectorUiState());

  final EmbeddingConfig Function() _config;
  bool _cancel = false;

  Future<String?> _dbPath() async {
    final status = await GameDataInstaller().getStatus();
    return status.installed ? status.dbPath : null;
  }

  /// Reads what is missing from the installed knowledge base.
  Future<void> refresh() async {
    if (state.running) return;
    state = state.copyWith(loading: true, clearError: true);
    try {
      final path = await _dbPath();
      if (path == null) {
        state = const StoryVectorUiState();
        return;
      }
      final db = await sqflite.openDatabase(path, readOnly: true, singleInstance: false);
      try {
        final plan = await planVectorUpdate(db);
        final config = _config();
        final mismatch = plan.existingVectors > 0 &&
                plan.model != null &&
                config.isValid &&
                (plan.model != config.model ||
                    plan.dims != config.dimensions)
            ? (
                have: '${plan.model}@${plan.dims}',
                want: '${config.model}@${config.dimensions}',
              )
            : null;
        state = state.copyWith(
          plan: plan,
          loading: false,
          mismatch: mismatch,
          clearMismatch: mismatch == null,
        );
      } finally {
        await db.close();
      }
    } catch (error) {
      state = state.copyWith(loading: false, error: '$error');
    }
  }

  /// Embeds the stories without vectors with the configured embedding
  /// service. Needs a valid configuration (the page checks it first).
  Future<void> start() => BackgroundWork.instance.run(
        BackgroundWork.text('正在生成故事向量', 'Generating story vectors'),
        _start,
      );

  Future<void> _start() async {
    if (state.running) return;
    final config = _config();
    if (!config.isValid) {
      state = state.copyWith(error: 'embedding is not configured');
      return;
    }
    final path = await _dbPath();
    if (path == null) return;
    _cancel = false;
    state = state.copyWith(
      running: true,
      doneStories: 0,
      doneChunks: 0,
      clearError: true,
    );
    final client = OpenAICompatibleEmbeddingClient(config: config);
    sqflite.Database? db;
    try {
      db = await sqflite.openDatabase(path, singleInstance: false);
      final result = await updateStoryVectors(
        db: db,
        client: client,
        shouldCancel: () => _cancel,
        onProgress: (done, total, chunks) {
          state = state.copyWith(
            doneStories: done,
            totalStories: total,
            doneChunks: chunks,
          );
        },
      );
      state = state.copyWith(running: false, result: result);
    } on VectorModelMismatch catch (error) {
      state = state.copyWith(
        running: false,
        mismatch: (have: error.have, want: error.want),
      );
    } catch (error) {
      state = state.copyWith(running: false, error: '$error');
    } finally {
      client.dispose();
      await db?.close();
    }
    await refresh();
  }

  void cancel() => _cancel = true;
}
