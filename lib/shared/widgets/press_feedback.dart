import 'dart:async';

import 'package:flutter/gestures.dart' show kTouchSlop, kPressTimeout;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/motion.dart';

/// Defers feedback until a stationary touch survives [kPressTimeout].
/// Quick taps still show feedback; scrolling never flashes a pressed row.
mixin PressHold<T extends StatefulWidget> on State<T> {
  bool _pressed = false;
  int? _pointer;
  Offset? _origin;
  Timer? _pending;
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
    _pending?.cancel();
    _show(false);
    _pending = Timer(kPressTimeout, _beginFeedback);
  }

  void _beginFeedback() {
    _show(true);
    _release?.cancel();
    _release = Timer(Motion.of(context, Motion.press), () {
      if (_pointer == null) _show(false);
    });
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
    _pending?.cancel();
    if (now) {
      _release?.cancel();
      _show(false);
    } else if (!_pressed) {
      _beginFeedback();
    } else if (!(_release?.isActive ?? false)) {
      _show(false);
    }
  }

  /// [child] answering the finger while [enabled]. Pointer-only: the tap
  /// itself stays with the child's own gesture detector.
  Widget pressListener({required bool enabled, required Widget child}) {
    if (!enabled && (_pressed || _pointer != null)) {
      _pointer = null;
      _origin = null;
      _release?.cancel();
      _pending?.cancel();
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
    _pending?.cancel();
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
