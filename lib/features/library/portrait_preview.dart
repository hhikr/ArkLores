import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/gamedata/build/portrait_names.dart';
import '../../core/library/portrait_provider.dart';
import '../../shared/l10n/l10n.dart';
import '../../shared/providers/theme_provider.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/theme/motion.dart';
import '../../shared/widgets/ef_widgets.dart';
import '../../shared/widgets/portrait_image.dart';
import 'portrait_sheet.dart';

VoidCallback? _dismissPreview;

void showPortraitPreview(
  BuildContext context, {
  required String speaker,
  required PortraitOrigin origin,
  String? sprite,
  Future<String?>? spriteFuture,
  bool fromLine = false,
  Rect? anchor,
  BuildContext? anchorContext,
}) {
  _dismissPreview?.call();
  final box = (anchorContext ?? context).findRenderObject();
  anchor ??= box is RenderBox
      ? box.localToGlobal(Offset.zero) & box.size
      : const Rect.fromLTWH(16, 80, 48, 20);
  final overlay = Overlay.of(context);
  final route = ModalRoute.of(context);
  final scroll = Scrollable.maybeOf(anchorContext ?? context)?.position;
  late OverlayEntry entry;
  late LocalHistoryEntry history;
  var closed = false;
  var removed = false;
  late VoidCallback close;
  void remove() {
    if (removed) return;
    removed = true;
    closed = true;
    scroll?.removeListener(close);
    if (context.mounted) history.remove();
    entry.remove();
    entry.dispose();
    if (_dismissPreview == remove) _dismissPreview = null;
  }

  close = () {
    if (closed) return;
    closed = true;
    scroll?.removeListener(close);
    if (context.mounted && overlay.mounted) {
      entry.markNeedsBuild();
      history.remove();
    } else {
      remove();
    }
  };

  history = LocalHistoryEntry(onRemove: close);
  entry = OverlayEntry(
    builder: (_) => IgnorePointer(
      ignoring: closed,
      child: AnimatedOpacity(
        opacity: closed ? 0 : 1,
        duration: Motion.of(context, Motion.dialogOut),
        curve: Motion.mech,
        onEnd: () {
          if (closed) remove();
        },
        child: _PreviewOverlay(
          anchor: anchor!,
          speaker: speaker,
          sprite: sprite,
          spriteFuture: spriteFuture,
          fromLine: fromLine,
          onClose: close,
          onMore: () {
            close();
            showPortraitSheet(
              context,
              speaker: speaker,
              sprite: sprite,
              spriteFuture: spriteFuture,
              fromLine: fromLine,
              origin: origin,
            );
          },
        ),
      ),
    ),
  );
  _dismissPreview = remove;
  route?.addLocalHistoryEntry(history);
  scroll?.addListener(close);
  overlay.insert(entry);
}

class _PreviewOverlay extends ConsumerWidget {
  const _PreviewOverlay({
    required this.anchor,
    required this.speaker,
    this.sprite,
    this.spriteFuture,
    required this.fromLine,
    required this.onClose,
    required this.onMore,
  });
  final Rect anchor;
  final String speaker;
  final String? sprite;
  final Future<String?>? spriteFuture;
  final bool fromLine;
  final VoidCallback onClose, onMore;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    final size = MediaQuery.sizeOf(context);
    final bottom = size.height - MediaQuery.viewInsetsOf(context).bottom - 16;
    final width = math.min(280.0, size.width - 32);
    const height = 256.0;
    final top = anchor.bottom + 8 + height <= bottom
        ? anchor.bottom + 8
        : math.max(16.0, anchor.top - height - 8);
    final name = ref.watch(speakerPortraitsProvider(speaker)).valueOrNull;
    return Stack(
      children: [
        Positioned.fill(
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (_) => onClose(),
            onPointerSignal: (_) => onClose(),
          ),
        ),
        Positioned(
          left: anchor.left.clamp(16.0, size.width - width - 16),
          top: top,
          width: width,
          child: ExcludeFocus(
            child: TextFieldTapRegion(
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: Motion.of(context, Motion.dialogIn),
                curve: Motion.snap,
                builder: (_, value, child) =>
                    Opacity(opacity: value, child: child),
                child: Material(
                  color: theme.cardSurface,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      border: Border.all(color: theme.cardBorder),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          height: 160,
                          child: FutureBuilder<String?>(
                            future: spriteFuture,
                            builder: (_, snapshot) {
                              final shown = fromLine
                                  ? (spriteFuture == null
                                      ? sprite
                                      : snapshot.data)
                                  : name?.topSprite;
                              if (spriteFuture != null &&
                                  snapshot.connectionState !=
                                      ConnectionState.done) {
                                return const SizedBox.shrink();
                              }
                              if (shown == null) {
                                return Text(
                                  context.t.portraitNoSprite,
                                  style: theme.text(14),
                                );
                              }
                              final group = ref
                                  .watch(
                                    portraitGroupProvider(
                                      SpriteName.parse(shown)!.group,
                                    ),
                                  )
                                  .valueOrNull;
                              return PortraitImage(
                                sprite: shown,
                                fallbackSprite: group?.topSprite,
                              );
                            },
                          ),
                        ),
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    speaker,
                                    style: theme.heading(14),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (name != null)
                                    Text(
                                      context.t.portraitLines(name.lines),
                                      style: theme.field(),
                                    ),
                                ],
                              ),
                            ),
                            AppButton(
                              context.t.portraitMore,
                              onPressed: onMore,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
