part of 'ef_widgets.dart';

/// Progress as a bar of [cells] cells lit in hard steps, with a readout
/// (`063%`). Without a [value] a short run of lit cells walks across until
/// the work is done (the only motion that loops).
class SegmentProgress extends ConsumerStatefulWidget {
  const SegmentProgress({
    super.key,
    this.value,
    this.label,
    this.cells = 24,
    this.height = 8,
    this.showReadout = true,
  });

  final double? value;
  final String? label;
  final int cells;
  final double height;
  final bool showReadout;

  @override
  ConsumerState<SegmentProgress> createState() => _SegmentProgressState();
}

class _SegmentProgressState extends ConsumerState<SegmentProgress>
    with SingleTickerProviderStateMixin {
  late final AnimationController _walk = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(covariant SegmentProgress old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    final walk = widget.value == null && !Motion.reduced(context);
    if (walk && !_walk.isAnimating) {
      _walk.repeat();
    } else if (!walk && _walk.isAnimating) {
      _walk.stop();
    }
  }

  @override
  void dispose() {
    _walk.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider);
    final n = widget.cells;
    final value = widget.value?.clamp(0.0, 1.0);
    final percent = value == null ? null : (value * 100).round();
    return Semantics(
      label: widget.label,
      value: percent == null ? null : '$percent%',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.label != null || (widget.showReadout && percent != null))
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  if (widget.label != null)
                    Expanded(
                      child: Text(
                        widget.label!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.ui(13, color: theme.textPrimary),
                      ),
                    )
                  else
                    const Spacer(),
                  if (widget.showReadout && percent != null)
                    Text(
                      '${percent.toString().padLeft(3, '0')}%',
                      style: theme.field(color: theme.textPrimary),
                    ),
                ],
              ),
            ),
          AnimatedBuilder(
            animation: _walk,
            builder: (context, _) {
              final lit = value == null ? null : (value * n).floor();
              final head = (_walk.value * (n + 4)).floor() - 4;
              return Row(
                children: [
                  for (var i = 0; i < n; i++)
                    Expanded(
                      child: Container(
                        height: widget.height,
                        margin: EdgeInsets.only(right: i == n - 1 ? 0 : 2),
                        color: (lit != null
                                ? i < lit
                                : (Motion.reduced(context)
                                    ? i < n ~/ 3
                                    : i >= head && i < head + 4))
                            ? theme.accentPrimary
                            : theme.surfaceElevated,
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

/// A square switch: on = accent track with an ink block; off = chip track
/// with a panel block. The block moves in 280 ms, mechanically.
class SquareSwitch extends ConsumerWidget {
  const SquareSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.semanticLabel,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    final enabled = onChanged != null;
    return Semantics(
      toggled: value,
      enabled: enabled,
      label: semanticLabel,
      child: PressBuilder(
        enabled: enabled,
        builder: (context, down) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: enabled
              ? () {
                  HapticFeedback.selectionClick();
                  onChanged!(!value);
                }
              : null,
          child: SizedBox(
            width: 56,
            height: 48,
            child: Center(
              child: Opacity(
                opacity: enabled ? 1 : 0.45,
                child: AnimatedContainer(
                  duration: Motion.of(context, Motion.wipe),
                  curve: Motion.mech,
                  width: 48,
                  height: 26,
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: value
                        ? theme.accentPrimary
                        : down
                            ? pressTint(
                                theme.surfaceElevated,
                                theme.textPrimary,
                              )
                            : theme.surfaceElevated,
                    border: value ? null : Border.all(color: theme.cardBorder),
                  ),
                  alignment:
                      value ? Alignment.centerRight : Alignment.centerLeft,
                  // Pressed, the block grows toward where it will go.
                  child: AnimatedContainer(
                    duration: Motion.of(context, Motion.press),
                    curve: Motion.mech,
                    width: down ? 22 : 18,
                    height: 18,
                    color: value ? theme.onAccent : theme.cardSurface,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A segmented choice: an ink frame, the current segment filled with ink
/// (the accent is kept for navigation and the main action). On a change the
/// ink block slides to the new segment, and each label turns light as the
/// block passes under it.
class SegmentedChoice<T> extends ConsumerWidget {
  const SegmentedChoice({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    this.labelStyle,
  });

  final List<(T, String)> options;
  final T value;
  final ValueChanged<T> onChanged;

  /// Laid over a choice's label (a font set in itself).
  final TextStyle Function(T value)? labelStyle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    final n = options.length;
    final selected = options.indexWhere((o) => o.$1 == value);
    return Container(
      decoration: BoxDecoration(border: Border.all(color: theme.textPrimary)),
      child: TweenAnimationBuilder<double>(
        // Where the ink block stands, in segments (it slides between them).
        tween: Tween(end: selected < 0 ? -1 : selected.toDouble()),
        duration: Motion.of(context, Motion.row),
        curve: Motion.snap,
        builder: (context, at, _) => LayoutBuilder(
          builder: (context, box) {
            final width = box.maxWidth / n;
            return Stack(
              children: [
                if (selected >= 0)
                  Positioned(
                    left: at * width,
                    top: 0,
                    bottom: 0,
                    width: width,
                    child: ColoredBox(color: theme.textPrimary),
                  ),
                Row(
                  children: [
                    for (var i = 0; i < n; i++)
                      Expanded(
                        child: _segment(
                          theme,
                          options[i],
                          // How much of the block is under this segment.
                          (1 - (at - i).abs()).clamp(0.0, 1.0),
                        ),
                      ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _segment(AppThemeTokens theme, (T, String) option, double covered) {
    final (v, label) = option;
    final current = v == value;
    return Semantics(
      button: true,
      inMutuallyExclusiveGroup: true,
      checked: current,
      child: PressBuilder(
        enabled: !current,
        builder: (context, down) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: current
              ? null
              : () {
                  HapticFeedback.selectionClick();
                  onChanged(v);
                },
          child: AnimatedContainer(
            duration: Motion.of(context, down ? Motion.press : Motion.wipe),
            curve: Motion.mech,
            constraints: const BoxConstraints(minHeight: 48),
            // Narrow: seven short values fit across a phone.
            padding: const EdgeInsets.symmetric(horizontal: 2),
            alignment: Alignment.center,
            color: down && !current
                ? pressTint(Colors.transparent, theme.textPrimary)
                : Colors.transparent,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: theme
                  .ui(
                    14,
                    weight: covered > 0.5 ? 700 : 500,
                    color: Color.lerp(
                      theme.textPrimary,
                      theme.bgPrimary,
                      covered,
                    ),
                  )
                  .merge(labelStyle?.call(v)),
            ),
          ),
        ),
      ),
    );
  }
}

/// A cut track filled with the accent up to a large ink thumb that stands
/// past it above and below; taps and drags share one scale.
class AppSlider extends ConsumerStatefulWidget {
  const AppSlider({
    super.key,
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max = 1,
    this.divisions,
    this.onChangeEnd,
    this.semanticLabel,
    this.semanticValue,
  })  : assert(max > min),
        assert(divisions == null || divisions > 0);
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final ValueChanged<double>? onChanged;
  final ValueChanged<double>? onChangeEnd;
  final String? semanticLabel;
  final String? semanticValue;
  @override
  ConsumerState<AppSlider> createState() => _AppSliderState();
}

class _AppSliderState extends ConsumerState<AppSlider> {
  late double _value = widget.value;
  bool _dragging = false;
  bool _focused = false;
  static const _thumb = 40.0;

  @override
  void didUpdateWidget(AppSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Under the finger the thumb is where the finger is, not where the
    // owner rounded it to.
    if (!_dragging && widget.value != oldWidget.value) _value = widget.value;
  }

  double _snap(double value) {
    final share =
        ((value - widget.min) / (widget.max - widget.min)).clamp(0.0, 1.0);
    final steps = widget.divisions;
    return widget.min +
        (steps == null ? share : (share * steps).round() / steps) *
            (widget.max - widget.min);
  }

  void _change(double value) {
    final next = _snap(value);
    if (next == _value) return;
    if (widget.divisions != null) HapticFeedback.selectionClick();
    setState(() => _value = next);
    widget.onChanged?.call(next);
  }

  void _adjust(int direction) {
    _change(
      _value +
          direction * (widget.max - widget.min) / (widget.divisions ?? 100),
    );
    widget.onChangeEnd?.call(_value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider);
    final enabled = widget.onChanged != null;
    return Semantics(
      slider: true,
      enabled: enabled,
      label: widget.semanticLabel,
      value: widget.semanticValue ?? '${_value.round()}',
      increasedValue:
          '${_snap(_value + (widget.max - widget.min) / (widget.divisions ?? 100))}',
      decreasedValue:
          '${_snap(_value - (widget.max - widget.min) / (widget.divisions ?? 100))}',
      onIncrease: enabled && _value < widget.max ? () => _adjust(1) : null,
      onDecrease: enabled && _value > widget.min ? () => _adjust(-1) : null,
      child: Focus(
        canRequestFocus: enabled,
        onFocusChange: (value) => setState(() => _focused = value),
        onKeyEvent: (_, event) {
          if (!enabled || event is! KeyDownEvent) return KeyEventResult.ignored;
          final key = event.logicalKey;
          if (key == LogicalKeyboardKey.arrowRight ||
              key == LogicalKeyboardKey.arrowUp) {
            _adjust(1);
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.arrowLeft ||
              key == LogicalKeyboardKey.arrowDown) {
            _adjust(-1);
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: LayoutBuilder(
          builder: (context, box) {
            final travel = math.max(1.0, box.maxWidth - _thumb);
            final rtl = Directionality.of(context) == TextDirection.rtl;
            double at(Offset position) {
              final x = rtl ? box.maxWidth - position.dx : position.dx;
              return widget.min +
                  ((x - _thumb / 2) / travel).clamp(0.0, 1.0) *
                      (widget.max - widget.min);
            }

            void finish() {
              if (!_dragging) return;
              setState(() => _dragging = false);
              widget.onChangeEnd?.call(_value);
            }

            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: enabled
                  ? (details) {
                      _change(at(details.localPosition));
                      widget.onChangeEnd?.call(_value);
                    }
                  : null,
              onHorizontalDragStart: enabled
                  ? (details) {
                      setState(() => _dragging = true);
                      _change(at(details.localPosition));
                    }
                  : null,
              onHorizontalDragUpdate: enabled
                  ? (details) => _change(at(details.localPosition))
                  : null,
              onHorizontalDragEnd: enabled ? (_) => finish() : null,
              onHorizontalDragCancel: enabled ? finish : null,
              child: SizedBox(
                height: 48,
                child: TweenAnimationBuilder<double>(
                  tween: Tween(
                    end: ((_value - widget.min) / (widget.max - widget.min))
                        .clamp(0.0, 1.0),
                  ),
                  duration: _dragging
                      ? Duration.zero
                      : Motion.of(context, Motion.row),
                  curve: Motion.snap,
                  builder: (context, share, _) {
                    final x = share * travel;
                    return Stack(
                      clipBehavior: Clip.none,
                      children: [
                        // The track: filled up to the needle.
                        Positioned.fill(
                          top: 10,
                          bottom: 10,
                          child: DecoratedBox(
                            decoration: ShapeDecoration(
                              color: theme.divider,
                              shape: CutBorder.br(
                                7,
                                side: BorderSide(
                                  color:
                                      _focused ? theme.trace : theme.cardBorder,
                                  width: _focused ? 2 : 1,
                                ),
                              ),
                            ),
                            child: ClipPath(
                              clipper: const ShapeBorderClipper(
                                shape: CutBorder.br(7),
                              ),
                              child: Stack(
                                children: [
                                  PositionedDirectional(
                                    start: 0,
                                    top: 0,
                                    bottom: 0,
                                    width: x + _thumb / 2,
                                    child: ColoredBox(
                                      color: enabled
                                          ? theme.accentPrimary
                                          : theme.surfaceElevated,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        // The thumb: an ink block standing past the track
                        // above and below (it reads on the fill and on the
                        // empty part alike), its corner cut (it is moved),
                        // two grip lines that take the accent while held.
                        PositionedDirectional(
                          start: x,
                          top: 4,
                          width: _thumb,
                          height: _thumb,
                          child: DecoratedBox(
                            key: const ValueKey('app-slider-thumb'),
                            decoration: ShapeDecoration(
                              color:
                                  enabled ? theme.textPrimary : theme.textMuted,
                              shape: const CutBorder.br(8),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                for (final gap in const [0.0, 5.0])
                                  Padding(
                                    padding: EdgeInsets.only(left: gap),
                                    child: AnimatedContainer(
                                      duration: Motion.of(
                                        context,
                                        _dragging ? Motion.press : Motion.wipe,
                                      ),
                                      curve: Motion.mech,
                                      width: 2,
                                      height: 14,
                                      color: _dragging
                                          ? theme.accentPrimary
                                          : theme.bgPrimary,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
