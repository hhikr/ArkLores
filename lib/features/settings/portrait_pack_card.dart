import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/gamedata/game.dart';
import '../../core/gamedata/portrait_pack_provider.dart';
import '../../core/library/portrait_provider.dart';
import '../../shared/l10n/l10n.dart';
import '../../shared/providers/theme_provider.dart';
import '../../shared/widgets/ef_widgets.dart';
import '../../shared/widgets/theme_aware_card.dart';
import 'kb_common.dart';

class PortraitPackCard extends ConsumerWidget {
  const PortraitPackCard({super.key, this.game = Game.arknights});
  final Game game;

  String _size(int bytes) => '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    final t = context.t;
    final endfield = game == Game.endfield;
    final index = endfield ? null : ref.watch(hasPortraitIndexProvider);
    final status = endfield ? null : ref.watch(portraitPackStatusProvider);
    final s = status?.valueOrNull;
    final asset = s?.asset;
    final ready = index?.valueOrNull == true;
    final downloading = s?.downloading == true;
    final canDownload = ready &&
        asset != null &&
        !downloading &&
        (s?.installed != true || s?.updateAvailable == true);
    // An installed pack can be deleted even when the knowledge base no
    // longer has the portrait tables.
    final canDelete = s?.installed == true && !downloading;
    final String? text;
    if (endfield) {
      text = t.portraitPackEndfield;
    } else if (index?.isLoading == true || status?.isLoading == true) {
      text = null;
    } else if (!ready) {
      text = t.portraitPackOldIndex;
    } else if (downloading) {
      final total = s!.total ?? asset?.size ?? 0;
      text = t.portraitPackProgress(
        _size(s.received),
        _size(total),
        total > 0
            ? (100 * s.received / total).clamp(0, 100).toStringAsFixed(0)
            : '0',
      );
    } else if (asset == null) {
      text = t.portraitPackUnreleased;
    } else if (s!.updateAvailable) {
      text = t.portraitPackUpdateAvailable(_size(asset.size));
    } else if (s.installed) {
      text = t.portraitPackInstalled(s.spriteCount, _size(s.bytes));
    } else {
      text = t.portraitPackDescription(_size(asset.size));
    }
    return ThemeAwareCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          KbCardHeader(icon: Icons.image_sharp, title: t.portraitPackTitle),
          const SizedBox(height: 8),
          if (text != null) kbNote(text, theme, theme.textSecondary),
          if (downloading) ...[
            const SizedBox(height: 8),
            SegmentProgress(
              value: (s!.total ?? 0) > 0
                  ? (s.received / s.total!).clamp(0.0, 1.0)
                  : null,
            ),
          ],
          if (s?.error != null || status?.hasError == true) ...[
            const SizedBox(height: 8),
            kbFlag(t.portraitPackError, theme),
          ],
          if (canDownload || canDelete || downloading) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (canDownload)
                  AppButton(
                    s!.installed
                        ? t.portraitPackUpdate
                        : t.portraitPackDownload,
                    kind: ButtonKind.go,
                    onPressed: () => unawaited(
                      ref
                          .read(portraitPackDownloadProvider.notifier)
                          .start(t.portraitPackDownload),
                    ),
                  ),
                if (downloading)
                  AppButton(
                    t.portraitPackCancel,
                    onPressed: () => ref
                        .read(portraitPackDownloadProvider.notifier)
                        .cancel(),
                  ),
                if (canDelete)
                  AppButton(
                    t.portraitPackDelete,
                    kind: ButtonKind.danger,
                    onPressed: () async {
                      final ok = await confirmAction(
                        context,
                        title: t.portraitPackDelete,
                        message: t.portraitPackDeleteConfirm,
                        confirm: t.portraitPackDelete,
                        danger: true,
                      );
                      if (ok) {
                        await ref
                            .read(portraitPackDownloadProvider.notifier)
                            .delete();
                      }
                    },
                  ),
              ],
            ),
          ],
          if (!endfield) ...[
            const SizedBox(height: 12),
            kbNote(t.portraitPackCredit, theme, theme.textMuted),
          ],
        ],
      ),
    );
  }
}
