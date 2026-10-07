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

/// The top docks of a page, below the status bar, over the content: what
/// sits on the left ([leading], e.g. tabs) and what sits on the right
/// ([trailing], e.g. one action) are separate floating pills, each as wide
/// as its content, the page showing between them. Put it last in a
/// [Stack] whose content leaves [floatingTopInset] (plus the status bar)
/// free at the top.
class FloatingTopBar extends StatelessWidget {
  const FloatingTopBar({
    super.key,
    required this.theme,
    required this.leading,
    this.trailing,
  });

  final AppThemeTokens theme;
  final Widget leading;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: MediaQuery.paddingOf(context).top + 6,
      left: 10,
      right: 10,
      child: FloatingSplitBar(
        theme: theme,
        leading: leading,
        trailing: trailing,
      ),
    );
  }
}

/// The row of [FloatingTopBar]: a pill hugging [leading] on the left, a
/// round pill around [trailing] on the right.
class FloatingSplitBar extends StatelessWidget {
  const FloatingSplitBar({
    super.key,
    required this.theme,
    required this.leading,
    this.trailing,
  });

  final AppThemeTokens theme;
  final Widget leading;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: FloatingBar(
            theme: theme,
            height: floatingBarHeight,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: leading,
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 8),
          SizedBox(
            width: floatingBarHeight,
            child: FloatingBar(
              theme: theme,
              height: floatingBarHeight,
              radius: floatingBarHeight / 2,
              child: Center(child: trailing),
            ),
          ),
        ],
      ],
    );
  }
}

/// One choice in a floating pill (a tab, a site): the selected one filled.
class FloatingSegment extends StatelessWidget {
  const FloatingSegment({
    super.key,
    required this.theme,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final AppThemeTokens theme;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: selected ? null : onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          constraints: const BoxConstraints(maxWidth: 180),
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
          decoration: BoxDecoration(
            color: selected
                ? theme.accentPrimary.withValues(alpha: 0.28)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.bodyFont.copyWith(
              fontSize: 13.5,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? theme.textPrimary : theme.textSecondary,
            ),
          ),
        ),
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
