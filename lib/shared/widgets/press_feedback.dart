import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/motion.dart';

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
