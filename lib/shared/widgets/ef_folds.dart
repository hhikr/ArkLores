part of 'ef_widgets.dart';

/// A pressable row: while the finger is down a trace bar drops from the top
/// of its left edge to the bottom and the content shifts 6 px right (200 ms,
/// then back). No ripple, no scale; a drag (a scroll) lets go.
class PressRow extends ConsumerStatefulWidget {
  const PressRow({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.shift = true,
    this.marked = false,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// Whether the bar drops and the content moves right while pressed. Off
  /// for heads that should stay put (a status line, a fold's head): the
  /// press is then only a light film.
  final bool shift;

  /// The bar stays: the row is the current one, or what it opens is open.
  final bool marked;

  @override
  ConsumerState<PressRow> createState() => _PressRowState();
}

class _PressRowState extends ConsumerState<PressRow> with PressHold<PressRow> {
  /// Tapped: the bar runs its full length at once and stays while what the
  /// row opens covers it. Let go with the press (100 ms after a quick tap),
  /// it drew back half-drawn under the page coming in.
  bool _held = false;
  Timer? _hold;

  void _tapped() {
    HapticFeedback.selectionClick();
    if (widget.shift) {
      setState(() => _held = true);
      _hold?.cancel();
      _hold = Timer(Motion.coverIn + Motion.row, () {
        if (mounted) setState(() => _held = false);
      });
    }
    widget.onTap!();
  }

  @override
  void dispose() {
    _hold?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.onTap == null && widget.onLongPress == null) return widget.child;
    final theme = ref.watch(themeProvider);
    final d = Motion.of(context, Motion.row);
    final down = pressed || _held;
    final bar = (down && widget.shift) || widget.marked;
    return pressListener(
      enabled: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap == null ? null : _tapped,
        onLongPress: widget.onLongPress,
        child: Stack(
          children: [
            AnimatedContainer(
              duration: d,
              curve: Motion.snap,
              transform: Matrix4.translationValues(
                down && widget.shift ? 6 : 0,
                0,
                0,
              ),
              color: down
                  ? theme.textPrimary.withValues(alpha: 0.04)
                  : Colors.transparent,
              child: widget.child,
            ),
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: traceRailWidth,
              child: TraceRail(
                on: bar,
                // Fast once tapped: full before the new page has moved far.
                duration: _held ? Motion.of(context, Motion.press) : d,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// How wide the trace rail on the left of a pressed or open row is.
const double traceRailWidth = 3;

/// The trace rail of a row: it runs down from the top to the full height
/// of what it is beside while [on] (snap) and draws back up when off (mech).
/// It never grows thicker; its length is what moves. Give it a bounded
/// height (a [Positioned] with top and bottom).
class TraceRail extends ConsumerWidget {
  const TraceRail({super.key, required this.on, this.duration, this.color});

  final bool on;
  final Duration? duration;
  final Color? color;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    return AnimatedFractionallySizedBox(
      duration: duration ?? Motion.of(context, Motion.wipe),
      curve: on ? Motion.snap : Motion.mech,
      alignment: Alignment.topCenter,
      heightFactor: on ? 1 : 0,
      widthFactor: 1,
      child: ColoredBox(color: color ?? theme.trace),
    );
  }
}

/// A head that unfolds a body under it. A trace rail on the left edge runs
/// the length of what is open: it drops along the head while the finger is
/// down, extends with the body as the body opens, stays while it is open and
/// draws back with it as it folds. The head itself does not move; pressing
/// it lays a light film over it. Leave at least 10 px on the left of the
/// head and the body for the rail.
class FoldBlock extends ConsumerStatefulWidget {
  const FoldBlock({
    super.key,
    required this.head,
    required this.open,
    required this.onTap,
    this.body,
    this.headKey,
    this.railTop = 0,
  });

  final Widget head;

  /// Where the rail starts below the top of the head: a tall head with a
  /// short label in it starts the rail just above the label.
  final double railTop;

  /// On the head (what is tapped), not the whole block.
  final Key? headKey;

  /// Built only while [open].
  final Widget Function()? body;
  final bool open;
  final VoidCallback? onTap;

  @override
  ConsumerState<FoldBlock> createState() => _FoldBlockState();
}

class _FoldBlockState extends ConsumerState<FoldBlock>
    with PressHold<FoldBlock> {
  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider);
    final open = widget.open;
    final down = pressed;
    final head = pressListener(
      enabled: widget.onTap != null,
      child: GestureDetector(
        key: widget.headKey,
        behavior: HitTestBehavior.opaque,
        onTap: withHaptic(widget.onTap),
        child: AnimatedContainer(
          duration: Motion.of(context, Motion.press),
          curve: Motion.mech,
          color: down
              ? theme.textPrimary.withValues(alpha: 0.04)
              : Colors.transparent,
          child: widget.head,
        ),
      ),
    );
    // Opening answers the tap at once (snap) and folding stops hard (mech);
    // the body is its own layer, so the frames only clip it.
    final body = widget.body == null
        ? null
        : AnimatedSize(
            duration: Motion.of(context, Motion.wipe),
            curve: open ? Motion.snap : Motion.mech,
            alignment: Alignment.topLeft,
            child: open
                ? RepaintBoundary(child: widget.body!())
                : const SizedBox(width: double.infinity),
          );
    return Stack(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [head, if (body != null) body],
        ),
        Positioned(
          left: 0,
          top: widget.railTop,
          bottom: 0,
          width: traceRailWidth,
          child: TraceRail(on: open || down),
        ),
      ],
    );
  }
}

/// A row that folds a list under it, keeping its own state (in place of
/// Material's ExpansionTile): a [FoldBlock] whose head is the title, a
/// short line under it and a chevron.
class FoldTile extends ConsumerStatefulWidget {
  const FoldTile({
    super.key,
    required this.title,
    this.subtitle,
    required this.children,
    this.initiallyOpen = false,
    this.padding = const EdgeInsets.symmetric(horizontal: 12),
    this.childrenPadding = EdgeInsets.zero,
  });

  final Widget title;
  final Widget? subtitle;
  final List<Widget> children;
  final bool initiallyOpen;

  /// Left and right of the head (at least 10 on the left, for the rail).
  final EdgeInsets padding;
  final EdgeInsets childrenPadding;

  @override
  ConsumerState<FoldTile> createState() => _FoldTileState();
}

class _FoldTileState extends ConsumerState<FoldTile> {
  late bool _open = widget.initiallyOpen;

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider);
    return Semantics(
      button: true,
      expanded: _open,
      child: FoldBlock(
        open: _open,
        onTap: () => setState(() => _open = !_open),
        head: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: widget.padding.add(
              const EdgeInsets.symmetric(vertical: 8),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      widget.title,
                      if (widget.subtitle != null) widget.subtitle!,
                    ],
                  ),
                ),
                AnimatedRotation(
                  turns: _open ? 0 : -0.25,
                  duration: Motion.of(context, Motion.wipe),
                  curve: Motion.mech,
                  child: Icon(
                    Icons.expand_more_sharp,
                    size: 22,
                    color: _open ? theme.textPrimary : theme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
        body: () => Padding(
          padding: widget.childrenPadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: widget.children,
          ),
        ),
      ),
    );
  }
}

/// Opens a dialog: it switches on from the top down in 280 ms and shuts
/// from the bottom up in 180 ms. Put an [AppDialog] in it.
Future<T?> showAppDialog<T>(BuildContext context, WidgetBuilder builder) {
  final still = Motion.reduced(context);
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.black.withValues(alpha: 0.5),
    transitionDuration: still ? Duration.zero : Motion.dialogIn,
    pageBuilder: (context, _, __) => SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Material(
            type: MaterialType.transparency,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Builder(builder: builder),
            ),
          ),
        ),
      ),
    ),
    transitionBuilder: (context, animation, _, child) => AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, child) {
        final t = Motion.mech.transform(animation.value);
        return ClipRect(
          child: Align(
            alignment: Alignment.topCenter,
            heightFactor: t,
            child: child,
          ),
        );
      },
    ),
  );
}
