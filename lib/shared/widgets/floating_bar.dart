import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/theme_provider.dart';
import '../theme/app_theme.dart';
import 'press_feedback.dart';

/// Height of a floating top bar ([FloatingBar] in a [FloatingTopBar]).
const double floatingBarHeight = 44;

/// Space a floating top bar takes from the top of the page (its margins
/// included), below the status bar.
const double floatingTopInset = 6 + floatingBarHeight + 6;

/// The look of every floating dock (top bars, the bottom navigation, the
/// question box): a square, slightly translucent plate with a hairline, a
/// soft shadow and a short accent tick on its top-left corner (the corner
/// mark both games put on their panels), standing off the edges so the
/// content shows around it.
class FloatingBar extends StatelessWidget {
  const FloatingBar({
    super.key,
    required this.theme,
    required this.child,
    this.height,
    this.padding = EdgeInsets.zero,
  });

  final AppThemeTokens theme;
  final Widget child;
  final double? height;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: theme.surfaceElevated.withValues(alpha: 0.96),
      elevation: 3,
      shadowColor: Colors.black.withValues(alpha: 0.22),
      shape: Border.all(color: theme.divider, width: 0.5),
      clipBehavior: Clip.hardEdge,
      child: CustomPaint(
        foregroundPainter: CornerTickPainter(theme.accentPrimary),
        child: SizedBox(
          height: height,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// A short L of [color] on a panel's top-left corner.
class CornerTickPainter extends CustomPainter {
  const CornerTickPainter(this.color, {this.length = 10, this.width = 2});

  final Color color;
  final double length;
  final double width;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    canvas
      ..drawRect(Rect.fromLTWH(0, 0, length, width), paint)
      ..drawRect(Rect.fromLTWH(0, 0, width, length * 0.6), paint);
  }

  @override
  bool shouldRepaint(covariant CornerTickPainter old) =>
      color != old.color || length != old.length || width != old.width;
}

/// How a selected tab is marked in every tab row (the library's games, the
/// wiki's sites, the bottom navigation): a bar of [color] along one edge of
/// the tab that wipes in from the left when it is chosen — the games mark a
/// chosen tab with a bar, not a filled lozenge.
class SelectionBar extends StatelessWidget {
  const SelectionBar({
    super.key,
    required this.selected,
    required this.color,
    this.thickness = 2.5,
    this.top = false,
  });

  final bool selected;
  final Color color;
  final double thickness;
  final bool top;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: top ? Alignment.topLeft : Alignment.bottomLeft,
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: selected ? 1 : 0),
        duration: selectionDuration,
        curve: Curves.easeOutExpo,
        builder: (context, t, _) => FractionallySizedBox(
          widthFactor: t,
          child: SizedBox(
            height: thickness,
            child: ColoredBox(color: color),
          ),
        ),
      ),
    );
  }
}

/// The time a selection mark takes to move: short and without overshoot.
const Duration selectionDuration = Duration(milliseconds: 220);

/// The top docks of a page, below the status bar, over the content: what
/// sits on the left ([leading], e.g. tabs) and what sits on the right
/// ([trailing], e.g. one action) are separate floating plates, each as wide
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

/// The row of [FloatingTopBar]: a plate hugging [leading] on the left, a
/// square plate around [trailing] on the right.
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
              child: Center(child: trailing),
            ),
          ),
        ],
      ],
    );
  }
}

/// One choice in a floating plate (a tab, a site): the selected one on a
/// faint tint with a [SelectionBar] along its bottom edge.
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
      child: PressFeedback(
        child: InkWell(
          onTap: selected ? null : withHaptic(onTap),
          child: AnimatedContainer(
            duration: selectionDuration,
            curve: Curves.easeOutCubic,
            constraints: const BoxConstraints(maxWidth: 180),
            color: selected
                ? theme.accentPrimary.withValues(alpha: 0.14)
                : Colors.transparent,
            child: Stack(
              children: [
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.bodyFont.copyWith(
                      fontSize: 13.5,
                      fontWeight:
                          selected ? FontWeight.w700 : FontWeight.w500,
                      color: selected ? theme.textPrimary : theme.textSecondary,
                    ),
                  ),
                ),
                Positioned.fill(
                  child: SelectionBar(
                    selected: selected,
                    color: theme.accentPrimary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A pushed page with floating top docks instead of an app bar: a square
/// back button and the [title] in a plate on the left (as wide as the
/// title), the [actions] in a plate on the right, the page showing around
/// them.
///
/// With [scrollUnder] the body starts at the top of the screen and scrolls
/// beneath the docks (its scrollables use [floatingPadding]); without it
/// the body starts below them.
class FloatingScaffold extends ConsumerWidget {
  const FloatingScaffold({
    super.key,
    required this.title,
    required this.body,
    this.actions = const [],
    this.scrollUnder = false,
    this.floatingActionButton,
    this.backgroundColor,
  });

  final String title;
  final Widget body;
  final List<Widget> actions;
  final bool scrollUnder;
  final Widget? floatingActionButton;

  /// The page's own ground (the reader's plain paper); the app backdrop
  /// shows through when null.
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    final top = MediaQuery.viewPaddingOf(context).top;
    final canPop = ModalRoute.of(context)?.canPop ?? false;
    return Scaffold(
      backgroundColor: backgroundColor ?? Colors.transparent,
      floatingActionButton: floatingActionButton,
      body: Stack(
        children: [
          Positioned.fill(
            child: scrollUnder
                ? body
                : Padding(
                    padding: EdgeInsets.only(top: top + floatingTopInset),
                    child: MediaQuery.removePadding(
                      context: context,
                      removeTop: true,
                      child: body,
                    ),
                  ),
          ),
          Positioned(
            key: const ValueKey('floating-page-bar'),
            top: top + 6,
            left: 10,
            right: 10,
            child: IconButtonTheme(
              data: IconButtonThemeData(
                style: IconButton.styleFrom(
                  foregroundColor: theme.textPrimary,
                  visualDensity: VisualDensity.compact,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (canPop)
                          SizedBox(
                            width: floatingBarHeight,
                            child: FloatingBar(
                              theme: theme,
                              height: floatingBarHeight,
                              child: const Center(child: BackButton()),
                            ),
                          ),
                        if (canPop && title.isNotEmpty) const SizedBox(width: 8),
                        if (title.isNotEmpty)
                          Flexible(
                            child: FloatingBar(
                              theme: theme,
                              height: floatingBarHeight,
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 16),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                widthFactor: 1,
                                child: Text(
                                  title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.titleFont.copyWith(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: theme.textPrimary,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (actions.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    FloatingBar(
                      theme: theme,
                      height: floatingBarHeight,
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: actions,
                      ),
                    ),
                  ],
                ],
              ),            ),
          ),
        ],
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
    top: base.top +
        (topBar ? MediaQuery.viewPaddingOf(context).top + floatingTopInset : 0),
    bottom: base.bottom + insets.bottom,
  );
}
