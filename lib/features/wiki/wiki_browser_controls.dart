import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/l10n/l10n.dart';
import '../../shared/providers/theme_provider.dart';
import '../../shared/theme/app_theme.dart';
import '../ai/wiki_ai_context.dart' show WikiAiTarget;
import 'wiki_toolbar.dart';

class WikiAiTargetSheet extends StatelessWidget {

  const WikiAiTargetSheet({super.key,required this.theme});
  final AppThemeTokens theme;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.cardSurface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          border: Border(top: BorderSide(color: theme.cardBorder)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.t.wikiSendToAi,
                style: theme.titleFont.copyWith(fontSize: 18),
              ),
              const SizedBox(height: 6),
              Text(
                context.t.wikiSendToAiDesc,
                style: theme.bodyFont.copyWith(
                  color: theme.textSecondary,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 12),
              TargetTile(
                theme: theme,
                icon: Icons.summarize_rounded,
                title: context.t.aiTabSummary,
                subtitle: context.t.wikiSendToSummaryDesc,
                onTap: () => Navigator.pop(context, WikiAiTarget.summary),
              ),
              TargetTile(
                theme: theme,
                icon: Icons.verified_outlined,
                title: context.t.aiTabFactCheck,
                subtitle: context.t.wikiSendToFactCheckDesc,
                onTap: () => Navigator.pop(context, WikiAiTarget.factCheck),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class TargetTile extends StatelessWidget {

  const TargetTile({super.key,
    required this.theme,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final AppThemeTokens theme;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: theme.accentPrimary),
      title: Text(title, style: theme.titleFont.copyWith(fontSize: 15)),
      subtitle: Text(
        subtitle,
        style: theme.bodyFont.copyWith(color: theme.textSecondary),
      ),
      onTap: onTap,
    );
  }
}

class ReaderToolbar extends ConsumerWidget {
  const ReaderToolbar({super.key,
    required this.visible,
    required this.isDarkMode,
    required this.onToggleDarkMode,
    required this.onDecreaseReaderFont,
    required this.onIncreaseReaderFont,
    required this.onHide,
    required this.onExitReader,
  });

  final bool visible;
  final bool isDarkMode;
  final VoidCallback onToggleDarkMode;
  final VoidCallback onDecreaseReaderFont;
  final VoidCallback onIncreaseReaderFont;
  final VoidCallback onHide;
  final VoidCallback onExitReader;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);

    return Positioned(
      left: 18,
      right: 18,
      bottom: 22,
      child: SafeArea(
        top: false,
        child: IgnorePointer(
          ignoring: !visible,
          child: AnimatedSlide(
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            offset: visible ? Offset.zero : const Offset(0, 1.2),
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 180),
              opacity: visible ? 1 : 0,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: theme.cardSurface.withValues(alpha: 0.94),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: theme.cardBorder),
                  boxShadow: theme.cardShadow,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      ReaderToolButton(
                        theme: theme,
                        icon: Icons.keyboard_arrow_down_rounded,
                        onTap: onHide,
                      ),
                      ReaderToolButton(
                        theme: theme,
                        icon: isDarkMode
                            ? Icons.light_mode_rounded
                            : Icons.dark_mode_rounded,
                        onTap: onToggleDarkMode,
                      ),
                      ReaderToolButton(
                        theme: theme,
                        label: 'A-',
                        onTap: onDecreaseReaderFont,
                      ),
                      ReaderToolButton(
                        theme: theme,
                        label: 'A+',
                        onTap: onIncreaseReaderFont,
                      ),
                      ReaderToolButton(
                        theme: theme,
                        icon: Icons.close_rounded,
                        onTap: onExitReader,
                      ),
                    ],
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

class ReaderToolButton extends StatefulWidget {
  const ReaderToolButton({super.key,
    required this.theme,
    required this.onTap,
    this.icon,
    this.label,
  });

  final AppThemeTokens theme;
  final VoidCallback onTap;
  final IconData? icon;
  final String? label;

  @override
  State<ReaderToolButton> createState() => ReaderToolButtonState();
}

class ReaderToolButtonState extends State<ReaderToolButton> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (mounted && _pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 54,
      height: 44,
      child: Semantics(
        button: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => _setPressed(true),
          onTapCancel: () => _setPressed(false),
          onTapUp: (_) => _setPressed(false),
          onTap: () {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) widget.onTap();
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
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: widget.icon != null
                    ? Icon(
                        widget.icon,
                        size: 22,
                        color: widget.theme.textPrimary,
                      )
                    : Text(
                        widget.label ?? '',
                        style: widget.theme.titleFont.copyWith(fontSize: 18),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Sizing constants for the expandable tray ───────────────────
const double _traySize = 52;
const double _trayMargin = 16;
const double _trayBottomOffset = 64;
const double _trayHeightFactor = 0.45;

/// Floating tray anchored at bottom-right that morphs between a FAB and a
/// tall vertical toolbar.
///
/// Collapsed: a small round button.
/// Expanded: the same-width container "stretches" upward into a floating
/// vertical toolbar with [WikiToolbar] inside and a close toggle at bottom.
class ExpandableTray extends ConsumerWidget {
  const ExpandableTray({super.key,
    required this.expanded,
    required this.onToggle,
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
  });

  final bool expanded;
  final VoidCallback onToggle;

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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);

    return Positioned(
      right: _trayMargin,
      bottom: _trayBottomOffset,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOutCubic,
        width: _traySize,
        height: expanded
            ? (MediaQuery.of(context).size.height * _trayHeightFactor)
            : _traySize,
        decoration: BoxDecoration(
          color: theme.cardSurface,
          borderRadius: BorderRadius.circular(expanded ? 16 : _traySize / 2),
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
                    isReaderMode: isReaderMode,
                    isBookmarked: isBookmarked,
                    onZoomOut: onZoomOut,
                    onZoomIn: onZoomIn,
                    onRefresh: onRefresh,
                    onToggleDarkMode: onToggleDarkMode,
                    onToggleReaderMode: onToggleReaderMode,
                    onDecreaseReaderFont: onDecreaseReaderFont,
                    onIncreaseReaderFont: onIncreaseReaderFont,
                    onToggleBookmark: onToggleBookmark,
                    onSendToAi: onSendToAi,
                    sendToAiTooltip: context.t.wikiSendToAi,
                    readerModeTooltip: context.t.wikiReaderMode,
                    readerFontSmallerTooltip: context.t.wikiReaderFontSmaller,
                    readerFontLargerTooltip: context.t.wikiReaderFontLarger,
                  ),
                ),
              ),

            // ── Toggle button (always visible at the bottom) ──────
            SizedBox(
              height: _traySize,
              child: IconButton(
                icon: Icon(
                  expanded ? Icons.close_rounded : Icons.tune_rounded,
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
                    borderRadius: BorderRadius.circular(14),
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
