import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/theme_provider.dart';
import 'industrial_ui.dart';

PageRoute<T> smoothPageRoute<T>({
  required WidgetBuilder builder,
  RouteSettings? settings,
}) {
  return PageRouteBuilder<T>(
    settings: settings,
    opaque: true,
    transitionDuration: const Duration(milliseconds: 300),
    reverseTransitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (context, animation, secondaryAnimation) => builder(context),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final eased = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return Consumer(
        builder: (context, ref, _) {
          final theme = ref.watch(themeProvider);
          return IndustrialBackdrop(
            theme: theme,
            child: ClipRect(
              child: FadeTransition(
                opacity: eased,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 0.025),
                    end: Offset.zero,
                  ).animate(eased),
                  child: child,
                ),
              ),
            ),
          );
        },
      );
    },
  );
}
