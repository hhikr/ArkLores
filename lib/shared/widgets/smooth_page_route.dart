import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/theme_provider.dart';
import '../theme/motion.dart';
import 'industrial_ui.dart';

/// The app's page change, a push: the new page (on its own ground, so the
/// page below never shows through) slides in whole from the right with a
/// 2px trace line on its leading edge (360 ms, slow start and hard stop);
/// the page below moves a third of the way left and dims under it. Going
/// back runs the same move the other way (240 ms). No fade, zoom or
/// bounce. With reduced motion the page just appears.
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
  final below = CurvedAnimation(
    parent: secondaryAnimation,
    curve: Motion.mech,
    reverseCurve: Motion.mech.flipped,
  );
  return Consumer(
    child: page,
    builder: (context, ref, page) {
      final tokens = ref.watch(themeProvider);
      return AnimatedBuilder(
        animation: Listenable.merge([t, below]),
        child: page,
        builder: (context, page) {
          var out = page!;
          // Covered by the page above: pushed left and dimmed.
          if (below.value > 0) {
            out = FractionalTranslation(
              translation: Offset(-_belowShift * below.value, 0),
              child: Stack(
                fit: StackFit.passthrough,
                children: [
                  out,
                  Positioned.fill(
                    child: IgnorePointer(
                      child: ColoredBox(
                        color: Colors.black
                            .withValues(alpha: _belowDim * below.value),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }
          // Coming in (or going out): slid in from the right.
          if (t.value < 1) {
            out = FractionalTranslation(
              translation: Offset(1 - t.value, 0),
              child: Stack(
                fit: StackFit.passthrough,
                children: [
                  out,
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    width: 2,
                    child: ColoredBox(color: tokens.trace),
                  ),
                ],
              ),
            );
          }
          return out;
        },
      );
    },
  );
}

/// How far the page below moves left, as a share of its width.
const _belowShift = 0.3;

/// How dark the page below gets when it is fully covered.
const _belowDim = 0.35;

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

/// A pushed page. A [MaterialPageRoute], so the theme's
/// [SmoothPageTransitionsBuilder] moves it in and the page below moves with
/// it (Flutter animates the covered page only for material routes).
PageRoute<T> smoothPageRoute<T>({
  required WidgetBuilder builder,
  RouteSettings? settings,
}) =>
    MaterialPageRoute<T>(settings: settings, builder: builder);
