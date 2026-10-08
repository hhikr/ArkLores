import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// [onTap] with a light tick of the phone's haptics first (when the system
/// allows them); null stays null, so a disabled control stays disabled.
VoidCallback? withHaptic(VoidCallback? onTap) => onTap == null
    ? null
    : () {
        HapticFeedback.selectionClick();
        onTap();
      };

/// Makes a tappable surface answer the finger: it sinks a little (scales
/// to [pressedScale]) as soon as it is touched and settles back on release,
/// so a tap is felt even when it opens another page at once. Mechanical,
/// not springy: a short ease without overshoot, like the games' panels. A
/// drag (a scroll starting on it) lets it go. Pointer-only: the child keeps
/// its own tap handling and ripple.
class PressFeedback extends StatefulWidget {
  const PressFeedback({
    super.key,
    required this.child,
    this.enabled = true,
    this.pressedScale = 0.98,
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
    if (!widget.enabled) return widget.child;
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
      child: AnimatedScale(
        scale: _pressed ? widget.pressedScale : 1,
        duration: Duration(milliseconds: _pressed ? 70 : 160),
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    );
  }
}
