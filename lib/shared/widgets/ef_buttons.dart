part of 'ef_widgets.dart';

enum ButtonKind {
  /// A chip-grey button; the accent wipes in while it is pressed.
  normal,

  /// The one main action of a group: the accent at rest.
  go,

  /// Deleting: red text, red wipes in while pressed.
  danger,

  /// A text-only button for small actions beside content.
  quiet,
}

/// A button: a block with its bottom-right corner cut. Pressing wipes a fill
/// in from the left (100 ms) and lets it go (280 ms); no ripple. While
/// [busy] it is hatched and does not answer.
class AppButton extends ConsumerStatefulWidget {
  const AppButton(
    this.label, {
    super.key,
    this.onPressed,
    this.kind = ButtonKind.normal,
    this.icon,
    this.small = false,
    this.expand = false,
    this.busy = false,
    this.tooltip,
  });

  final String label;
  final VoidCallback? onPressed;
  final ButtonKind kind;
  final IconData? icon;
  final bool small;
  final bool expand;
  final bool busy;
  final String? tooltip;

  @override
  ConsumerState<AppButton> createState() => _AppButtonState();
}

class _AppButtonState extends ConsumerState<AppButton>
    with SingleTickerProviderStateMixin, PressHold<AppButton> {
  late final AnimationController _run = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
  );

  @override
  void didUpdateWidget(covariant AppButton old) {
    super.didUpdateWidget(old);
    _syncBusy();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncBusy());
  }

  void _syncBusy() {
    if (!mounted) return;
    if (widget.busy && !Motion.reduced(context)) {
      if (!_run.isAnimating) _run.repeat();
    } else if (_run.isAnimating) {
      _run.stop();
    }
  }

  @override
  void dispose() {
    _run.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider);
    final enabled = widget.onPressed != null && !widget.busy;
    final kind = widget.kind;
    final down = pressed;
    final rest = switch (kind) {
      ButtonKind.go => theme.accentPrimary,
      ButtonKind.quiet => Colors.transparent,
      _ => theme.surfaceElevated,
    };
    final wipe = switch (kind) {
      ButtonKind.danger => theme.danger,
      ButtonKind.go => theme.textPrimary.withValues(alpha: 0.14),
      _ => theme.accentPrimary,
    };
    final Color fg;
    if (!enabled && !widget.busy) {
      fg = theme.textMuted;
    } else if (down) {
      fg = switch (kind) {
        ButtonKind.danger => theme.isDark ? theme.bgPrimary : Colors.white,
        _ => theme.onAccent,
      };
    } else {
      fg = switch (kind) {
        ButtonKind.go => theme.onAccent,
        ButtonKind.danger => theme.danger,
        _ => theme.textPrimary,
      };
    }
    // Drawn smaller than the finger's 48: a block the size of the touch
    // area outweighs what is around it.
    final h = widget.small ? 34.0 : 42.0;
    final label = Row(
      mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (widget.icon != null) ...[
          Icon(widget.icon, size: widget.small ? 18 : 20, color: fg),
          const SizedBox(width: 8),
        ],
        Flexible(
          child: Text(
            widget.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.ui(widget.small ? 13.5 : 15, weight: 700, color: fg),
          ),
        ),
      ],
    );
    Widget button = Semantics(
      button: true,
      enabled: enabled,
      label: widget.busy ? widget.label : null,
      child: pressListener(
        enabled: enabled,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: enabled
              ? () {
                  if (kind == ButtonKind.go || kind == ButtonKind.danger) {
                    HapticFeedback.lightImpact();
                  } else {
                    HapticFeedback.selectionClick();
                  }
                  widget.onPressed!();
                }
              : null,
          child: ConstrainedBox(
            // The finger gets 48 even where the block is drawn 34 high.
            constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
            child: Center(
              widthFactor: widget.expand ? null : 1,
              heightFactor: 1,
              child: ClipPath(
                clipper: const ShapeBorderClipper(shape: CutBorder.br(8)),
                child: SizedBox(
                  height: h,
                  width: widget.expand ? double.infinity : null,
                  child: Stack(
                    fit: StackFit.passthrough,
                    children: [
                      Positioned.fill(
                        child: ColoredBox(
                          color: enabled || widget.busy
                              ? rest
                              : (kind == ButtonKind.quiet
                                  ? Colors.transparent
                                  : theme.surfaceElevated
                                      .withValues(alpha: 0.6)),
                        ),
                      ),
                      if (widget.busy)
                        Positioned.fill(
                          child: AnimatedBuilder(
                            animation: _run,
                            builder: (context, _) => CustomPaint(
                              painter: HatchPainter(
                                (kind == ButtonKind.go
                                        ? theme.onAccent
                                        : theme.textPrimary)
                                    .withValues(alpha: 0.22),
                                offset: _run.value * 9.2,
                              ),
                            ),
                          ),
                        ),
                      Positioned.fill(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: AnimatedFractionallySizedBox(
                            duration: Motion.of(
                              context,
                              down ? Motion.press : Motion.wipe,
                            ),
                            curve: Motion.mech,
                            widthFactor: down ? 1 : 0,
                            heightFactor: 1,
                            child: ColoredBox(color: wipe),
                          ),
                        ),
                      ),
                      Padding(
                        padding: EdgeInsets.fromLTRB(
                          widget.small ? 10 : 14,
                          0,
                          widget.small ? 14 : 18,
                          0,
                        ),
                        child: Center(
                          widthFactor: widget.expand ? null : 1,
                          child: label,
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
    if (widget.tooltip != null) {
      button = Tooltip(message: widget.tooltip!, child: button);
    }
    return button;
  }
}

/// A square icon button: 48×48 to the finger, a chip-grey block with a cut
/// corner when [filled], the accent wiping in while pressed. Always has a
/// [tooltip], which is also what a screen reader says.
class SquareIconButton extends ConsumerStatefulWidget {
  const SquareIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.filled = false,
    this.selected = false,
    this.size = 22,
    this.color,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool filled;

  /// On: the accent fill (a toggle that is on).
  final bool selected;
  final double size;
  final Color? color;

  @override
  ConsumerState<SquareIconButton> createState() => _SquareIconButtonState();
}

class _SquareIconButtonState extends ConsumerState<SquareIconButton>
    with PressHold<SquareIconButton> {
  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider);
    final enabled = widget.onPressed != null;
    final down = pressed;
    final on = down || widget.selected;
    final fg = !enabled
        ? theme.textMuted
        : on
            ? theme.onAccent
            : (widget.color ?? theme.textPrimary);
    return Tooltip(
      message: widget.tooltip,
      child: Semantics(
        button: true,
        enabled: enabled,
        toggled: widget.selected ? true : null,
        label: widget.tooltip,
        excludeSemantics: true,
        child: pressListener(
          enabled: enabled,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: enabled
                ? () {
                    HapticFeedback.selectionClick();
                    widget.onPressed!();
                  }
                : null,
            child: SizedBox(
              width: 48,
              height: 48,
              child: Center(
                child: AnimatedContainer(
                  duration:
                      Motion.of(context, down ? Motion.press : Motion.wipe),
                  curve: Motion.mech,
                  width: 38,
                  height: 38,
                  decoration: ShapeDecoration(
                    color: on
                        ? theme.accentPrimary
                        : widget.filled
                            ? theme.surfaceElevated
                            : Colors.transparent,
                    shape: const CutBorder.br(6),
                  ),
                  child: Icon(widget.icon, size: widget.size, color: fg),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
