import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/theme_provider.dart';
import '../theme/motion.dart';
import 'industrial_ui.dart';

/// The app's page change, a shutter: the new page (on its own ground, so
/// the page below never shows through) comes in from the right behind a
/// slanted edge (360 ms, slow start and hard stop); the page below stays
/// where it is and is covered. Going back opens the shutter the other way
/// (240 ms). No fade, zoom or bounce. With reduced motion the page just
/// appears.
Widget smoothPageTransition(
  BuildContext context,
  Animation<double> animation,
  Animation<double> secondaryAnimation,
  Widget child,
) {
  final page = Consumer(
    child: child,
    builder: (context, ref, child) => IndustrialBackdrop(
      theme: ref.watch(themeProvider),
      child: child!,
    ),
  );
  if (Motion.reduced(context)) return page;
  final t = CurvedAnimation(
    parent: animation,
    curve: Motion.mech,
    reverseCurve: Motion.mech.flipped,
  );
  return AnimatedBuilder(
    animation: t,
    child: page,
    builder: (context, child) => t.value >= 1
        ? child!
        : ClipPath(clipper: _ShutterClipper(t.value), child: child),
  );
}

/// The visible part of a page coming in: everything right of a slanted
/// edge that sweeps from the right edge (0) past the left one (1).
class _ShutterClipper extends CustomClipper<Path> {
  const _ShutterClipper(this.t);

  final double t;

  @override
  Path getClip(Size size) {
    final slant = size.width * 0.35;
    final x = size.width - t * (size.width + slant);
    return Path()
      ..moveTo(x + slant, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(x, size.height)
      ..close();
  }

  @override
  bool shouldReclip(_ShutterClipper old) => old.t != t;
}

/// [smoothPageTransition] for every route (`MaterialPageRoute`, named
/// routes, the home route), set in the theme's `pageTransitionsTheme`.
class SmoothPageTransitionsBuilder extends PageTransitionsBuilder {
  const SmoothPageTransitionsBuilder();

  @override
  Duration get transitionDuration => Motion.shutter;

  @override
  Duration get reverseTransitionDuration => Motion.shutterOut;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) =>
      smoothPageTransition(context, animation, secondaryAnimation, child);
}

PageRoute<T> smoothPageRoute<T>({
  required WidgetBuilder builder,
  RouteSettings? settings,
}) {
  return PageRouteBuilder<T>(
    settings: settings,
    opaque: true,
    transitionDuration: Motion.shutter,
    reverseTransitionDuration: Motion.shutterOut,
    pageBuilder: (context, animation, secondaryAnimation) => builder(context),
    transitionsBuilder: smoothPageTransition,
  );
}
