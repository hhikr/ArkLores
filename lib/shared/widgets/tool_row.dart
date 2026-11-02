import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import '../theme/motion.dart';
import 'press_feedback.dart';

/// One tool in a page's tool panel: an icon and what it does (an icon alone
/// does not say), 48 high; the accent wipes in while it is pressed. [on] marks
/// a tool that is switched on (an accent block on its left).
class ToolRow extends StatefulWidget {
  const ToolRow({
    super.key,
    required this.icon,
    required this.label,
    required this.theme,
    required this.onTap,
    this.on,
  });

  final IconData icon;
  final String label;
  final AppThemeTokens theme;
  final VoidCallback onTap;

  /// Null: not a switch.
  final bool? on;

  @override
  State<ToolRow> createState() => _ToolRowState();
}

class _ToolRowState extends State<ToolRow> with PressHold<ToolRow> {
  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final down = pressed;
    final fg = down ? theme.onAccent : theme.textPrimary;
    return Semantics(
      button: true,
      toggled: widget.on,
      child: pressListener(
        enabled: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            HapticFeedback.selectionClick();
            widget.onTap();
          },
          child: SizedBox(
            height: 48,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: AnimatedFractionallySizedBox(
                    duration:
                        Motion.of(context, down ? Motion.press : Motion.wipe),
                    curve: Motion.mech,
                    widthFactor: down ? 1 : 0,
                    heightFactor: 1,
                    child: ColoredBox(color: theme.accentPrimary),
                  ),
                ),
                if (widget.on ?? false)
                  Positioned(
                    left: 0,
                    top: 10,
                    bottom: 10,
                    width: 4,
                    child: ColoredBox(color: theme.trace),
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Row(
                    children: [
                      Icon(widget.icon, size: 20, color: fg),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          widget.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.ui(
                            15,
                            weight: (widget.on ?? false) ? 700 : 500,
                            color: fg,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
