import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/theme_provider.dart';
import '../theme/cut_border.dart';
import '../theme/motion.dart';
import 'press_feedback.dart';

/// A panel: white (the theme's panel colour), a hairline frame and a short
/// ink tab on its top edge. With [onTap] it can be pressed, and says so by
/// its cut bottom-right corner; pressing wipes the accent in along its
/// bottom edge and drops a trace line on its left. Without [onTap] it is a
/// plain rectangle.
class ThemeAwareCard extends ConsumerStatefulWidget {
  const ThemeAwareCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin,
    this.onTap,
    this.semanticLabel,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final VoidCallback? onTap;
  final String? semanticLabel;

  @override
  ConsumerState<ThemeAwareCard> createState() => _ThemeAwareCardState();
}

class _ThemeAwareCardState extends ConsumerState<ThemeAwareCard>
    with PressHold<ThemeAwareCard> {
  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider);
    final tappable = widget.onTap != null;
    final down = tappable && pressed;
    final cut = tappable ? 14.0 : 0.0;
    Widget card = Stack(
      children: [
        DecoratedBox(
          decoration: ShapeDecoration(
            color: theme.cardSurface,
            shape: CutBorder(
              bottomRight: cut,
              side: BorderSide(
                color: down ? theme.trace : theme.divider,
              ),
            ),
          ),
          child: Padding(padding: widget.padding, child: widget.child),
        ),
        Positioned(
          left: 0,
          top: 0,
          width: 40,
          height: 4,
          child: ColoredBox(color: theme.textPrimary),
        ),
        if (tappable)
          Positioned(
            left: 0,
            right: cut,
            bottom: 0,
            height: 4,
            child: Align(
              alignment: Alignment.centerLeft,
              child: AnimatedFractionallySizedBox(
                duration:
                    Motion.of(context, down ? Motion.press : Motion.wipe),
                curve: Motion.mech,
                widthFactor: down ? 1 : 0,
                heightFactor: 1,
                child: ColoredBox(color: theme.accentPrimary),
              ),
            ),
          ),
      ],
    );
    if (tappable) {
      card = Semantics(
        button: true,
        label: widget.semanticLabel,
        child: pressListener(
          enabled: true,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              HapticFeedback.selectionClick();
              widget.onTap!();
            },
            child: card,
          ),
        ),
      );
    }
    return widget.margin == null
        ? card
        : Padding(padding: widget.margin!, child: card);
  }
}
