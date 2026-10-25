import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/theme_provider.dart';
import '../theme/app_theme.dart';
import '../theme/motion.dart';
import 'industrial_ui.dart';

/// The app's page change, a push. Only the materials pages (routes made
/// with `smoothPageRoute(frosted: true)`) come in as the frosted pane below;
/// every other page itself slides in from the right, a 2px trace line on
/// its leading edge, over the page below, which dims under it
/// (Motion.coverIn), and is built at once.
///
/// The frosted pane: the pane (a blur
/// with the paper colour over it, a 2px trace line on its leading edge)
/// slides in from the right over the page below, which dims under it
/// (Motion.coverIn, moving at once and settling, so it answers the tap).
/// Only once the pane covers the screen is the new page built, behind it: a
/// page that takes long to build and lay out its first frame (long text)
/// shows a still, blurred screen, not a stuck slide. After that first frame
/// the pane clears where it is (Motion.reveal): that frame, blurred a few
/// times over from the pane's blur down to nearly sharp, steps from one
/// blur to the next and the last into the page, the colour going with it,
/// so the page comes into focus. Going back slides the page out to the
/// right (240 ms, slow start and hard stop, as every exit): the page below
/// is built. No zoom or bounce. With reduced motion the page just appears.
///
/// The page is drawn into its own layer and only moved: the widgets around
/// it keep one shape for the whole move (a wrapper that came and went with
/// the animation re-parented the whole page), and the ground's contour
/// lines are not drawn again each frame.
Widget smoothPageTransition(
  BuildContext context,
  Animation<double> animation,
  Animation<double> secondaryAnimation,
  Widget child, {
  bool frosted = false,
}) =>
    _ShutterTransition(
      animation: animation,
      secondaryAnimation: secondaryAnimation,
      frosted: frosted,
      child: child,
    );

class _ShutterTransition extends ConsumerStatefulWidget {
  const _ShutterTransition({
    required this.animation,
    required this.secondaryAnimation,
    required this.frosted,
    required this.child,
  });

  final Animation<double> animation;
  final Animation<double> secondaryAnimation;
  final bool frosted;
  final Widget child;

  @override
  ConsumerState<_ShutterTransition> createState() => _ShutterTransitionState();
}

