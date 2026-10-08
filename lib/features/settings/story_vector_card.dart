import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

/// Story vectors: what is missing, what it costs, how to configure it, and
/// generating them.
class StoryVectorCard extends ConsumerStatefulWidget {
  const StoryVectorCard({super.key});

  @override
  ConsumerState<StoryVectorCard> createState() => _StoryVectorCardState();
}

class _StoryVectorCardState extends ConsumerState<StoryVectorCard> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (mounted) ref.read(storyVectorProvider.notifier).refresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider);
    // A finished update changes which stories lack vectors.
    ref.listen(gameDataBuildProvider, (previous, next) {
      if (previous?.phase != GameDataBuildPhase.done &&
          next.phase == GameDataBuildPhase.done) {
        ref.read(storyVectorProvider.notifier).refresh();
      }
    });
    final installed =
        ref.watch(gameDataInstallStatusProvider).valueOrNull?.installed ??
            false;
    if (!installed) return const SizedBox.shrink();
    final vec = ref.watch(storyVectorProvider);
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
    return ThemeAwareCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.hub_rounded, color: theme.accentPrimary, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  context.t.kbVectorTitle,
                  style: theme.titleFont.copyWith(fontSize: 15),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          kbNote(context.t.kbVectorDesc, theme, theme.textSecondary),
          const SizedBox(height: 10),
          if (plan != null) ...[
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
              context.t.kbVectorRunning(
                vec.doneStories,
                vec.totalStories,
                vec.doneChunks,
              ),
              theme,
              theme.textPrimary,
            ),
            const SizedBox(height: 6),
            LinearProgressIndicator(
              value: vec.totalStories > 0
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
          const SizedBox(height: 10),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: vec.running || vec.loading
                    ? null
                    : () => ref.read(storyVectorProvider.notifier).refresh(),
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: Text(context.t.kbVectorRefresh),
                style: OutlinedButton.styleFrom(
                  foregroundColor: theme.accentText,
                  side: BorderSide(color: theme.divider),
                ),
              ),
              const SizedBox(width: 8),
              if (vec.running)
                OutlinedButton.icon(
                  onPressed: () =>
                      ref.read(storyVectorProvider.notifier).cancel(),
                  icon: const Icon(Icons.stop_rounded, size: 18),
                  label: Text(context.t.kbVectorCancel),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: theme.danger,
                    side: BorderSide(color: theme.divider),
                  ),
                )
              else
                ElevatedButton.icon(
                  key: const Key('kb-vector-start'),
                  onPressed: canStart ? () => _startVectors(plan) : null,
                  icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                  label: Text(context.t.kbVectorStart),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.accentPrimary,
                    foregroundColor: theme.onAccent,
                  ),
                ),
            ],
          ),
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
    unawaited(ref.read(storyVectorProvider.notifier).start());
  }
}
