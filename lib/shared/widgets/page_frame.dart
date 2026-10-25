import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/bars_provider.dart';
import '../providers/theme_provider.dart';
import '../theme/app_theme.dart';
import '../theme/cut_border.dart';
import '../theme/motion.dart';
import 'ef_widgets.dart';
import 'press_feedback.dart';

/// Height of a page's top bar, below the status bar.
const double topBarHeight = 56;

/// Room the top bar takes from the top of the page, below the status bar.
const double topBarInset = topBarHeight;

/// A plate that holds controls over content (the question box, the wiki's
/// controls): a panel with a hairline frame and a short ink tab on its top
/// edge. No shadow, no glow.
class DockPanel extends StatelessWidget {
  const DockPanel({
    super.key,
    required this.theme,
    required this.child,
    this.height,
    this.padding = EdgeInsets.zero,
    this.footer,
    this.tab = true,
  });

  final AppThemeTokens theme;
  final Widget child;
  final double? height;
  final EdgeInsetsGeometry padding;

  /// Laid along the plate's bottom edge, over its full width (outside
  /// [padding]).
  final Widget? footer;
  final bool tab;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: theme.cardSurface,
      shape: Border.all(color: theme.divider),
      clipBehavior: Clip.hardEdge,
      child: SizedBox(
        height: height,
        child: Stack(
          children: [
            Padding(padding: padding, child: child),
            if (tab)
              Positioned(
                left: 0,
                top: 0,
                width: 32,
                height: 3,
                child: ColoredBox(color: theme.textPrimary),
              ),
            if (footer != null)
              Positioned(left: 0, right: 0, bottom: 0, child: footer!),
          ],
        ),
      ),
    );
  }
}

/// How a chosen item is marked along an edge (a site in the wiki's bar, a
/// fold's open state): a bar of [color] that wipes in from the left when it
/// is chosen, mechanically.
class SelectionBar extends StatelessWidget {
  const SelectionBar({
    super.key,
    required this.selected,
    required this.color,
    this.thickness = 3,
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
        duration: Motion.of(context, selectionDuration),
        curve: Motion.mech,
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

/// The time a selection mark takes to move.
const Duration selectionDuration = Motion.wipe;

/// The top bar of a main screen (one of the four tabs): the three-colour
/// strip where the screen begins, [leading] (its tabs or its name) on the
/// left, [trailing] (one action) on the right, a hairline below. Put it last
/// in a [Stack] whose content leaves [topBarInset] (plus the status bar)
/// free at the top, or scrolls under it with [pagePadding].
///
/// With [hides] (the wiki, Ask) it slides up under the status bar while the
/// bars are out of the way ([barsHiddenProvider]).
class MainTopBar extends ConsumerWidget {
  const MainTopBar({
    super.key,
    required this.leading,
    this.trailing,
    this.hides = false,
  });

  final Widget leading;
  final Widget? trailing;
  final bool hides;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    final top = MediaQuery.paddingOf(context).top;
    final bar = _bar(theme);
    return Positioned(
      key: const ValueKey('main-top-bar'),
      top: 0,
      left: 0,
      right: 0,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: top,
            width: double.infinity,
            child: ColoredBox(color: theme.bgPrimary),
          ),
          if (hides)
            ClipRect(child: BarsAway(distance: -topBarHeight, child: bar))
          else
            bar,
        ],
      ),
    );
  }

  Widget _bar(AppThemeTokens theme) => DecoratedBox(
        decoration: BoxDecoration(
          color: theme.bgPrimary,
          border: Border(bottom: BorderSide(color: theme.divider)),
        ),
        child: SizedBox(
          height: topBarHeight - 1,
          child: Column(
            children: [
              const TriStrip(),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: leading,
                        ),
                      ),
                      if (trailing != null) trailing!,
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
}

/// The room the shell's tab bar takes at the bottom of a main screen (none
/// on a page pushed on its own): how far what sits on it moves down with
/// [BarsAway].
double tabBarRoom(BuildContext context) {
  final room = MediaQuery.paddingOf(context).bottom -
      MediaQuery.viewPaddingOf(context).bottom;
  return room < 0 ? 0 : room;
}

/// Moves [child] by [distance] (down when positive) while the main screen's
/// bars are out of the way ([barsHiddenProvider]), mechanically: the top
/// bar up, the tab bar and what sits on it (the question box, the wiki's
/// tools) down. Only moved, never laid out again. Not while the keyboard is
/// up (the tab bar is under it then).
class BarsAway extends ConsumerWidget {
  const BarsAway({super.key, required this.distance, required this.child});

  final double distance;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hidden = ref.watch(barsHiddenProvider) &&
        MediaQuery.viewInsetsOf(context).bottom == 0;
    return TweenAnimationBuilder<double>(
      tween: Tween(end: hidden ? 1 : 0),
      duration: Motion.of(context, hidden ? Motion.row : Motion.press * 2),
      curve: Motion.mech,
      child: child,
      builder: (context, t, child) => Transform.translate(
        offset: Offset(0, distance * t),
        child: child,
      ),
    );
  }
}