class _ShutterTransitionState extends ConsumerState<_ShutterTransition>
    with TickerProviderStateMixin {
  /// The pane clearing, after the page's first frame: 0 frosted, 1 gone.
  /// Set by [_clearing], not run by time alone.
  late final AnimationController _reveal = AnimationController(vsync: this);

  /// Moves [_reveal] on a frame at a time: by the time since the last frame,
  /// but never more than [_maxStep]. A slow frame of the page (data coming
  /// in, more text laid out) holds the clearing back a little instead of
  /// cutting a piece out of it.
  Ticker? _clearing;
  Duration _lastTick = Duration.zero;
  double _cleared = 0;

  /// Whether the page is in the tree: from the moment the pane covers the
  /// screen (or at once for a route that is not coming in).
  bool _built = false;

  @override
  void initState() {
    super.initState();
    widget.animation.addStatusListener(_onStatus);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_built) return;
    // A route that is there without coming in (the first route), or reduced
    // motion: no pane. The first frame of a push is built offstage with a
    // finished animation (for heroes): that is not one.
    // A page that is not frosted is built at once and only slides.
    final offstage = ModalRoute.of(context)?.offstage ?? false;
    if (!widget.frosted ||
        Motion.reduced(context) ||
        (!offstage && widget.animation.status == AnimationStatus.completed)) {
      _built = true;
      _reveal.value = 1;
    }
  }

  /// Covered: build the page behind the pane; the pane clears after the
  /// page's first frame.
  void _onStatus(AnimationStatus status) {
    if (_built || status != AnimationStatus.completed) return;
    setState(() => _built = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _freeze();
      _clearing = createTicker(_clear)..start();
    });
  }

  void _clear(Duration elapsed) {
    final step = elapsed - _lastTick;
    _lastTick = elapsed;
    _cleared = math.min(
      1,
      _cleared +
          math.min(step.inMicroseconds, _maxStep.inMicroseconds) /
              Motion.reveal.inMicroseconds,
    );
    _reveal.value = Motion.ease.transform(_cleared);
    if (_cleared < 1) return;
    _clearing!.stop();
    // Off the screen from the frame the pane went: let them go after it.
    WidgetsBinding.instance.addPostFrameCallback((_) => _thaw());
  }

  /// The page's first frame at [_levels] blurs, worked out once, that the
  /// pane steps through as it clears: one blur after another fading into
  /// the next, the last into the page, so the page comes into focus. A blur
  /// worked out again every frame (the whole screen, 9–15 ms a frame on a
  /// phone) missed one frame in two at 120 Hz and the clearing went in
  /// jerks; one blurred picture fading over the sharp page showed the page
  /// sharp half way and did not read as focusing. Empty when they could
  /// not be made: the pane then blurs live.
  List<ui.Image> _frozen = const [];

  void _freeze() {
    final boundary = _pageKey.currentContext?.findRenderObject();
    if (boundary is! RenderRepaintBoundary || boundary.debugNeedsPaint) return;
    try {
      // At logical resolution: cheap to make and to blur, and blurred there
      // is no detail lost that would show.
      final shot = boundary.toImageSync();
      final levels = <ui.Image>[];
      for (final sigma in _levels) {
        final recorder = ui.PictureRecorder();
        Canvas(recorder).drawImage(
          shot,
          Offset.zero,
          Paint()
            ..imageFilter = ui.ImageFilter.blur(
              sigmaX: sigma,
              sigmaY: sigma,
              tileMode: TileMode.clamp,
            ),
        );
        final picture = recorder.endRecording();
        levels.add(picture.toImageSync(shot.width, shot.height));
        picture.dispose();
      }
      shot.dispose();
      setState(() => _frozen = levels);
    } catch (error) {
      debugPrint('[PageRoute] No blurred snapshots: $error');
    }
  }

  void _thaw() {
    if (_frozen.isEmpty) return;
    for (final image in _frozen) {
      image.dispose();
    }
    if (mounted) setState(() => _frozen = const []);
  }

  final _pageKey = GlobalKey();

  @override
  void didUpdateWidget(covariant _ShutterTransition old) {
    super.didUpdateWidget(old);
    if (old.animation != widget.animation) {
      old.animation.removeStatusListener(_onStatus);
      widget.animation.addStatusListener(_onStatus);
      _onStatus(widget.animation.status);
    }
  }

  @override
  void dispose() {
    widget.animation.removeStatusListener(_onStatus);
    _clearing?.dispose();
    _reveal.dispose();
    for (final image in _frozen) {
      image.dispose();
    }
    super.dispose();
  }

  /// The pane while it clears with [_frozen]: the two blurs [reveal] is
  /// between, the sharper fading in over the other (past the last one, the
  /// last fading out over the page), and the paper colour going.
  Widget _steps(AppThemeTokens tokens, double reveal) {
    final at = reveal * _frozen.length;
    final k = math.min(at.floor(), _frozen.length - 1);
    final fade = at - k;
    final last = k == _frozen.length - 1;
    Widget image(ui.Image image, double opacity) => RawImage(
          image: image,
          fit: BoxFit.fill,
          filterQuality: FilterQuality.medium,
          opacity: AlwaysStoppedAnimation(opacity),
        );
    return Stack(
      fit: StackFit.passthrough,
      children: [
        image(_frozen[k], last ? 1 - fade : 1),
        if (!last) image(_frozen[k + 1], fade),
        ColoredBox(
          color: tokens.bgPrimary.withValues(alpha: _frostTint * (1 - reveal)),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = ref.watch(themeProvider);
    final page = RepaintBoundary(
      key: _pageKey,
      child: IndustrialBackdrop(theme: tokens, child: widget.child),
    );
    if (Motion.reduced(context)) return page;
    final t = CurvedAnimation(
      parent: widget.animation,
      curve: Motion.snap,
      reverseCurve: Motion.mech.flipped,
    );
    final below = CurvedAnimation(
      parent: widget.secondaryAnimation,
      curve: Motion.snap,
      reverseCurve: Motion.mech.flipped,
    );
    return AnimatedBuilder(
      animation: Listenable.merge([t, below, _reveal]),
      builder: (context, _) {
        final covered = below.value;
        final shift = -_belowShift * covered;
        final leaving = widget.animation.status == AnimationStatus.reverse;
        // Not frosted: the page itself slides, in and out.
        final sliding = leaving || (!widget.frosted && t.value < 1);
        final reveal = _reveal.value;
        return FractionalTranslation(
          // Going back: the whole page slides out to the right.
          translation: Offset((sliding ? 1 - t.value : 0) + shift, 0),
          child: Stack(
            fit: StackFit.passthrough,
            children: [
              // Before the cover is shut there is no page: an empty box of
              // the same size keeps the Stack's shape.
              if (_built) page else const SizedBox.expand(),
              if (!leaving && reveal < 1)
                Positioned.fill(
                  child: IgnorePointer(
                    child: FractionalTranslation(
                      key: shutterCoverKey,
                      // In from the right; then it stays and clears.
                      translation: Offset(_built ? 0 : 1 - t.value, 0),
                      child: ClipRect(
                        child: _frozen.isNotEmpty
                            ? _steps(tokens, reveal)
                            : BackdropFilter(
                                filter: ui.ImageFilter.blur(
                                  sigmaX: _frostBlur * (1 - reveal),
                                  sigmaY: _frostBlur * (1 - reveal),
                                ),
                                child: Stack(
                                  fit: StackFit.passthrough,
                                  children: [
                                    ColoredBox(
                                      color: tokens.bgPrimary.withValues(
                                        alpha: _frostTint * (1 - reveal),
                                      ),
                                    ),
                                    if (!_built)
                                      Positioned(
                                        left: 0,
                                        top: 0,
                                        bottom: 0,
                                        width: 2,
                                        child: ColoredBox(color: tokens.trace),
                                      ),
                                  ],
                                ),
                              ),
                      ),
                    ),
                  ),
                ),
              if (sliding)
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: 2,
                  child: ColoredBox(color: tokens.trace),
                ),
              if (covered > 0)
                Positioned.fill(
                  child: IgnorePointer(
                    child: ColoredBox(
                      color:
                          Colors.black.withValues(alpha: _belowDim * covered),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// The frosted pane of a page coming in, while it is on screen (tests).
@visibleForTesting
const shutterCoverKey = ValueKey('shutterCover');

/// The pane's blur at its thickest (logical pixels, sigma).
const _frostBlur = 8.0;

/// The blurs the pane clears through (logical pixels, sigma), from the
/// pane's own to nearly sharp.
const _levels = [_frostBlur, 5.0, 3.0, 1.5];

/// The most the clearing moves on in one frame (see [_ShutterTransition]).
const _maxStep = Duration(milliseconds: 25);

/// How much of the paper colour the pane lays over what it blurs.
const _frostTint = 0.55;

/// How far the page below moves left, as a share of its width: not at all.
/// Through the frosted pane the strip it left on the right showed, in
/// another colour.
const _belowShift = 0.0;

/// How dark the page below gets when it is fully covered.
const _belowDim = 0.35;

/// [smoothPageTransition] for every route (`MaterialPageRoute`, named
/// routes, the home route), set in the theme's `pageTransitionsTheme`.
class SmoothPageTransitionsBuilder extends PageTransitionsBuilder {
  const SmoothPageTransitionsBuilder();

  @override
  Duration get transitionDuration => Motion.coverIn;

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
      smoothPageTransition(
        context,
        animation,
        secondaryAnimation,
        child,
        frosted: route is _FrostedPageRoute,
      );
}

/// A pushed page. A [MaterialPageRoute], so the theme's
/// [SmoothPageTransitionsBuilder] moves it in and the page below moves with
/// it (Flutter animates the covered page only for material routes).
/// [frosted] (the materials pages only) brings it in behind the frosted pane.
PageRoute<T> smoothPageRoute<T>({
  required WidgetBuilder builder,
  RouteSettings? settings,
  bool frosted = false,
}) =>
    frosted
        ? _FrostedPageRoute<T>(settings: settings, builder: builder)
        : MaterialPageRoute<T>(settings: settings, builder: builder);

class _FrostedPageRoute<T> extends MaterialPageRoute<T> {
  _FrostedPageRoute({required super.builder, super.settings});
}
