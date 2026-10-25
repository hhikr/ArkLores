import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/l10n/l10n.dart';
import '../../shared/providers/theme_provider.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/theme/motion.dart';
import '../../shared/widgets/press_feedback.dart';

/// The page tools of the wiki: one labelled row per tool (an icon alone does
/// not say what it does). Rendered inside the tray in [WikiBrowserPage]; the
/// parent draws the panel and the toggle.
class WikiToolbar extends ConsumerWidget {
  const WikiToolbar({
    super.key,
    required this.isDarkMode,
    required this.isBookmarked,
    required this.onZoomOut,
    required this.onZoomIn,
    required this.onRefresh,
    required this.onToggleDarkMode,
    required this.onToggleBookmark,
  });

  final bool isDarkMode;
  final bool isBookmarked;

  final VoidCallback onZoomOut;
  final VoidCallback onZoomIn;
  final VoidCallback onRefresh;
  final VoidCallback onToggleDarkMode;
  final VoidCallback onToggleBookmark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ToolRow(
          key: const ValueKey('wiki-tool-zoom-out'),
          icon: Icons.text_decrease_sharp,
          label: context.t.wikiZoomOut,
          theme: theme,
          onTap: onZoomOut,
        ),
        _ToolRow(
          key: const ValueKey('wiki-tool-zoom-in'),
          icon: Icons.text_increase_sharp,
          label: context.t.wikiZoomIn,
          theme: theme,
          onTap: onZoomIn,
        ),
        _ToolRow(
          key: const ValueKey('wiki-tool-refresh'),
          icon: Icons.refresh_sharp,
          label: context.t.wikiRefresh,
          theme: theme,
          onTap: onRefresh,
        ),
        Divider(color: theme.divider, height: 1),
        _ToolRow(
          key: const ValueKey('wiki-tool-dark'),
          icon: Icons.dark_mode_sharp,
          label: context.t.wikiDarkPage,
          theme: theme,
          on: isDarkMode,
          onTap: onToggleDarkMode,
        ),
        _ToolRow(
          key: const ValueKey('wiki-tool-bookmark'),
          icon: isBookmarked ? Icons.bookmark_sharp : Icons.bookmark_border_sharp,
          label: isBookmarked
              ? context.t.wikiBookmarkRemove
              : context.t.wikiBookmarkAdd,
          theme: theme,
          on: isBookmarked,
          onTap: onToggleBookmark,
        ),
      ],
    );
  }
}

/// One tool: an icon and what it does, 48 high; the accent wipes in while it
/// is pressed. [on] marks a tool that is switched on (an accent block on its
/// left).
class _ToolRow extends StatefulWidget {
  const _ToolRow({
    super.key,
    required this.icon,
    required this.label,
    required this.theme,
    required this.onTap,
    this.on,
  });

  final IconData icon;
  final String label;
  final AppThemeTokens theme;
  final VoidCallback onTap;

  /// Null: not a switch.
  final bool? on;

  @override
  State<_ToolRow> createState() => _ToolRowState();
}

class _ToolRowState extends State<_ToolRow> with PressHold<_ToolRow> {
  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final down = pressed;
    final fg = down ? theme.onAccent : theme.textPrimary;
    return Semantics(
      button: true,
      toggled: widget.on,
      child: pressListener(
        enabled: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            HapticFeedback.selectionClick();
            widget.onTap();
          },
          child: SizedBox(
            height: 48,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: AnimatedFractionallySizedBox(
                    duration: Motion.of(context, down ? Motion.press : Motion.wipe),
                    curve: Motion.mech,
                    widthFactor: down ? 1 : 0,
                    heightFactor: 1,
                    child: ColoredBox(color: theme.accentPrimary),
                  ),
                ),
                if (widget.on ?? false)
                  Positioned(
                    left: 0,
                    top: 10,
                    bottom: 10,
                    width: 4,
                    child: ColoredBox(color: theme.trace),
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Row(
                    children: [
                      Icon(widget.icon, size: 20, color: fg),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          widget.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.ui(
                            15,
                            weight: (widget.on ?? false) ? 700 : 500,
                            color: fg,
                          ),
                        ),
                      ),
                    ],
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
