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

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: margin,
        padding: padding,
        decoration: BoxDecoration(
          color: theme.cardSurface,
          borderRadius: theme.cardRadius,
          border: Border.all(
            color: theme.cardBorder,
            width: 1,
          ),
          boxShadow: theme.cardShadow,
        ),
        child: child,
      ),
    );
  }
}
