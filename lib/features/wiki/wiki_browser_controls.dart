import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/l10n/l10n.dart';
import '../../shared/providers/theme_provider.dart';
import '../../shared/theme/motion.dart';
import '../../shared/widgets/ef_widgets.dart';
import '../../shared/widgets/page_frame.dart';
import 'wiki_toolbar.dart';

const double _trayMargin = 12;
const double _trayWidth = 200;

/// The wiki's page tools, anchored at the bottom right: a square button with
/// a cut corner; tapped, a panel with the labelled tools opens above it
/// (pushed up from the button, mechanically) and the button closes it.
class ExpandableTray extends ConsumerWidget {
  const ExpandableTray({
    super.key,
    required this.expanded,
    required this.onToggle,
    required this.isDarkMode,
    required this.isBookmarked,
    required this.onZoomOut,
    required this.onZoomIn,
    required this.onRefresh,
    required this.onToggleDarkMode,
    required this.onToggleBookmark,
  });

  final bool expanded;
  final VoidCallback onToggle;

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
    return Positioned(
      right: _trayMargin,
      // Above the tab bar (the page reaches under it).
      bottom: _trayMargin + MediaQuery.paddingOf(context).bottom,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          AnimatedSize(
            duration: Motion.of(
              context,
              expanded ? Motion.sheetIn : Motion.sheetOut,
            ),
            curve: expanded ? Motion.snap : Motion.mech,
            alignment: Alignment.bottomRight,
            child: expanded
                ? Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: SizedBox(
                      width: _trayWidth,
                      child: DockPanel(
                        key: const ValueKey('wiki-tools'),
                        theme: theme,
                        padding: const EdgeInsets.only(top: 3),
                        child: WikiToolbar(
                          isDarkMode: isDarkMode,
                          isBookmarked: isBookmarked,
                          onZoomOut: onZoomOut,
                          onZoomIn: onZoomIn,
                          onRefresh: onRefresh,
                          onToggleDarkMode: onToggleDarkMode,
                          onToggleBookmark: onToggleBookmark,
                        ),
                      ),
                    ),
                  )
                : const SizedBox(width: 0, height: 0),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              color: theme.cardSurface,
              border: Border.all(color: theme.divider),
            ),
            child: SquareIconButton(
              key: const ValueKey('wiki-tools-toggle'),
              icon: expanded ? Icons.close_sharp : Icons.tune_sharp,
              tooltip: expanded ? context.t.wikiToolsClose : context.t.wikiTools,
              selected: expanded,
              onPressed: onToggle,
            ),
          ),
        ],
      ),
    );
  }
}
