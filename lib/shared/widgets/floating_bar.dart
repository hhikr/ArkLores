import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Height of a floating top bar ([FloatingBar] in a [FloatingTopBar]).
const double floatingBarHeight = 44;

/// Space a floating top bar takes from the top of the page (its margins
/// included), below the status bar.
const double floatingTopInset = 6 + floatingBarHeight + 6;

/// The look of every floating dock (top bars, the bottom navigation, the
/// question box): a rounded, slightly translucent card with a hairline and
/// a soft shadow, standing off the edges so the content shows around it.
class FloatingBar extends StatelessWidget {
  const FloatingBar({
    super.key,
    required this.theme,
    required this.child,
    this.radius = 22,
    this.height,
    this.padding = EdgeInsets.zero,
  });

  final AppThemeTokens theme;
  final Widget child;
  final double radius;
  final double? height;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: theme.surfaceElevated.withValues(alpha: 0.96),
      elevation: 3,
      shadowColor: Colors.black.withValues(alpha: 0.22),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
        side: BorderSide(color: theme.divider, width: 0.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        height: height,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// A [FloatingBar] at the top of a page, below the status bar, over the
/// content. Put it last in a [Stack] whose content leaves
/// [floatingTopInset] (plus the status bar) free at the top.
class FloatingTopBar extends StatelessWidget {
  const FloatingTopBar({super.key, required this.theme, required this.child});

  final AppThemeTokens theme;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: MediaQuery.paddingOf(context).top + 6,
      left: 10,
      right: 10,
      child: FloatingBar(
        theme: theme,
        height: floatingBarHeight,
        child: child,
      ),
    );
  }
}

/// [base] plus the room the floating docks take: the top bar (when
/// [topBar]) and the status bar above it, and whatever the shell reserves
/// at the bottom (the floating navigation).
EdgeInsets floatingPadding(
  BuildContext context,
  EdgeInsets base, {
  bool topBar = true,
}) {
  final insets = MediaQuery.paddingOf(context);
  return base.copyWith(
    top: base.top + (topBar ? insets.top + floatingTopInset : 0),
    bottom: base.bottom + insets.bottom,
  );
}
