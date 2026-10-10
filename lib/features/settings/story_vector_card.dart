import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/gamedata/game.dart';
import '../../core/gamedata/gamedata_build_provider.dart';
import '../../core/gamedata/gamedata_provider.dart';
import '../../core/gamedata/story_vector_provider.dart';
import '../../core/gamedata/story_vector_updater.dart';
import '../../core/llm/embedding_client.dart';
import '../../shared/l10n/l10n.dart';
import '../../shared/providers/settings_provider.dart';
import '../../shared/providers/theme_provider.dart';
import '../../shared/widgets/theme_aware_card.dart';
import 'kb_common.dart';

/// One game's vectors (stories and records). With nothing to do the card is
/// two lines: what there is, and that it is complete. It opens into what is
/// missing, what that costs, how to configure it and the run itself only
/// when vectors are missing (after an update from the game data, or an
/// asset without record vectors), the configured model differs, or a run is
/// going or just ended.
class StoryVectorCard extends ConsumerStatefulWidget {
  const StoryVectorCard({super.key, this.game = Game.arknights});

  final Game game;

  /// Keeps the Arknights card's widget keys as they were.
  String get keySuffix => game == Game.arknights ? '' : '-${game.key}';

  @override
  ConsumerState<StoryVectorCard> createState() => _StoryVectorCardState();
}

