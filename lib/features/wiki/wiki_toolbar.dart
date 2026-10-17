import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/providers/theme_provider.dart';
import '../../shared/theme/app_theme.dart';

/// Compact vertical toolbar with icon-only buttons.
///
/// Rendered inside the expandable tray in [WikiBrowserPage].
/// No outer decoration — the parent handles the container, animation, and
/// toggle button.
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
      children: [
        _TrayButton(
          icon: Icons.zoom_out_sharp,
          theme: theme,
          onTap: onZoomOut,
        ),
        _TrayButton(icon: Icons.zoom_in_sharp, theme: theme, onTap: onZoomIn),
        _TrayButton(
          icon: Icons.refresh_sharp,
          theme: theme,
          onTap: onRefresh,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          child: Divider(color: theme.divider, height: 1),
        ),
        _TrayButton(
          icon: isDarkMode ? Icons.light_mode_sharp : Icons.dark_mode_sharp,
          theme: theme,
          onTap: onToggleDarkMode,
          activeColor: theme.accentPrimary,
        ),
        _TrayButton(
          icon:
              isBookmarked ? Icons.bookmark_sharp : Icons.bookmark_border_sharp,
          theme: theme,
          onTap: onToggleBookmark,
          activeColor: isBookmarked ? theme.warning : null,
        ),
      ],
    );
  }
}

/// A single icon button inside the expandable toolbar.
class _TrayButton extends StatefulWidget {
  const _TrayButton({
    required this.icon,
    required this.theme,
    this.onTap,
    this.activeColor,
  });
  final IconData icon;
  final VoidCallback? onTap;
  final AppThemeTokens theme;
  final Color? activeColor;

  @override
  State<_TrayButton> createState() => _TrayButtonState();
}

class _TrayButtonState extends State<_TrayButton> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (mounted && _pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.activeColor ?? widget.theme.textPrimary;

    return SizedBox(
      height: 44,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _setPressed(true),
        onTapCancel: () => _setPressed(false),
        onTapUp: (_) => _setPressed(false),
        onTap: () {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) widget.onTap?.call();
          });
        },
        child: AnimatedScale(
          scale: _pressed ? 0.9 : 1,
          duration: const Duration(milliseconds: 110),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 110),
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              color: _pressed
                  ? widget.theme.accentPrimary.withValues(alpha: 0.14)
                  : Colors.transparent,
              borderRadius: BorderRadius.zero,
            ),
            child: Center(
              child: Icon(widget.icon, size: 20, color: color),
            ),
          ),
        ),
      ),
    );
  }
}
