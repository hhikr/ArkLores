import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'ef_widgets.dart';

/// The app's ground: the paper, with two faint patches of open contour
/// lines in opposite corners (the only texture there is). The lines are a
/// layer of their own behind [child]: what repaints in the page (a fading
/// barrier, a moving page) does not draw them again.
class IndustrialBackdrop extends StatelessWidget {
  const IndustrialBackdrop({
    super.key,
    required this.theme,
    required this.child,
  });

  final AppThemeTokens theme;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: theme.bgPrimary,
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          Positioned.fill(
            child: RepaintBoundary(
              child: CustomPaint(
                painter: ContourPainter(
                  theme.textPrimary
                      .withValues(alpha: theme.isDark ? 0.07 : 0.08),
                ),
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

/// A section's heading: `// CODE` small above, the Chinese bold below.
class IndustrialSectionHeader extends StatelessWidget {
  const IndustrialSectionHeader({
    super.key,
    required this.theme,
    required this.title,
    required this.code,
    this.trailing,
  });

  final AppThemeTokens theme;
  final String title;
  final String code;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) =>
      SectionTitle(title: title, code: code, trailing: trailing);
}
