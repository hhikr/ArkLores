import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/providers/theme_provider.dart';
import 'wiki_toolbar.dart';

// ─── Sizing constants for the expandable tray ───────────────────
const double _traySize = 52;
const double _trayMargin = 16;
const double _trayBottomOffset = 64;
const double _trayHeightFactor = 0.45;

/// Floating tray anchored at bottom-right that morphs between a FAB and a
/// tall vertical toolbar.
///
/// Collapsed: a small square button.
/// Expanded: the same-width container "stretches" upward into a floating
/// vertical toolbar with [WikiToolbar] inside and a close toggle at bottom.
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
      // Above the floating navigation (the page reaches under it).
      bottom: _trayBottomOffset + MediaQuery.paddingOf(context).bottom,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOutCubic,
        width: _traySize,
        height: expanded
            ? (MediaQuery.of(context).size.height * _trayHeightFactor)
            : _traySize,
        decoration: BoxDecoration(
          color: theme.cardSurface,
          borderRadius: BorderRadius.zero,
          boxShadow: theme.cardShadow,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Toolbar buttons (only when expanded) ──────────────
            if (expanded)
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(vertical: 4),
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

            // ── Toggle button (always visible at the bottom) ──────
            SizedBox(
              height: _traySize,
              child: IconButton(
                icon: Icon(
                  expanded ? Icons.close_sharp : Icons.tune_sharp,
                  size: 22,
                ),
                color: theme.textPrimary,
                onPressed: onToggle,
                padding: EdgeInsets.zero,
                tooltip: expanded ? 'Close' : 'Tools',
                style: IconButton.styleFrom(
                  splashFactory: NoSplash.splashFactory,
                  overlayColor: theme.accentPrimary.withValues(alpha: 0.12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.zero,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
