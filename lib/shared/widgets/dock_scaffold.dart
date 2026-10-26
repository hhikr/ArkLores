import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/theme_provider.dart';
import '../theme/app_theme.dart';
import '../theme/cut_border.dart';
import '../theme/motion.dart';
import 'press_feedback.dart';

/// Height of the floating controls of a [DockScaffold].
const double floatingDockHeight = 48;

/// From the controls to the screen's sides, and to the system's navigation.
const double _edge = 12;
const double _lift = 8;

/// How much of the bottom of the screen the floating controls cover (with
/// the system's navigation under them): what a body leaves free at its end
/// so its last line can be read clear of them.
double floatingDockRoom(BuildContext context) =>
    floatingDockHeight +
    _lift +
    _edge +
    MediaQuery.viewPaddingOf(context).bottom;

/// One square control among the floating ones.
class DockAction {
  const DockAction({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.key,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final Key? key;
}

/// A pushed page held in one hand (the reader). The paper fills the whole
/// screen, under the status bar too; the controls float over it near the bottom, in
/// reach of the thumb, as separate plates with gaps between them: back, a
/// plate naming the page ([title], a [status] line under it and [progress]
/// along its foot) that opens what [onTitleTap] opens, and the [actions].
/// While [away] they slide down out of the screen (the owner follows the
/// reader's drags and taps, as the wiki and Ask do with their bars).
///
/// [panel] (what the title opens) floats over the controls, as wide as
/// they are; give it its own opening. The body runs under the controls: end
/// it [floatingDockRoom] above the bottom.
class DockScaffold extends ConsumerWidget {
  const DockScaffold({
    super.key,
    required this.title,
    required this.body,
    this.status,
    this.progress,
    this.onTitleTap,
    this.open = false,
    this.actions = const [],
    this.away = false,
    this.panel,
    this.backgroundColor,
  });

  final String title;
  final Widget? status;
  final Widget? progress;
  final VoidCallback? onTitleTap;

  /// What the title opens is open (the chevron points down to close it).
  final bool open;
  final List<DockAction> actions;
  final bool away;
  final Widget? panel;
  final Widget body;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    final insets = MediaQuery.viewPaddingOf(context);
    final canPop = ModalRoute.of(context)?.canPop ?? false;
    final ground = backgroundColor ?? theme.bgPrimary;
    final bottom = insets.bottom + _lift;
    return Scaffold(
      backgroundColor: ground,
      body: Stack(
        children: [
          // The text runs under the transparent status bar, as in the wiki
          // and Ask with their bars away; the body starts its first line
          // below it (the top padding stays in its MediaQuery).
          Positioned.fill(child: body),
          if (panel != null)
            Positioned(
              left: _edge,
              right: _edge,
              bottom: bottom + floatingDockHeight + _lift,
              child: panel!,
            ),
          Positioned(
            key: const ValueKey('page-bottom-dock'),
            left: _edge,
            right: _edge,
            bottom: bottom,
            height: floatingDockHeight,
            child: IgnorePointer(
              ignoring: away,
              child: TweenAnimationBuilder<double>(
                tween: Tween(end: away ? 1 : 0),
                duration:
                    Motion.of(context, away ? Motion.row : Motion.press * 2),
                curve: Motion.mech,
                builder: (context, t, child) => Transform.translate(
                  offset: Offset(0, (floatingDockHeight + bottom + 4) * t),
                  child: child,
                ),
                child: Row(
                  children: [
                    if (canPop) ...[
                      _Plate(
                        key: const ValueKey('page-back'),
                        tooltip:
                            MaterialLocalizations.of(context).backButtonTooltip,
                        onTap: () => Navigator.of(context).maybePop(),
                        theme: theme,
                        builder: (fg) =>
                            Icon(Icons.arrow_back_sharp, size: 22, color: fg),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Expanded(child: _titlePlate(context, theme)),
                    for (final action in actions) ...[
                      const SizedBox(width: 8),
                      _Plate(
                        key: action.key,
                        tooltip: action.tooltip,
                        onTap: action.onPressed,
                        theme: theme,
                        builder: (fg) => Icon(action.icon, size: 22, color: fg),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _titlePlate(BuildContext context, AppThemeTokens theme) => Semantics(
        header: true,
        button: onTitleTap != null,
        expanded: onTitleTap == null ? null : open,
        child: _Plate(
          key: const ValueKey('page-title'),
          onTap: onTitleTap,
          theme: theme,
          wide: true,
          builder: (fg) => Stack(
            fit: StackFit.expand,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 8, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.heading(14).copyWith(
                                  color: fg,
                                  height: 1.25,
                                ),
                          ),
                          if (status != null)
                            DefaultTextStyle.merge(
                              style: TextStyle(color: fg, height: 1.25),
                              child: status!,
                            ),
                        ],
                      ),
                    ),
                    if (onTitleTap != null)
                      AnimatedRotation(
                        turns: open ? 0.5 : 0,
                        duration: Motion.of(context, Motion.wipe),
                        curve: Motion.mech,
                        child: Icon(
                          Icons.expand_less_sharp,
                          size: 20,
                          color: fg,
                        ),
                      ),
                  ],
                ),
              ),
              if (progress != null)
                Positioned(left: 0, right: 0, bottom: 0, child: progress!),
            ],
          ),
        ),
      );
}

/// A floating plate: the panel's colour inside a hairline frame, the cut
/// corner of what can be pressed; pressed, the accent fills it.
class _Plate extends StatelessWidget {
  const _Plate({
    super.key,
    required this.theme,
    required this.onTap,
    required this.builder,
    this.tooltip,
    this.wide = false,
  });

  final AppThemeTokens theme;
  final VoidCallback? onTap;
  final Widget Function(Color fg) builder;
  final String? tooltip;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final plate = PressBuilder(
      enabled: onTap != null,
      builder: (context, down) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: withHaptic(onTap),
        child: Material(
          color: down ? theme.accentPrimary : theme.cardSurface,
          animationDuration: Motion.of(context, Motion.press),
          shape: CutBorder.br(
            onTap == null ? 0 : 8,
            side: BorderSide(color: theme.cardBorder),
          ),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            width: wide ? null : floatingDockHeight,
            height: floatingDockHeight,
            child: wide
                ? builder(down ? theme.onAccent : theme.textPrimary)
                : Center(
                    child: builder(down ? theme.onAccent : theme.textPrimary),
                  ),
          ),
        ),
      ),
    );
    if (tooltip == null) return plate;
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        excludeSemantics: true,
        child: plate,
      ),
    );
  }
}
