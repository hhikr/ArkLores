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
    required this.isDarkMode,
    required this.isReaderMode,
    required this.isBookmarked,
    required this.onZoomOut,
    required this.onZoomIn,
    required this.onRefresh,
    required this.onToggleDarkMode,
    required this.onToggleReaderMode,
    required this.onDecreaseReaderFont,
    required this.onIncreaseReaderFont,
    required this.onToggleBookmark,
    required this.onSendToAi,
    required this.sendToAiTooltip,
    required this.readerModeTooltip,
    required this.readerFontSmallerTooltip,
    required this.readerFontLargerTooltip,
  });

  final bool isDarkMode;
  final bool isReaderMode;
  final bool isBookmarked;

  final VoidCallback onZoomOut;
  final VoidCallback onZoomIn;
  final VoidCallback onRefresh;
  final VoidCallback onToggleDarkMode;
  final VoidCallback onToggleReaderMode;
  final VoidCallback onDecreaseReaderFont;
  final VoidCallback onIncreaseReaderFont;
  final VoidCallback onToggleBookmark;
  final VoidCallback onSendToAi;
  final String sendToAiTooltip;
  final String readerModeTooltip;
  final String readerFontSmallerTooltip;
  final String readerFontLargerTooltip;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _TrayButton(
            icon: Icons.zoom_out_rounded, theme: theme, onTap: onZoomOut),
        _TrayButton(icon: Icons.zoom_in_rounded, theme: theme, onTap: onZoomIn),
        _TrayButton(
            icon: Icons.refresh_rounded, theme: theme, onTap: onRefresh),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          child: Divider(color: theme.divider, height: 1),
        ),
        _TrayButton(
          icon: isDarkMode ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
          theme: theme,
          onTap: onToggleDarkMode,
          activeColor: theme.accentPrimary,
        ),
        _TrayButton(
          icon: isReaderMode
              ? Icons.chrome_reader_mode_rounded
              : Icons.chrome_reader_mode_outlined,
          theme: theme,
          onTap: onToggleReaderMode,
          activeColor: isReaderMode ? theme.accentPrimary : null,
          tooltip: readerModeTooltip,
        ),
        if (isReaderMode) ...[
          _TrayButton(
            icon: Icons.text_decrease_rounded,
            theme: theme,
            onTap: onDecreaseReaderFont,
            tooltip: readerFontSmallerTooltip,
          ),
          _TrayButton(
            icon: Icons.text_increase_rounded,
            theme: theme,
            onTap: onIncreaseReaderFont,
            tooltip: readerFontLargerTooltip,
          ),
        ],
        _TrayButton(
          icon: isBookmarked
              ? Icons.bookmark_rounded
              : Icons.bookmark_border_rounded,
          theme: theme,
          onTap: onToggleBookmark,
          activeColor: isBookmarked ? theme.warning : null,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          child: Divider(color: theme.divider, height: 1),
        ),
        _TrayButton(
          icon: Icons.psychology_alt_rounded,
          theme: theme,
          onTap: onSendToAi,
          activeColor: theme.accentPrimary,
          tooltip: sendToAiTooltip,
        ),
      ],
    );
  }
}

/// A single icon button inside the expandable toolbar.
class _TrayButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final AppThemeTokens theme;
  final Color? activeColor;
  final String? tooltip;

  const _TrayButton({
    required this.icon,
    required this.theme,
    this.onTap,
    this.activeColor,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final color = activeColor ?? theme.textPrimary;

    return SizedBox(
      height: 44,
      child: IconButton(
        icon: Icon(icon, size: 20),
        color: color,
        onPressed: onTap,
        padding: EdgeInsets.zero,
        splashRadius: 18,
        tooltip: tooltip,
      ),
    );
  }
}
