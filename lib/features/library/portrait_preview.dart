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
    final top =
        below ? anchor.bottom + 6 : math.max(16.0, anchor.top - height - 6);
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
          left: anchor.left.clamp(16.0, size.width - width - 16),
          top: top,
          width: width,
          child: ExcludeFocus(
            child: TextFieldTapRegion(
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: Motion.of(context, Motion.dialogIn),
                curve: Motion.mech,
                // It opens out of the name: down from it, or up when it
                // sits above.
                builder: (_, value, child) => ClipRect(
                  child: Align(
                    alignment:
                        below ? Alignment.topCenter : Alignment.bottomCenter,
                    heightFactor: value,
                    child: child,
                  ),
                ),
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
                              return PortraitImage(
                                sprite: shown,
                                fallbackSprite: group?.topSprite,
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
                      ],
                    ),                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
