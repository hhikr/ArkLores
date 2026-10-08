import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/theme_provider.dart';
import 'industrial_ui.dart';

/// The app's page change, after the games' panels: the new page (with its
/// backdrop) slides in a short way from the right while it fades in, fast
/// at first and settling without overshoot; the page below shifts a little
/// to the left as it is covered (and comes back when the new page leaves).
/// Straight moves, no zoom or bounce, so the tap that opened a page
/// visibly leads somewhere.
Widget smoothPageTransition(
  Animation<double> animation,
  Animation<double> secondaryAnimation,
  Widget child,
) {
  final enter = CurvedAnimation(
    parent: animation,
    curve: Curves.easeOutExpo,
    reverseCurve: Curves.easeInCubic,
  );
  final covered = CurvedAnimation(
    parent: secondaryAnimation,
    curve: Curves.easeOutExpo,
    reverseCurve: Curves.easeInCubic,
  );
  return SlideTransition(
    position: Tween<Offset>(begin: Offset.zero, end: const Offset(-0.04, 0))
        .animate(covered),
    child: FadeTransition(
      opacity: enter,
      child: SlideTransition(
        position:
            Tween<Offset>(begin: const Offset(0.08, 0), end: Offset.zero)
                .animate(enter),
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
    transitionDuration: const Duration(milliseconds: 300),
    reverseTransitionDuration: const Duration(milliseconds: 200),
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