/// The name of a main screen in its top bar when it has no tabs: the
/// English label small, the Chinese bold.
class TopBarTitle extends ConsumerWidget {
  const TopBarTitle({super.key, required this.title, this.code});

  final String title;
  final String? code;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: Semantics(
        header: true,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Flexible(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.heading(19),
              ),
            ),
            if (code != null) ...[
              const SizedBox(width: 10),
              ExcludeSemantics(child: Eyebrow(code!)),
            ],
          ],
        ),
      ),
    );
  }
}

/// One tab in a top bar (a game, a site): the chosen one is an accent block
/// with a cut corner and bold text; the others are quiet text. 48 high to
/// the finger.
class TopTab extends ConsumerWidget {
  const TopTab({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.compact = false,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  /// A narrower tab (smaller face, tighter padding) for bars that hold
  /// several named tabs and an action, such as the wiki's sites.
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    return Semantics(
      button: true,
      selected: selected,
      child: PressBuilder(
        enabled: !selected,
        builder: (context, down) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: selected
              ? null
              : () {
                  HapticFeedback.selectionClick();
                  onTap();
                },
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
            child: Center(
              widthFactor: 1,
              child: AnimatedContainer(
                duration: Motion.of(context, down ? Motion.press : Motion.wipe),
                curve: Motion.mech,
                constraints: BoxConstraints(maxWidth: compact ? 160 : 180),
                height: compact ? 32 : 36,
                padding: compact
                    ? const EdgeInsets.fromLTRB(10, 0, 12, 0)
                    : const EdgeInsets.fromLTRB(12, 0, 16, 0),
                decoration: ShapeDecoration(
                  color: selected
                      ? theme.accentPrimary
                      : down
                          ? pressTint(Colors.transparent, theme.textPrimary)
                          : Colors.transparent,
                  shape: const CutBorder.br(7),
                ),
                // As wide as the label (an aligned container would fill
                // its whole maxWidth).
                child: Center(
                  widthFactor: 1,
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.ui(
                      compact ? 14 : 15,
                      weight: selected ? 700 : 500,
                      color: selected
                          ? theme.onAccent
                          : down
                              ? theme.textPrimary
                              : theme.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A pushed page: a top bar on the paper (a back button with a cut corner,
/// the [title] in bold with an optional English [code] above it, the
/// [actions] on the right, a hairline below), then the [body].
///
/// With [scrollUnder] the body starts at the top of the screen and scrolls
/// beneath the bar (its scrollables use [pagePadding]); without it the body
/// starts below the bar.
class PageScaffold extends ConsumerWidget {
  const PageScaffold({
    super.key,
    required this.title,
    required this.body,
    this.code,
    this.actions = const [],
    this.scrollUnder = false,
    this.floatingActionButton,
    this.backgroundColor,
    this.titleFooter,
    this.onTitleHoldStart,
    this.onTitleHoldMove,
    this.onTitleHoldEnd,
  });

  final String title;

  /// The title held down and dragged (the reader's scrubbing): the hold
  /// starts, the finger moves (its offset from where the hold started), the
  /// finger lifts.
  final GestureLongPressStartCallback? onTitleHoldStart;
  final GestureLongPressMoveUpdateCallback? onTitleHoldMove;
  final VoidCallback? onTitleHoldEnd;

  /// The English label over the title, or null.
  final String? code;

  /// A thin strip along the bottom edge of the bar (the reader's progress),
  /// over its full width.
  final Widget? titleFooter;
  final Widget body;
  final List<Widget> actions;
  final bool scrollUnder;
  final Widget? floatingActionButton;

  /// The page's own ground (the reader's paper); the app's ground when null.
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    final top = MediaQuery.viewPaddingOf(context).top;
    final canPop = ModalRoute.of(context)?.canPop ?? false;
    final ground = backgroundColor ?? theme.bgPrimary;
    return Scaffold(
      backgroundColor: backgroundColor ?? Colors.transparent,
      floatingActionButton: floatingActionButton,
      body: Stack(
        children: [
          Positioned.fill(
            child: scrollUnder
                ? body
                : Padding(
                    padding: EdgeInsets.only(top: top + topBarInset),
                    child: MediaQuery.removePadding(
                      context: context,
                      removeTop: true,
                      child: body,
                    ),
                  ),
          ),
          Positioned(
            key: const ValueKey('page-top-bar'),
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.only(top: top),
              decoration: BoxDecoration(
                color: ground,
                border: Border(bottom: BorderSide(color: theme.divider)),
              ),
              child: SizedBox(
                height: topBarHeight - 1,
                child: Stack(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Row(
                        children: [
                          if (canPop)
                            SquareIconButton(
                              key: const ValueKey('page-back'),
                              icon: Icons.arrow_back_sharp,
                              tooltip: MaterialLocalizations.of(context)
                                  .backButtonTooltip,
                              filled: true,
                              onPressed: () => Navigator.of(context).maybePop(),
                            ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: GestureDetector(
                              key: const ValueKey('page-title'),
                              behavior: HitTestBehavior.opaque,
                              onLongPressStart: onTitleHoldStart,
                              onLongPressMoveUpdate: onTitleHoldMove,
                              onLongPressEnd: onTitleHoldEnd == null
                                  ? null
                                  : (_) => onTitleHoldEnd!(),
                              onLongPressCancel: onTitleHoldEnd,
                              child: Semantics(
                                header: true,
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (code != null)
                                      ExcludeSemantics(child: Eyebrow(code!)),
                                    if (title.isNotEmpty)
                                      Text(
                                        title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme
                                            .heading(code == null ? 18 : 16),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          if (actions.isNotEmpty) ...[
                            const SizedBox(width: 4),
                            ...actions,
                          ],
                        ],
                      ),
                    ),
                    if (titleFooter != null)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: titleFooter!,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// [base] plus the room the bars take: the top bar (when [topBar]) and the
/// status bar above it, and whatever the shell reserves at the bottom (the
/// tab bar).
EdgeInsets pagePadding(
  BuildContext context,
  EdgeInsets base, {
  bool topBar = true,
}) {
  final insets = MediaQuery.paddingOf(context);
  return base.copyWith(
    top: base.top +
        (topBar ? MediaQuery.viewPaddingOf(context).top + topBarInset : 0),
    bottom: base.bottom + insets.bottom,
  );
}

/// The bottom tab bar of the app: a panel with a hairline above; every tab
/// has a label (the English small above the Chinese); the current one is an
/// accent block with a cut corner that moves to the tab chosen.
class AppTabBar extends ConsumerWidget {
  const AppTabBar({
    super.key,
    required this.items,
    required this.current,
    required this.onSelected,
  });

  /// (English label, label) per tab.
  final List<(String, String)> items;
  final int current;
  final ValueChanged<int> onSelected;

  static const double height = 60;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    return Container(
      key: const ValueKey('main-navigation'),
      decoration: BoxDecoration(
        color: theme.cardSurface,
        border: Border(top: BorderSide(color: theme.divider)),
      ),
      child: SafeArea(
        top: false,
        // The same height while the keyboard comes up (MainShell).
        maintainBottomViewPadding: true,
        child: SizedBox(
          height: height,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
            child: Row(
              children: [
                for (var i = 0; i < items.length; i++)
                  Expanded(
                    child: Semantics(
                      button: true,
                      selected: i == current,
                      label: items[i].$2,
                      excludeSemantics: true,
                      child: PressBuilder(
                        enabled: i != current,
                        builder: (context, down) => GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            if (i != current) HapticFeedback.selectionClick();
                            onSelected(i);
                          },
                          child: AnimatedContainer(
                            duration: Motion.of(
                              context,
                              down ? Motion.press : Motion.wipe,
                            ),
                            curve: Motion.mech,
                            margin: const EdgeInsets.symmetric(horizontal: 3),
                            decoration: ShapeDecoration(
                              color: i == current
                                  ? theme.accentPrimary
                                  : down
                                      ? pressTint(
                                          Colors.transparent,
                                          theme.textPrimary,
                                        )
                                      : Colors.transparent,
                              shape: const CutBorder.br(8),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  // The English over the Chinese; where it
                                  // would only repeat the label, the tab's
                                  // number.
                                  zh &&
                                          items[i].$1.toLowerCase() !=
                                              items[i].$2.toLowerCase()
                                      ? items[i].$1
                                      : '0${i + 1}',
                                  maxLines: 1,
                                  overflow: TextOverflow.clip,
                                  style: theme.eyebrow(
                                    size: 10,
                                    color: i == current
                                        ? theme.onAccent
                                        : theme.textMuted,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  items[i].$2,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.ui(
                                    14,
                                    weight: i == current ? 700 : 500,
                                    color: i == current
                                        ? theme.onAccent
                                        : theme.textPrimary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
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
