import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/theme/app_theme.dart';
import '../../shared/providers/theme_provider.dart';

/// Custom toolbar for the Wiki browser.
///
/// Displays navigation controls (back / forward / refresh), a page title
/// preview, and actions (dark-mode toggle, bookmark toggle, bookmark list).
/// All colors are driven by [AppThemeTokens] — no hardcoded values.
class WikiToolbar extends ConsumerWidget {
  const WikiToolbar({
    super.key,
    required this.canGoBack,
    required this.canGoForward,
    required this.currentTitle,
    required this.isDarkMode,
    required this.isBookmarked,
    required this.onBack,
    required this.onForward,
    required this.onRefresh,
    required this.onToggleDarkMode,
    required this.onToggleBookmark,
    required this.onOpenBookmarks,
  });

  final bool canGoBack;
  final bool canGoForward;
  final String currentTitle;
  final bool isDarkMode;
  final bool isBookmarked;

  final VoidCallback onBack;
  final VoidCallback onForward;
  final VoidCallback onRefresh;
  final VoidCallback onToggleDarkMode;
  final VoidCallback onToggleBookmark;
  final VoidCallback onOpenBookmarks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);

    return Container(
      padding: EdgeInsets.only(
        top: 0,
        bottom: 4,
        left: 4,
        right: 4,
      ),
      decoration: BoxDecoration(
        color: theme.bgSecondary,
        border: Border(
          bottom: BorderSide(
            color: theme.divider,
            width: 0.5,
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Action row ──────────────────────────────────────
          Row(
            children: [
              // Back
              _ToolbarIconButton(
                icon: Icons.arrow_back_ios_rounded,
                enabled: canGoBack,
                onPressed: onBack,
                theme: theme,
              ),
              // Forward
              _ToolbarIconButton(
                icon: Icons.arrow_forward_ios_rounded,
                enabled: canGoForward,
                onPressed: onForward,
                theme: theme,
              ),
              // Refresh
              _ToolbarIconButton(
                icon: Icons.refresh_rounded,
                enabled: true,
                onPressed: onRefresh,
                theme: theme,
              ),

              const Spacer(),

              // Dark mode toggle
              _ToolbarIconButton(
                icon: isDarkMode
                    ? Icons.light_mode_rounded
                    : Icons.dark_mode_rounded,
                enabled: true,
                onPressed: onToggleDarkMode,
                theme: theme,
                activeColor: theme.accentPrimary,
              ),

              // Bookmark toggle
              _ToolbarIconButton(
                icon: isBookmarked
                    ? Icons.bookmark_rounded
                    : Icons.bookmark_border_rounded,
                enabled: true,
                onPressed: onToggleBookmark,
                theme: theme,
                activeColor: isBookmarked ? theme.warning : null,
              ),

              // Bookmark list
              _ToolbarIconButton(
                icon: Icons.bookmarks_rounded,
                enabled: true,
                onPressed: onOpenBookmarks,
                theme: theme,
              ),
            ],
          ),

          // ── Page title (truncated) ─────────────────────────
          if (currentTitle.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                currentTitle,
                style: theme.bodyFont.copyWith(
                  fontSize: 11,
                  color: theme.textSecondary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
    );
  }
}

/// A single icon button in the toolbar.
///
/// Disabled buttons are dimmed and non-interactive.
class _ToolbarIconButton extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback onPressed;
  final AppThemeTokens theme;
  final Color? activeColor;

  const _ToolbarIconButton({
    required this.icon,
    required this.enabled,
    required this.onPressed,
    required this.theme,
    this.activeColor,
  });

  @override
  Widget build(BuildContext context) {
    final color = !enabled
        ? theme.textSecondary.withValues(alpha: 0.3)
        : (activeColor ?? theme.textPrimary);

    return SizedBox(
      width: 40,
      height: 40,
      child: IconButton(
        icon: Icon(icon, size: 20),
        color: color,
        disabledColor: theme.textSecondary.withValues(alpha: 0.3),
        onPressed: enabled ? onPressed : null,
        padding: EdgeInsets.zero,
        splashRadius: 18,
        tooltip: null,
      ),
    );
  }
}