class _StoryVectorCardState extends ConsumerState<StoryVectorCard> {
  StateNotifierProvider<StoryVectorNotifier, StoryVectorUiState>
      get _provider => storyVectorProvider(widget.game);

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (mounted) ref.read(_provider.notifier).refresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider);
    // A finished update or download changes which texts lack vectors.
    if (widget.game == Game.arknights) {
      ref.listen(gameDataBuildProvider, (previous, next) {
        if (previous?.phase != GameDataBuildPhase.done &&
            next.phase == GameDataBuildPhase.done) {
          ref.read(_provider.notifier).refresh();
        }
      });
    }
    ref.listen(installStatusOf(widget.game), (previous, next) {
      if (previous?.valueOrNull != next.valueOrNull) {
        ref.read(_provider.notifier).refresh();
      }
    });
    final installed =
        ref.watch(installStatusOf(widget.game)).valueOrNull?.installed ?? false;
    if (!installed) return const SizedBox.shrink();
    final vec = ref.watch(_provider);
    final config = ref.watch(embeddingConfigProvider);
    final plan = vec.plan;
    final tokensText = plan == null
        ? ''
        : (plan.estimatedTokens / 10000).toStringAsFixed(1);
    final bailian = config.baseUrl.contains('dashscope');
    final yuan = plan == null ? 0.0 : plan.estimatedYuan();
    final canStart = !vec.running &&
        !vec.loading &&
        plan != null &&
        !plan.nothingToDo &&
        config.isValid &&
        vec.mismatch == null;
    // Nothing to decide here: say what there is and stop.
    final quiet = plan != null &&
        plan.nothingToDo &&
        !vec.running &&
        vec.mismatch == null &&
        vec.error == null &&
        (vec.result == null || vec.result!.chunks == 0);
    return ThemeAwareCard(
      key: Key('kb-vector-card${widget.keySuffix}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.hub_sharp, color: theme.accentPrimary, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  context.t.kbVectorTitle,
                  style: theme.titleFont.copyWith(fontSize: 15),
                ),
              ),
              if (quiet)
                Text(
                  context.t.kbVectorComplete,
                  key: Key('kb-vector-complete${widget.keySuffix}'),
                  style: theme.bodyFont.copyWith(
                    color: theme.accentText,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          if (quiet)
            Padding(
              padding: const EdgeInsets.only(left: 36),
              child: kbNote(
                context.t.kbVectorSummary(
                  plan.existingVectors,
                  plan.existingRecordVectors,
                ),
                theme,
                theme.textSecondary,
              ),
            )
          else ...[
            kbNote(context.t.kbVectorDesc, theme, theme.textSecondary),
            const SizedBox(height: 10),
          ],
          if (plan != null && !quiet) ...[
            Text(
              plan.existingVectors > 0
                  ? context.t.kbVectorStatus(
                      plan.existingVectors,
                      plan.storiesWithVectors,
                    )
                  : context.t.kbVectorNone,
              style: theme.bodyFont.copyWith(
                color: theme.textPrimary,
                fontSize: 13,
              ),
            ),
            if (plan.existingRecordVectors > 0)
              kbNote(
                context.t.kbVectorRecordStatus(plan.existingRecordVectors),
                theme,
                theme.textPrimary,
              ),
            const SizedBox(height: 4),
            if (plan.nothingToDo)
              kbNote(context.t.kbVectorUpToDate, theme, theme.accentText)
            else ...[
              kbNote(
                context.t.kbVectorPending(
                  plan.pendingStories,
                  plan.pendingChunks,
                  tokensText,
                ),
                theme,
                theme.textPrimary,
              ),
              if (plan.pendingRecordChunks > 0)
                kbNote(
                  context.t.kbVectorPendingRecords(plan.pendingRecordChunks),
                  theme,
                  theme.textPrimary,
                ),
              if (bailian)
                kbNote(
                  context.t.kbVectorCost(
                    yuan < 0.01 ? '<0.01' : yuan.toStringAsFixed(2),
                  ),
                  theme,
                  theme.textSecondary,
                ),
              if (plan.isFirstBuild)
                kbNote(context.t.kbVectorFirstBuild, theme, theme.warning),
            ],
          ],
          // Asking by meaning needs the service too, vectors or not.
          if (!config.isValid) ...[
            const SizedBox(height: 6),
            kbNote(
              context.t.kbVectorConfigure(
                defaultEmbeddingConfig.model,
                defaultEmbeddingConfig.dimensions,
              ),
              theme,
              theme.warning,
            ),
          ],
          if (vec.mismatch != null) ...[
            const SizedBox(height: 6),
            kbNote(
              context.t.kbVectorMismatch(
                vec.mismatch!.have,
                vec.mismatch!.want,
              ),
              theme,
              theme.danger,
            ),
          ],
          if (vec.running) ...[
            const SizedBox(height: 10),
            kbNote(
              // The records come after the stories.
              vec.totalRecords > 0
                  ? context.t.kbVectorRunningRecords(
                      vec.doneRecords,
                      vec.totalRecords,
                    )
                  : context.t.kbVectorRunning(
                      vec.doneStories,
                      vec.totalStories,
                      vec.doneChunks,
                    ),
              theme,
              theme.textPrimary,
            ),
            const SizedBox(height: 6),
            LinearProgressIndicator(
              value: vec.totalRecords > 0
                  ? (vec.doneRecords / vec.totalRecords).clamp(0.0, 1.0)
                  : vec.totalStories > 0
                      ? (vec.doneStories / vec.totalStories).clamp(0.0, 1.0)
                      : null,
              backgroundColor: theme.divider,
              valueColor: AlwaysStoppedAnimation(theme.accentPrimary),
              minHeight: 6,
            ),
          ] else if (vec.result != null && vec.result!.chunks > 0) ...[
            const SizedBox(height: 6),
            kbNote(
              context.t.kbVectorDone(
                vec.result!.chunks,
                vec.result!.tokensUsed,
              ),
              theme,
              theme.accentText,
            ),
          ],
          if (vec.error != null) ...[
            const SizedBox(height: 6),
            kbNote(vec.error!, theme, theme.danger),
          ],
          if (!quiet) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: vec.running || vec.loading
                      ? null
                      : () => ref.read(_provider.notifier).refresh(),
                  icon: const Icon(Icons.refresh_sharp, size: 18),
                  label: Text(context.t.kbVectorRefresh),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: theme.accentText,
                    side: BorderSide(color: theme.divider),
                  ),
                ),
                const SizedBox(width: 8),
                if (vec.running)
                  OutlinedButton.icon(
                    onPressed: () => ref.read(_provider.notifier).cancel(),
                    icon: const Icon(Icons.stop_sharp, size: 18),
                    label: Text(context.t.kbVectorCancel),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: theme.danger,
                      side: BorderSide(color: theme.divider),
                    ),
                  )
                else
                  ElevatedButton.icon(
                    key: Key('kb-vector-start${widget.keySuffix}'),
                    onPressed: canStart ? () => _startVectors(plan) : null,
                    icon: const Icon(Icons.auto_awesome_sharp, size: 18),
                    label: Text(context.t.kbVectorStart),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.accentPrimary,
                      foregroundColor: theme.onAccent,
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// Starts the vector update; a first complete build asks first (it costs
  /// far more than an incremental update).
  Future<void> _startVectors(VectorPlan plan) async {
    if (plan.isFirstBuild) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: Text(context.t.kbVectorConfirmTitle),
          content: Text(
            context.t.kbVectorConfirmBody(
              plan.pendingStories,
              plan.pendingChunks,
              (plan.estimatedTokens / 10000).toStringAsFixed(1),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: Text(context.t.kbCancel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: Text(context.t.kbVectorConfirm),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    unawaited(ref.read(_provider.notifier).start());
  }
}
