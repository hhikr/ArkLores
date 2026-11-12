import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/gamedata/game.dart';
import '../../core/gamedata/gamedata_channel.dart';
import '../../core/gamedata/story_art_pack_provider.dart';
import '../../core/library/portrait_provider.dart';
import '../../shared/l10n/l10n.dart';
import '../../shared/providers/theme_provider.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/ef_widgets.dart';
import '../../shared/widgets/theme_aware_card.dart';
import 'kb_common.dart';

/// The story-art packs: the standard and the HD one (developer 2026-11-12),
/// each downloaded, updated and deleted on its own; with both installed the
/// user picks the one the pages draw from.
class StoryArtPackCard extends ConsumerWidget {
  const StoryArtPackCard({super.key, this.game = Game.arknights});
  final Game game;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    final t = context.t;
    final endfield = game == Game.endfield;
    final index = endfield ? null : ref.watch(hasPortraitIndexProvider);
    return ThemeAwareCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          KbCardHeader(icon: Icons.image_sharp, title: t.storyArtPackTitle),
          const SizedBox(height: 8),
          if (endfield)
            kbNote(t.storyArtPackEndfield, theme, theme.textSecondary)
          else ...[
            kbNote(t.storyArtDescription, theme, theme.textSecondary),
            if (index?.hasValue == true && index!.value != true) ...[
              const SizedBox(height: 8),
              kbNote(t.storyArtPackOldIndex, theme, theme.textSecondary),
            ],
            for (final variant in StoryArtVariant.values) ...[
              const SizedBox(height: 12),
              _VariantBlock(
                variant: variant,
                ready: index?.valueOrNull == true,
              ),
            ],
            const SizedBox(height: 12),
            kbNote(t.storyArtCredit, theme, theme.textMuted),
          ],
        ],
      ),
    );
  }
}

/// One variant: what it is, its state, and what can be done with it.
class _VariantBlock extends ConsumerWidget {
  const _VariantBlock({required this.variant, required this.ready});
  final StoryArtVariant variant;

  /// The knowledge base has the portrait tables (a pack can be downloaded).
  final bool ready;

