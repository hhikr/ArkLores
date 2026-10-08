import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/theme_provider.dart';
import 'industrial_ui.dart';

/// The app's page change: the new page (with its backdrop) fades in while
/// growing from 94 %, and the page below eases back to 96 % as it is
/// covered (and returns when the new page leaves). Both pages are seen
/// moving, so the tap that opened a page visibly leads somewhere.
Widget smoothPageTransition(
  Animation<double> animation,
  Animation<double> secondaryAnimation,
  Widget child,
) {
  final enter = CurvedAnimation(
    parent: animation,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );
  final covered = CurvedAnimation(
    parent: secondaryAnimation,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );
  return ScaleTransition(
    scale: Tween<double>(begin: 1, end: 0.96).animate(covered),
    child: FadeTransition(
      opacity: enter,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.94, end: 1).animate(enter),
        child: child,
      ),
    ),
  );
}

/// [smoothPageTransition] for every route (`MaterialPageRoute`, named
/// routes, the home route), set in the theme's `pageTransitionsTheme`.
class SmoothPageTransitionsBuilder extends PageTransitionsBuilder {
  const SmoothPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) =>
      smoothPageTransition(animation, secondaryAnimation, child);
}

PageRoute<T> smoothPageRoute<T>({
  required WidgetBuilder builder,
  RouteSettings? settings,
}) {
  return PageRouteBuilder<T>(
    settings: settings,
    opaque: true,
    transitionDuration: const Duration(milliseconds: 320),
    reverseTransitionDuration: const Duration(milliseconds: 240),
    pageBuilder: (context, animation, secondaryAnimation) => builder(context),
    transitionsBuilder: (context, animation, secondaryAnimation, child) =>
        smoothPageTransition(
      animation,
      secondaryAnimation,
      Consumer(
        builder: (context, ref, _) => IndustrialBackdrop(
          theme: ref.watch(themeProvider),
          child: child,
        ),
      ),
    ),
  );
}
