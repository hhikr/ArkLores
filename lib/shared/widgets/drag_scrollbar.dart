import 'dart:math' as math;

import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/theme_provider.dart';

/// A scrollbar on the right edge of one vertical scrollable, drawn from its
/// [controller]: the thumb is as long as the share of the content in view
/// and sits where the view is, also while the content grows. Dragging along
/// the strip moves the content (the thumb follows the finger); a tap on the
/// strip away from the thumb pages to that place. Nothing is drawn while
/// everything fits.
///
/// The material [Scrollbar] cannot be dragged on a phone and only redraws
/// when the view scrolls (2026-11-12, the developer: the thinking window's
/// did not show where it was).
class DragScrollbar extends ConsumerStatefulWidget {
  const DragScrollbar({
    super.key,
    required this.controller,
    required this.child,
  });

  final ScrollController controller;
  final Widget child;

  /// Width of the strip that takes the finger; the thumb drawn in it is
  /// [thumbWidth] wide, at its right edge.
  static const double stripWidth = 28;
  static const double thumbWidth = 4;
  static const double minThumbLength = 36;

  @override
  ConsumerState<DragScrollbar> createState() => _DragScrollbarState();
}

class _DragScrollbarState extends ConsumerState<DragScrollbar> {
  bool _dragging = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
    // The scrollable has its size only after the first layout.
    WidgetsBinding.instance.addPostFrameCallback((_) => _changed());
  }

  @override
  void didUpdateWidget(DragScrollbar old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  /// The thumb's length and top in a strip [height] high, or null when the
  /// content fits.
  (double, double)? _thumb(double height) {
    final c = widget.controller;
    if (!c.hasClients || !c.position.hasContentDimensions) return null;
    final p = c.position;
    final max = p.maxScrollExtent;
    if (max <= 0 || height <= 0) return null;
    final length = (height * p.viewportDimension / (max + p.viewportDimension))
        .clamp(math.min(DragScrollbar.minThumbLength, height), height)
        .toDouble();
    final share = (p.pixels / max).clamp(0.0, 1.0);
    return (length, (height - length) * share);
  }

  void _dragBy(double dy, double height) {
    final c = widget.controller;
    final thumb = _thumb(height);
    if (thumb == null) return;
    final p = c.position;
    final travel = height - thumb.$1;
    if (travel <= 0) return;
    c.jumpTo(
      (p.pixels + dy * p.maxScrollExtent / travel)
          .clamp(0.0, p.maxScrollExtent),
    );
  }

  void _tapAt(double y, double height) {
    final thumb = _thumb(height);
    if (thumb == null) return;
    final (length, top) = thumb;
    if (y >= top && y <= top + length) return;
    final p = widget.controller.position;
    final page = p.viewportDimension * 0.9;
    final to = y < top ? p.pixels - page : p.pixels + page;
    widget.controller.jumpTo(to.clamp(0.0, p.maxScrollExtent));
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider);
    return NotificationListener<ScrollMetricsNotification>(
      // The content grew or shrank without a scroll: redraw the thumb.
      onNotification: (_) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _changed());
        return false;
      },
      child: Stack(
        children: [
          widget.child,
          Positioned(
            top: 0,
            bottom: 0,
            right: 0,
            width: DragScrollbar.stripWidth,
            child: LayoutBuilder(
              builder: (context, box) {
                final height = box.maxHeight;
                final thumb = _thumb(height);
                if (thumb == null) return const SizedBox.shrink();
                final (length, top) = thumb;
                return GestureDetector(
                  key: const ValueKey('drag-scrollbar'),
                  behavior: HitTestBehavior.opaque,
                  // The thumb moves the whole way the finger did, not less
                  // the slop it took to tell a drag.
                  dragStartBehavior: DragStartBehavior.down,
                  onTapUp: (d) => _tapAt(d.localPosition.dy, height),
                  onVerticalDragStart: (_) => setState(() => _dragging = true),
                  onVerticalDragUpdate: (d) => _dragBy(d.delta.dy, height),
                  onVerticalDragEnd: (_) => setState(() => _dragging = false),
                  onVerticalDragCancel: () => setState(() => _dragging = false),
                  child: Stack(
                    children: [
                      Positioned(
                        key: const ValueKey('drag-scrollbar-thumb'),
                        top: top,
                        right: 2,
                        width: DragScrollbar.thumbWidth,
                        height: length,
                        child: ColoredBox(
                          color: _dragging
                              ? theme.trace
                              : theme.textPrimary.withValues(alpha: 0.35),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
