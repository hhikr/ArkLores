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
import 'story_art_viewer.dart';

VoidCallback? _dismissPreview;

const double _pad = 8;
const double _width = 172;
const double _height = 300;

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

/// The part of the card shown while it opens: [across] of its width around
/// the name's place ([side], -1 to 1), [along] of its height from the edge
/// by the name (the top when it is [below] the name).
class _Reveal extends CustomClipper<Rect> {
  const _Reveal({
    required this.across,
    required this.along,
    required this.side,
    required this.below,
  });
  final double across, along, side;
  final bool below;

  @override
  Rect getClip(Size size) {
    final w = size.width * across;
    final h = size.height * along;
    final x = (size.width - w) * (side + 1) / 2;
    return Rect.fromLTWH(x, below ? 0 : size.height - h, w, h);
  }

  @override
  bool shouldReclip(_Reveal old) =>
      old.across != across ||
      old.along != along ||
      old.side != side ||
      old.below != below;
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
    // A tall, narrow card: the figure standing in it, a strip under it.
    final width = math.min(_width, size.width - 32);
    final height = math.min(_height, size.height * 0.5);
    final below = anchor.bottom + 6 + height <= bottom;
    final left = anchor.left.clamp(16.0, size.width - width - 16);
    // Where the name is along the card's width (-1 its left edge, 1 its
    // right): the card is put under or over the name and pushed in from
    // the screen's edge, so it may sit right, left or across it.
    final side = ((anchor.center.dx - left) / width * 2 - 1).clamp(-1.0, 1.0);
    final name = ref.watch(speakerPortraitsProvider(speaker)).valueOrNull;
    return Stack(
      children: [
        // The first touch outside only closes the card: it does not reach
        // what is under it (another name, a link). Inside the text field's
        // tap region, so the Ask input keeps its focus.
        Positioned.fill(
          child: TextFieldTapRegion(
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: (_) => onClose(),
              onPointerSignal: (_) => onClose(),
            ),
          ),
        ),
        Positioned(
          left: left,
          // Held by the edge next to the name, so it grows away from it.
          top: below ? anchor.bottom + 6 : null,
          bottom: below
              ? null
              : size.height - math.max(16.0 + height, anchor.top - 6),
          width: width,
          child: ExcludeFocus(
            child: TextFieldTapRegion(
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: Motion.of(context, Motion.dialogIn),
                curve: Curves.linear,
                // It opens out of the name: its edge by the name is drawn
                // out sideways from over the name, then the card unfolds
                // from that edge, down when it sits below, up when above.
                builder: (_, t, child) {
                  final across = Motion.mech
                      .transform(const Interval(0, 0.45).transform(t));
                  final along = Motion.mech
                      .transform(const Interval(0.3, 1).transform(t));
                  return ClipRect(
                    clipper: _Reveal(
                      across: across,
                      along: math.max(along, 2 / height),
                      side: side,
                      below: below,
                    ),
                    child: child,
                  );
                },
                child: Material(
                  color: theme.cardSurface,
                  child: Container(
                    height: height,
                    padding: const EdgeInsets.all(_pad),
                    decoration: BoxDecoration(
                      border: Border.all(color: theme.cardBorder),
                    ),
                    // The figure fills the card; the name, the count and the
                    // way to the whole card share one strip under it.
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
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
                                return Hatch(
                                  child: Center(
                                    child: Padding(
                                      padding: const EdgeInsets.all(12),
                                      child: Text(
                                        context.t.portraitNoSprite,
                                        textAlign: TextAlign.center,
                                        style: theme.text(
                                          13,
                                          color: theme.textSecondary,
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              }
                              final group = ref
                                  .watch(
                                    portraitGroupProvider(
                                      SpriteName.parse(shown)!.group,
                                    ),
                                  )
                                  .valueOrNull;
                              final variants = ref
                                      .watch(
                                        portraitSpritesProvider(
                                          SpriteName.parse(shown)!.group,
                                        ),
                                      )
                                      .valueOrNull ??
                                  [shown];
                              final pages = variants.contains(shown)
                                  ? variants
                                  : [shown, ...variants];
                              return PortraitFullscreenTap(
                                onTap: () => openArtViewer(
                                  context,
                                  pages: [
                                    for (final item in pages)
                                      ArtViewerPage.portrait(
                                        sprite: item,
                                        speaker: speaker,
                                      ),
                                  ],
                                  initial: pages.indexOf(shown),
                                ),
                                child: PortraitImage(
                                  sprite: shown,
                                  fallbackSprite: group?.topSprite,
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
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
                                      maxLines: 1,
                                      style: theme.field(size: 12),
                                    ),
                                ],
                              ),
                            ),
                            AppButton(
                              context.t.portraitMore,
                              small: true,
                              onPressed: onMore,
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          context.t.storyArtCredit,
                          style: theme.text(12, color: theme.textMuted),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
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
