import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/l10n.dart';
import '../providers/theme_provider.dart';
import '../theme/app_theme.dart';
import '../theme/motion.dart';
import 'ef_widgets.dart';

/// Whether the app opens with [LaunchCurtain]: only when main() starts it
/// (tests build the app without it).
final launchCurtainProvider = Provider<bool>((ref) => false);

/// The opening, over the app while its first screen is built behind it.
/// The system's splash is plain paper (Android 12+ shows only an icon
/// there); on it an accent block wipes in from the left and leaves to the
/// right, uncovering ARKLORES as it goes; the three-colour strip runs out
/// under the word, a line says what the app is, and the paper fades away.
/// Under 1 s in, a short hold, ~0.3 s out; nothing with reduced motion.
class LaunchCurtain extends ConsumerStatefulWidget {
  const LaunchCurtain({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<LaunchCurtain> createState() => _LaunchCurtainState();
}

class _LaunchCurtainState extends ConsumerState<LaunchCurtain>
    with SingleTickerProviderStateMixin {
  static const _total = 1500.0;

  late final AnimationController _run = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );
  late bool _done = !ref.read(launchCurtainProvider);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_done || _run.isAnimating) return;
    if (Motion.reduced(context)) {
      _done = true;
      return;
    }
    _run.forward().whenComplete(() {
      if (mounted) setState(() => _done = true);
    });
  }

  @override
  void dispose() {
    _run.dispose();
    super.dispose();
  }

  /// The part of the run from [from] to [to] ms, through [curve].
  double _part(double from, double to, Curve curve) => curve.transform(
        ((_run.value * _total - from) / (to - from)).clamp(0.0, 1.0),
      );

  @override
  Widget build(BuildContext context) {
    if (_done) return widget.child;
    final theme = ref.watch(themeProvider);
    final word = sairaStyle(
      size: 52,
      weight: 900,
      width: 125,
      spacing: 0.04,
      height: 1.05,
      color: theme.textPrimary,
    );
    // The strip and the line under the word are as wide as it.
    final width = (TextPainter(
      text: TextSpan(text: 'ARKLORES', style: word),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
    )..layout())
        .width;
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        AbsorbPointer(
          child: ExcludeSemantics(
            child: AnimatedBuilder(
              animation: _run,
              builder: (context, _) {
                final blockIn = _part(0, 330, Motion.mech);
                final blockOut = _part(300, 660, Motion.mech);
                final slide = _part(300, 700, Motion.snap);
                final strip = _part(560, 900, Motion.mech);
                final line = _part(700, 980, Motion.snap);
                final exit = _part(1240, 1500, Motion.mech);
                return Opacity(
                  opacity: 1 - exit,
                  child: ColoredBox(
                    color: theme.bgPrimary,
                    child: Center(
                      child: Transform.translate(
                        offset: Offset(24 * exit, 0),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 32),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: SizedBox(
                              width: width,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Stack(
                                    children: [
                                      // Uncovered where the block has been.
                                      ClipRect(
                                        clipper: _Upto(blockOut),
                                        child: Transform.translate(
                                          offset: Offset(-20 * (1 - slide), 0),
                                          child: Text('ARKLORES', style: word),
                                        ),
                                      ),
                                      Positioned.fill(
                                        child: CustomPaint(
                                          painter: _Block(
                                            from: blockOut,
                                            to: blockIn,
                                            color: theme.accentPrimary,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 14),
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: SizedBox(
                                      width: width * strip,
                                      child: const TriStrip(),
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  Opacity(
                                    opacity: line,
                                    child: Transform.translate(
                                      offset: Offset(0, 8 * (1 - line)),
                                      child: Text(
                                        context.t.launchTagline,
                                        style: theme.label(size: 13),
                                      ),
                                    ),
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
              },
            ),
          ),
        ),
      ],
    );
  }
}

/// The left [fraction] of the box.
class _Upto extends CustomClipper<Rect> {
  const _Upto(this.fraction);

  final double fraction;

  @override
  Rect getClip(Size size) =>
      Rect.fromLTWH(0, 0, size.width * fraction, size.height);

  @override
  bool shouldReclip(_Upto old) => old.fraction != fraction;
}

/// The accent block between [from] and [to] (fractions of the width).
class _Block extends CustomPainter {
  const _Block({required this.from, required this.to, required this.color});

  final double from;
  final double to;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (to <= from) return;
    canvas.drawRect(
      Rect.fromLTRB(size.width * from, 0, size.width * to, size.height),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_Block old) =>
      old.from != from || old.to != to || old.color != color;
}