  String _size(int bytes) => '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    final t = context.t;
    final status = ref.watch(storyArtPackStatusProvider(variant));
    final s = status.valueOrNull;
    final asset = s?.asset;
    final downloading = s?.downloading == true;
    // One download at a time: the packs are large.
    final otherDownloading = StoryArtVariant.values
        .where((v) => v != variant)
        .any((v) => ref.watch(storyArtPackDownloadProvider(v)).downloading);
    final canDownload = ready &&
        asset != null &&
        !downloading &&
        !otherDownloading &&
        (s?.installed != true || s?.updateAvailable == true);
    // An installed pack can be deleted even when the knowledge base no
    // longer has the portrait tables.
    final canDelete = s?.installed == true && !downloading;
    final canUse = s?.installed == true && s?.inUse != true && !downloading;
    // The channel file could not be read (no network, GitHub out of reach):
    // not the same as a pack that is not released, and it can be tried again.
    final channel = ref.watch(gameDataChannelProvider);
    final unreachable = channel.hasValue && channel.value == null;
    final canRetry = unreachable && asset == null && !downloading;
    final String? text;
    if (!status.hasValue) {
      // Only before the first answer: every progress report of a download
      // works the status out again, and a card that blanks its text for each
      // one jumps as fast as they come.
      text = null;
    } else if (downloading) {
      final total = s!.total ?? asset?.size ?? 0;
      text = t.storyArtPackProgress(
        _size(s.received),
        _size(total),
        total > 0
            ? (100 * s.received / total).clamp(0, 100).toStringAsFixed(0)
            : '0',
      );
    } else if (s!.installed && (asset == null || !s.updateAvailable)) {
      text = t.storyArtPackInstalled(
        s.spriteCount,
        s.backgroundCount,
        s.illustrationCount,
        _size(s.bytes),
      );
    } else if (asset == null) {
      text = unreachable
          ? t.storyArtChannelUnreachable
          : ready
              ? t.storyArtVariantUnreleased
              : null;
    } else if (s.updateAvailable) {
      text = t.storyArtPackUpdateAvailable(_size(asset.size));
    } else {
      text = ready ? t.storyArtPackDescription(_size(asset.size)) : null;
    }
    final name = switch (variant) {
      StoryArtVariant.standard => t.storyArtVariantStandard,
      StoryArtVariant.hd => t.storyArtVariantHd,
    };
    final spec = switch (variant) {
      StoryArtVariant.standard => t.storyArtVariantStandardSpec,
      StoryArtVariant.hd => t.storyArtVariantHdSpec,
    };
    return Container(
      key: ValueKey('story-art-${variant.name}'),
      padding: const EdgeInsets.only(top: 12),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: theme.divider)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  name,
                  style: theme.ui(15, weight: 700, color: theme.textPrimary),
                ),
              ),
              if (s?.inUse == true)
                StateStamp(
                  t.storyArtInUse,
                  key: ValueKey('story-art-in-use-${variant.name}'),
                ),
            ],
          ),
          const SizedBox(height: 4),
          kbNote(spec, theme, theme.textSecondary),
          if (text != null) ...[
            const SizedBox(height: 4),
            kbNote(text, theme, theme.textSecondary),
          ],
          if (s?.installed == true && (s?.updateAvailable == true || downloading)) ...[
            const SizedBox(height: 4),
            kbNote(
              t.storyArtPackInstalled(
                s!.spriteCount,
                s.backgroundCount,
                s.illustrationCount,
                _size(s.bytes),
              ),
              theme,
              theme.textSecondary,
            ),
          ],
          if (downloading) ...[
            const SizedBox(height: 8),
            SegmentProgress(
              value: (s!.total ?? 0) > 0
                  ? (s.received / s.total!).clamp(0.0, 1.0)
                  : null,
            ),
          ],
          if (s?.error != null || status.hasError) ...[
            const SizedBox(height: 8),
            kbFlag(t.storyArtPackError, theme),
          ],
          if (canDownload || canDelete || canUse || canRetry || downloading) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (canRetry)
                  AppButton(
                    t.storyArtRetry,
                    key: ValueKey('story-art-retry-${variant.name}'),
                    onPressed: () => ref.invalidate(gameDataChannelProvider),
                  ),
                if (canUse)
                  AppButton(
                    t.storyArtUseThis,
                    key: ValueKey('story-art-use-${variant.name}'),
                    onPressed: () =>
                        unawaited(useStoryArtVariant(ref, variant)),
                  ),
                if (canDownload)
                  AppButton(
                    s!.installed ? t.storyArtPackUpdate : t.storyArtVariantDownload,
                    key: ValueKey('story-art-download-${variant.name}'),
                    kind: ButtonKind.go,
                    onPressed: () => unawaited(
                      ref
                          .read(storyArtPackDownloadProvider(variant).notifier)
                          .start(t.storyArtPackDownload),
                    ),
                  ),
                if (downloading)
                  AppButton(
                    t.storyArtPackCancel,
                    onPressed: () => ref
                        .read(storyArtPackDownloadProvider(variant).notifier)
                        .cancel(),
                  ),
                if (canDelete)
                  AppButton(
                    t.storyArtPackDelete,
                    key: ValueKey('story-art-delete-${variant.name}'),
                    kind: ButtonKind.danger,
                    onPressed: () async {
                      final ok = await confirmAction(
                        context,
                        title: t.storyArtPackDelete,
                        message: t.storyArtPackDeleteConfirm,
                        confirm: t.storyArtPackDelete,
                        danger: true,
                      );
                      if (ok) {
                        await ref
                            .read(storyArtPackDownloadProvider(variant).notifier)
                            .delete();
                      }
                    },
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
