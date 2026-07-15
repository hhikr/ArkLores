import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

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
      child: CustomPaint(
        painter: _BackdropPainter(theme),
        child: child,
      ),
    );
  }
}

class IndustrialPageHeader extends StatelessWidget {
  const IndustrialPageHeader({
    super.key,
    required this.theme,
    required this.title,
    required this.code,
    this.icon,
  });

  final AppThemeTokens theme;
  final String title;
  final String code;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      child: Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 24),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Container(width: 5, height: 54, color: theme.accentPrimary),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    code.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.bodyFont.copyWith(
                      color: theme.textMuted,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.titleFont.copyWith(
                      color: theme.textPrimary,
                      fontSize: 32,
                      height: 1.1,
                    ),
                  ),
                ],
              ),
            ),
            if (icon != null)
              Icon(
                icon,
                size: 42,
                color: theme.textMuted.withValues(alpha: 0.38),
              ),
          ],
        ),
      ),
    );
  }
}

class IndustrialSectionHeader extends StatelessWidget {
  const IndustrialSectionHeader({
    super.key,
    required this.theme,
    required this.title,
    required this.code,
  });

  final AppThemeTokens theme;
  final String title;
  final String code;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 10),
        child: Row(
          children: [
            ClipPath(
              clipper: const _MarkerClipper(),
              child: Container(
                width: 10,
                height: 24,
                color: theme.accentPrimary,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.titleFont.copyWith(fontSize: 20),
              ),
            ),
            if (constraints.maxWidth >= 480) ...[
              const SizedBox(width: 12),
              SizedBox(width: 72, child: Divider(color: theme.divider)),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  code.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.bodyFont.copyWith(
                    color: theme.textMuted,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MarkerClipper extends CustomClipper<Path> {
  const _MarkerClipper();

  @override
  Path getClip(Size size) => Path()
    ..moveTo(size.width, 0)
    ..lineTo(size.width, size.height)
    ..lineTo(0, size.height)
    ..lineTo(size.width * 0.55, 0)
    ..close();

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

class _BackdropPainter extends CustomPainter {
  const _BackdropPainter(this.theme);

  final AppThemeTokens theme;

  @override
  void paint(Canvas canvas, Size size) {
    const spacing = 48.0;
    final baseAlpha = theme.isEndfield ? 0.17 : 0.2;
    var index = 0;
    for (double x = 0; x < size.width; x += spacing, index++) {
      final major = index % 4 == 0;
      final paint = Paint()
        ..color = theme.divider.withValues(
          alpha: baseAlpha * (major ? 1.7 : 0.65 + (index % 3) * 0.18),
        )
        ..strokeWidth = major ? 1.8 : 1.05;
      final breakStart = 210.0 + (index % 3) * 54;
      canvas.drawLine(Offset(x, 0), Offset(x, breakStart), paint);
      canvas.drawLine(
        Offset(x, breakStart + 38 + (index % 2) * 26),
        Offset(x, size.height),
        paint,
      );
    }

    index = 0;
    for (double y = 0; y < size.height; y += spacing, index++) {
      final major = index % 5 == 0;
      final paint = Paint()
        ..color = theme.divider.withValues(
          alpha: baseAlpha * (major ? 1.55 : 0.55 + (index % 4) * 0.13),
        )
        ..strokeWidth = major ? 1.7 : 1.0;
      final gapStart = size.width * (0.18 + (index % 4) * 0.12);
      canvas.drawLine(Offset(0, y), Offset(gapStart, y), paint);
      canvas.drawLine(
        Offset(gapStart + 26 + (index % 3) * 18, y),
        Offset(size.width, y),
        paint,
      );
    }

    final perspective = Paint()
      ..color = theme.divider.withValues(alpha: baseAlpha * 0.68)
      ..strokeWidth = 1.05;
    final vanishingPoint = Offset(size.width * 0.68, size.height * 0.16);
    for (var i = -2; i <= 5; i++) {
      canvas.drawLine(
        Offset(size.width * i / 3, size.height),
        vanishingPoint,
        perspective,
      );
    }

    final panel = Paint()
      ..color = theme.surfaceElevated.withValues(alpha: 0.035)
      ..style = PaintingStyle.fill;
    canvas.drawRect(
      Rect.fromLTWH(
        size.width * 0.52,
        math.min(size.height * 0.42, 520),
        size.width * 0.38,
        math.min(190, size.height * 0.12),
      ),
      panel,
    );

    final signal = Paint()
      ..color = theme.accentPrimary.withValues(alpha: 0.32)
      ..strokeWidth = 2;
    canvas.drawLine(
      Offset(size.width * 0.64, 0),
      Offset(size.width, size.width * 0.36),
      signal,
    );
    canvas.drawLine(
      Offset(size.width * 0.79, 0),
      Offset(size.width, size.width * 0.21),
      signal..strokeWidth = 1.2,
    );
  }

  @override
  bool shouldRepaint(covariant _BackdropPainter oldDelegate) =>
      oldDelegate.theme.themeName != theme.themeName;
}
