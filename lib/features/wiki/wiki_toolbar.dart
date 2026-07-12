import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/theme/app_theme.dart';
import '../../shared/providers/theme_provider.dart';

/// Compact vertical toolbar with icon-only buttons.
///
/// Rendered inside the expandable tray in [WikiBrowserPage].
/// No outer decoration — the parent handles the container, animation, and
/// toggle button.
class WikiToolbar extends ConsumerWidget {
  const WikiToolbar({
    super.key,
    required this.canGoBack,
    required this.canGoForward,
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

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _TrayButton(icon: Icons.arrow_back_ios_rounded, theme: theme,
          enabled: canGoBack, onTap: onBack),
        _TrayButton(icon: Icons.arrow_forward_ios_rounded, theme: theme,
          enabled: canGoForward, onTap: onForward),
        _TrayButton(icon: Icons.refresh_rounded, theme: theme, onTap: onRefresh),

        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          child: Divider(color: theme.divider, height: 1),
        ),

        _TrayButton(
          icon: isDarkMode ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
          theme: theme, onTap: onToggleDarkMode,
          activeColor: theme.accentPrimary,
        ),
        _TrayButton(
          icon: isBookmarked ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
          theme: theme, onTap: onToggleBookmark,
          activeColor: isBookmarked ? theme.warning : null,
        ),
        _TrayButton(
          icon: Icons.bookmarks_rounded, theme: theme, onTap: onOpenBookmarks),
      ],
    );
  }
}

/// A single icon button inside the expandable toolbar.
class _TrayButton extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback? onTap;
  final AppThemeTokens theme;
  final Color? activeColor;

  const _TrayButton({
    required this.icon,
    required this.theme,
    this.enabled = true,
    this.onTap,
    this.activeColor,
  });

  @override
  Widget build(BuildContext context) {
    final color = !enabled
        ? theme.textSecondary.withValues(alpha: 0.3)
        : (activeColor ?? theme.textPrimary);

    return SizedBox(
      height: 44,
      child: IconButton(
        icon: Icon(icon, size: 20),
        color: color,
        disabledColor: theme.textSecondary.withValues(alpha: 0.3),
        onPressed: enabled ? onTap : null,
        padding: EdgeInsets.zero,
        splashRadius: 18,
        tooltip: null,
      ),
    );
  }
}
