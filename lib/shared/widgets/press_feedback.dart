import 'dart:async';

import 'package:flutter/gestures.dart' show kTouchSlop;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/motion.dart';

/// The pressed state of a tappable part, shown as soon as the finger lands
/// and kept for at least [Motion.press] after it lifts, so a quick tap is
/// seen too. A tap's own `onTapDown` comes 100 ms late inside a scrollable
/// (it waits to see whether the touch is a drag), and a tap shorter than
/// that brought down and up in one frame: nothing moved. A drag (a scroll
/// starting on it) lets go at once.
///
/// Wrap the part in [pressListener]; read [pressed] in `build`.
mixin PressHold<T extends StatefulWidget> on State<T> {
  bool _pressed = false;
  int? _pointer;
  Offset? _origin;
  final Stopwatch _held = Stopwatch();
  Timer? _release;

  /// Whether the part is drawn pressed.
  bool get pressed => _pressed;

  void _show(bool value) {
    if (mounted && _pressed != value) setState(() => _pressed = value);
  }

  void _down(PointerDownEvent e) {
    if (_pointer != null) return;
    _pointer = e.pointer;
    _origin = e.position;
    _release?.cancel();
    _held
      ..reset()
      ..start();
    _show(true);
  }

  void _move(PointerMoveEvent e) {
    final origin = _origin;
    if (e.pointer != _pointer || origin == null) return;
    if ((e.position - origin).distance > kTouchSlop) _letGo(now: true);
  }

  void _up(PointerEvent e) {
    if (e.pointer != _pointer) return;
    _letGo(now: e is PointerCancelEvent);
  }

  void _letGo({required bool now}) {
    _pointer = null;
    _origin = null;
    _release?.cancel();
    final left = Motion.press - _held.elapsed;
    if (now || left <= Duration.zero) {
      _show(false);
    } else {
      _release = Timer(left, () => _show(false));
    }
  }

  /// [child] answering the finger while [enabled]. Pointer-only: the tap
  /// itself stays with the child's own gesture detector.
  Widget pressListener({required bool enabled, required Widget child}) {
    if (!enabled && (_pressed || _pointer != null)) {
      _pointer = null;
      _origin = null;
      _release?.cancel();
      _pressed = false;
    }
    // The same shape either way: the child keeps its state when [enabled]
    // changes (a button going busy).
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: enabled ? _down : null,
      onPointerMove: enabled ? _move : null,
      onPointerUp: enabled ? _up : null,
      onPointerCancel: enabled ? _up : null,
      child: child,
    );
  }

  @override
  void dispose() {
    _release?.cancel();
    super.dispose();
  }
}

/// [PressHold] for a part without state of its own (a tab, a chip, a row
/// built in a closure): [builder] gets whether it is drawn pressed. Put the
/// part's gesture detector inside.
class PressBuilder extends StatefulWidget {
  const PressBuilder({super.key, required this.builder, this.enabled = true});

  final bool enabled;
  final Widget Function(BuildContext context, bool pressed) builder;

  @override
  State<PressBuilder> createState() => _PressBuilderState();
}

class _PressBuilderState extends State<PressBuilder>
    with PressHold<PressBuilder> {
  @override
  Widget build(BuildContext context) => pressListener(
        enabled: widget.enabled,
        child: widget.builder(context, widget.enabled && pressed),
      );
}

/// [base] as it looks pressed: a film of [ink] over it (over nothing, the
/// film alone). The one pressed look of blocks, tags and rows that have no
/// wipe of their own.
Color pressTint(Color base, Color ink) =>
    Color.alphaBlend(ink.withValues(alpha: 0.10), base);

/// [onTap] with a light tick of the phone's haptics first (when the system
/// allows them); null stays null, so a disabled control stays disabled.
VoidCallback? withHaptic(VoidCallback? onTap) => onTap == null
    ? null
    : () {
        HapticFeedback.selectionClick();
        onTap();
      };

/// Makes a tappable surface answer the finger: it sinks a pixel and
/// shrinks very slightly (never below [pressedScale], at most 1.5 %) as soon
/// as it is touched, and settles back on release, so a tap is felt even when
/// it opens another page at once. Mechanical, not springy. A drag (a scroll
/// starting on it) lets it go. Pointer-only: the child keeps its own tap
/// handling. Still when the system asks for reduced motion.
class PressFeedback extends StatefulWidget {
  const PressFeedback({
    super.key,
    required this.child,
    this.enabled = true,
    this.pressedScale = 0.985,
  });

  final Widget child;
  final bool enabled;
  final double pressedScale;

  @override
  State<PressFeedback> createState() => _PressFeedbackState();
}

class _PressFeedbackState extends State<PressFeedback> {
  static const double _slop = 12;
  bool _pressed = false;
  Offset? _down;

  void _set(bool value) {
    if (mounted && _pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled || Motion.reduced(context)) return widget.child;
    final scale = widget.pressedScale < 0.985 ? 0.985 : widget.pressedScale;
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (e) {
        _down = e.position;
        _set(true);
      },
      onPointerMove: (e) {
        final down = _down;
        if (down != null && (e.position - down).distance > _slop) _set(false);
      },
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: AnimatedContainer(
        duration: _pressed ? Motion.press : Motion.row,
        curve: Motion.mech,
        transform: Matrix4.translationValues(0, _pressed ? 1 : 0, 0),
        child: AnimatedScale(
          scale: _pressed ? scale : 1,
          duration: _pressed ? Motion.press : Motion.row,
          curve: Motion.mech,
          child: widget.child,
        ),
      ),
    );
  }
}
