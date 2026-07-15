import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/theme_provider.dart';

/// A card widget that automatically adapts its visual style to the current
/// theme (ArkTheme or EndfieldTheme).
///
/// All colors, borders, and shadows are read from [AppThemeTokens] — no
/// hardcoded values.
class ThemeAwareCard extends ConsumerWidget {
  const ThemeAwareCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin,
    this.onTap,
  });

  /// The content placed inside the card.
  final Widget child;

  /// Padding around the child inside the card.
  final EdgeInsetsGeometry padding;

  /// Margin around the card (optional).
  final EdgeInsetsGeometry? margin;

  /// Optional tap callback. When provided, the card acts like an inkwell.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);

    final card = ClipPath(
      clipper: _CutCornerClipper(theme.cornerCut),
      child: Material(
        color: theme.cardSurface,
        child: InkWell(
          onTap: onTap,
          overlayColor: WidgetStatePropertyAll(
            theme.accentPrimary.withValues(alpha: 0.08),
          ),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );

    return Container(
      margin: margin,
      decoration: BoxDecoration(boxShadow: theme.cardShadow),
      child: CustomPaint(
        foregroundPainter: _IndustrialBorderPainter(
          border: theme.cardBorder,
          accent: theme.accentPrimary,
          cut: theme.cornerCut,
          endfield: theme.isEndfield,
        ),
        child: card,
      ),
    );
  }
}

class _CutCornerClipper extends CustomClipper<Path> {
  const _CutCornerClipper(this.cut);

  final double cut;

  @override
  Path getClip(Size size) => Path()
    ..moveTo(cut, 0)
    ..lineTo(size.width, 0)
    ..lineTo(size.width, size.height - cut)
    ..lineTo(size.width - cut, size.height)
    ..lineTo(0, size.height)
    ..lineTo(0, cut)
    ..close();

  @override
  bool shouldReclip(covariant _CutCornerClipper oldClipper) =>
      cut != oldClipper.cut;
}

class _IndustrialBorderPainter extends CustomPainter {
  const _IndustrialBorderPainter({
    required this.border,
    required this.accent,
    required this.cut,
    required this.endfield,
  });

  final Color border;
  final Color accent;
  final double cut;
  final bool endfield;

  @override
  void paint(Canvas canvas, Size size) {
    final borderPaint = Paint()
      ..color = border
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final path = Path()
      ..moveTo(cut, 0.5)
      ..lineTo(size.width - 0.5, 0.5)
      ..lineTo(size.width - 0.5, size.height - cut)
      ..lineTo(size.width - cut, size.height - 0.5)
      ..lineTo(0.5, size.height - 0.5)
      ..lineTo(0.5, cut)
      ..close();
    canvas.drawPath(path, borderPaint);

    final accentPaint = Paint()
      ..color = accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = endfield ? 2 : 1.5;
    canvas.drawLine(Offset(cut, 0.5), Offset(cut + 28, 0.5), accentPaint);
    if (endfield) {
      canvas.drawLine(
        Offset(size.width - 18, size.height - 0.5),
        Offset(size.width - cut, size.height - 0.5),
        accentPaint,
      );
    } else {
      canvas.drawLine(Offset(0.5, cut), Offset(0.5, cut + 18), accentPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _IndustrialBorderPainter oldDelegate) =>
      border != oldDelegate.border ||
      accent != oldDelegate.accent ||
      cut != oldDelegate.cut ||
      endfield != oldDelegate.endfield;
}
