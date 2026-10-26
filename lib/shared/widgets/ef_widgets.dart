import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/theme_provider.dart';
import '../theme/app_theme.dart';
import '../theme/cut_border.dart';
import '../theme/motion.dart';
import 'press_feedback.dart';

// The app's parts (0.17). Each one says in its comment what it MEANS:
// the accent marks "here", "act on this" or "look at this" and is a fill;
// a cut corner means "you can press this"; hairlines divide; numbers,
// dates and counts are real fields in the wide face; red is for deleting.

/// Magenta / accent / mint, 3px: where a screen begins. Only at the top of
/// the main screens and under the title of a story.
class TriStrip extends ConsumerWidget {
  const TriStrip({super.key, this.height = 3});

  final double height;

  static const magenta = Color(0xFFFF00F0);
  static const mint = Color(0xFF00FFA2);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    return ExcludeSemantics(
      child: SizedBox(
        height: height,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Expanded(child: ColoredBox(color: magenta)),
            Expanded(child: ColoredBox(color: theme.accentPrimary)),
            const Expanded(child: ColoredBox(color: mint)),
          ],
        ),
      ),
    );
  }
}

/// 45° hatch lines in faint ink: empty places, bands behind headings,
/// work in progress.
class Hatch extends ConsumerWidget {
  const Hatch({super.key, this.child, this.alpha = 0.22});

  final Widget? child;
  final double alpha;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    return CustomPaint(
      painter: HatchPainter(theme.textPrimary.withValues(alpha: alpha)),
      child: child,
    );
  }
}

class HatchPainter extends CustomPainter {
  const HatchPainter(this.color, {this.step = 9.2, this.offset = 0});

  final Color color;
  final double step;

  /// Shifts the lines sideways (0..[step]); a moving offset makes the
  /// hatch run (work in progress).
  final double offset;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 1.5;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    for (var x = -size.height - step + offset; x < size.width; x += step) {
      canvas.drawLine(Offset(x, size.height), Offset(x + size.height, 0), p);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(HatchPainter old) =>
      old.color != color || old.step != step || old.offset != offset;
}

/// Faint open contour lines in two opposite corners of the ground.
class ContourPainter extends CustomPainter {
  const ContourPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final reach = math.min(size.width, 520.0);
    _field(canvas, p, Offset(size.width, 0), reach * 0.8, 1, 3.1);
    _field(canvas, p, Offset(0, size.height), reach * 0.9, -1, 7.7);
  }

  void _field(
    Canvas canvas,
    Paint p,
    Offset origin,
    double reach,
    double dir,
    double seed,
  ) {
    for (var i = 0; i < 11; i++) {
      final r = reach * (0.18 + i * 0.075);
      final path = Path();
      for (var a = 0; a <= 60; a++) {
        final t = a / 60 * math.pi / 2;
        final wobble = 1 +
            0.07 * math.sin(t * 5 + seed + i * 0.6) +
            0.04 * math.sin(t * 11 + seed * 2);
        final x = origin.dx - dir * math.cos(t) * r * wobble;
        final y = origin.dy + dir * math.sin(t) * r * wobble * 0.85;
        a == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
      }
      canvas.drawPath(path, p);
    }
  }

  @override
  bool shouldRepaint(ContourPainter old) => old.color != color;
}

/// The small upper-case label above a heading, in the in-world script.
class Eyebrow extends ConsumerWidget {
  const Eyebrow(this.text, {super.key, this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    return Text(
      text.toUpperCase(),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      // Decoration: it grows a little with large text, not so much that it
      // pushes the name it sits over out of a bar.
      textScaler: MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.2),
      style: theme.eyebrow(color: color),
    );
  }
}

/// A section's name: the English label small above, the Chinese bold below,
/// an optional action on the right.
class SectionTitle extends ConsumerWidget {
  const SectionTitle({
    super.key,
    required this.title,
    this.code,
    this.trailing,
    this.size = 20,
    this.padding = const EdgeInsets.only(top: 20, bottom: 10),
  });

  final String title;

  /// The English label (a translation of [title]), or null.
  final String? code;
  final Widget? trailing;
  final double size;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    return Semantics(
      header: true,
      child: Padding(
        padding: padding,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (code != null && code!.isNotEmpty) ...[
                    ExcludeSemantics(child: Eyebrow(code!)),
                    const SizedBox(height: 2),
                  ],
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.heading(size),
                  ),
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 12), trailing!],
          ],
        ),
      ),
    );
  }
}

/// An index tag (`No.024`, a stage code): an ink block with its bottom-right
/// corner cut. [current] fills it with the accent (this one is where you are).
class IndexTag extends ConsumerWidget {
  const IndexTag(
    this.text, {
    super.key,
    this.current = false,
    this.quiet = false,
  });

  final String text;
  final bool current;

  /// A chip-grey tag for secondary codes.
  final bool quiet;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    final bg = current
        ? theme.accentPrimary
        : quiet
            ? theme.surfaceElevated
            : theme.tagBackground;
    final fg = current
        ? theme.onAccent
        : quiet
            ? theme.textPrimary
            : theme.tagForeground;
    return DecoratedBox(
      decoration: ShapeDecoration(color: bg, shape: const CutBorder.br(6)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(7, 1, 11, 1),
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.field(color: fg, size: 12, weight: 600),
        ),
      ),
    );
  }
}

/// Facts in the field face (dates, counts), divided by thin vertical rules.
class FactsRow extends ConsumerWidget {
  const FactsRow(this.items, {super.key, this.color});

  final List<String> items;
  final Color? color;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    final shown = [
      for (final i in items)
        if (i.isNotEmpty) i,
    ];
    return Wrap(
      runSpacing: 2,
      children: [
        for (var i = 0; i < shown.length; i++)
          Container(
            padding: EdgeInsets.only(left: i == 0 ? 0 : 8, right: 8),
            decoration: BoxDecoration(
              border: i == 0
                  ? null
                  : Border(left: BorderSide(color: theme.divider)),
            ),
            child: Text(shown[i], style: theme.field(color: color)),
          ),
      ],
    );
  }
}

/// A filter choice: a chip-grey block with a cut corner and an optional
/// count; the chosen one is filled with the accent and bold.
class FilterBlock extends ConsumerWidget {
  const FilterBlock({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.count,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final int? count;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    final fg = selected ? theme.onAccent : theme.textPrimary;
    return Semantics(
      button: true,
      selected: selected,
      child: PressBuilder(
        enabled: onTap != null,
        builder: (context, down) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap == null
              ? null
              : () {
                  HapticFeedback.selectionClick();
                  onTap!();
                },
          // 48 high to the finger, 36 to the eye.
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: AnimatedContainer(
              duration: Motion.of(context, Motion.press),
              constraints: const BoxConstraints(minHeight: 36, minWidth: 44),
              padding: const EdgeInsets.fromLTRB(12, 0, 16, 0),
              decoration: ShapeDecoration(
                color: selected
                    ? theme.accentPrimary
                    : down
                        ? pressTint(theme.surfaceElevated, theme.textPrimary)
                        : theme.surfaceElevated,
                shape: const CutBorder.br(7),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.ui(
                        14,
                        weight: selected ? 700 : 500,
                        color: fg,
                      ),
                    ),
                  ),
                  if (count != null) ...[
                    const SizedBox(width: 6),
                    Text('$count', style: theme.field(color: fg)),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

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

/// Something to notice (an error, a missing piece): a panel with a hairline
/// frame and an accent flag in front. Never red.
class NoticeBox extends ConsumerWidget {
  const NoticeBox(this.text, {super.key, this.title, this.action});

  final String text;
  final String? title;
  final Widget? action;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    return Semantics(
      liveRegion: true,
      child: Container(
        decoration: BoxDecoration(
          color: theme.cardSurface,
          border: Border.all(color: theme.divider),
        ),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 28,
                color: theme.accentPrimary,
                alignment: Alignment.topCenter,
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  '!',
                  style: theme.ui(16, weight: 800, color: theme.onAccent),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (title != null) ...[
                        Text(title!, style: theme.heading(15)),
                        const SizedBox(height: 4),
                      ],
                      Text(
                        text,
                        style: theme.text(14, color: theme.textPrimary),
                      ),
                      if (action != null) ...[
                        const SizedBox(height: 8),
                        action!,
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// An empty place: a hairline frame filled with hatch, one plain sentence on
/// a paper patch saying what will appear here, and the next step if any.
class EmptyState extends ConsumerWidget {
  const EmptyState({
    super.key,
    required this.text,
    this.title,
    this.action,
  });

  final String text;
  final String? title;
  final Widget? action;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    return Container(
      decoration: BoxDecoration(border: Border.all(color: theme.divider)),
      child: Hatch(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                color: theme.bgPrimary,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (title != null) ...[
                      Text(
                        title!,
                        textAlign: TextAlign.center,
                        style: theme.heading(16),
                      ),
                      const SizedBox(height: 4),
                    ],
                    Text(
                      text,
                      textAlign: TextAlign.center,
                      style: theme.text(14, color: theme.textSecondary),
                    ),
                  ],
                ),
              ),
              if (action != null) ...[const SizedBox(height: 14), action!],
            ],
          ),
        ),
      ),
    );
  }
}

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

/// A small "working" mark where a spinner used to be: a short bar of cells
/// with a lit run walking across.
class BusyMark extends StatelessWidget {
  const BusyMark({super.key, this.width = 96, this.label, this.cells = 12});

  final double width;
  final String? label;
  final int cells;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: width,
        child: SegmentProgress(
          cells: cells,
          height: 6,
          label: label,
          showReadout: false,
        ),
      );
}

/// A centred [BusyMark] for a page that is loading.
class LoadingView extends StatelessWidget {
  const LoadingView({super.key, this.label});

  final String? label;

  @override
  Widget build(BuildContext context) => Center(
        child: Semantics(
          label: label ??
              MaterialLocalizations.of(context).refreshIndicatorSemanticLabel,
          child: BusyMark(width: 144, label: label),
        ),
      );
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
            constraints: const BoxConstraints(minHeight: 44),
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

/// A big figure with its label (a count); [alert] puts it on an accent
/// block (needs a look).
class Figure extends ConsumerWidget {
  const Figure(this.value, this.label, {super.key, this.alert = false});

  final String value;
  final String label;
  final bool alert;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    return Semantics(
      label: '$label $value',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // A long number shrinks to its column rather than running into
          // the next one.
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Container(
              padding: alert ? const EdgeInsets.symmetric(horizontal: 6) : null,
              color: alert ? theme.accentPrimary : null,
              child: Text(
                value,
                maxLines: 1,
                style: sairaStyle(
                  size: 30,
                  weight: 700,
                  width: 112,
                  tabular: true,
                  height: 1.1,
                  color: alert ? theme.onAccent : theme.textPrimary,
                ),
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.ui(13, weight: 500, color: theme.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// A panel (a block of data, a dialog): white, a hairline frame, a short ink
/// tab on its top edge; its bottom-right corner cut when it can be pressed.
class InkPanel extends ConsumerWidget {
  const InkPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.cut = 0,
    this.tab = true,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double cut;
  final bool tab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    return Stack(
      children: [
        DecoratedBox(
          decoration: ShapeDecoration(
            color: theme.cardSurface,
            shape: CutBorder(
              bottomRight: cut,
              side: BorderSide(color: theme.divider),
            ),
          ),
          child: Padding(padding: padding, child: child),
        ),
        if (tab)
          Positioned(
            left: 0,
            top: 0,
            width: 48,
            height: 4,
            child: ColoredBox(color: theme.textPrimary),
          ),
      ],
    );
  }
}

/// A short message at the bottom of the screen: a dark bar with an accent
/// flag, one sentence, gone after two seconds.
void showToast(
  BuildContext context,
  String text, {
  SnackBarAction? action,
  Duration duration = Motion.toastHold,
}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(toastBar(context, text, action: action, duration: duration));
}

/// The [SnackBar] behind [showToast], for code that shows its own.
SnackBar toastBar(
  BuildContext context,
  String text, {
  SnackBarAction? action,
  Duration duration = Motion.toastHold,
}) {
  return SnackBar(
    behavior: SnackBarBehavior.floating,
    backgroundColor: const Color(0xFF161616),
    elevation: 0,
    duration: action == null ? duration : const Duration(seconds: 4),
    padding: EdgeInsets.zero,
    margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
    shape: const RoundedRectangleBorder(),
    action: action,
    content: IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Consumer(
            builder: (context, ref, _) => Container(
              width: 6,
              color: ref.watch(themeProvider).accentPrimary,
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              child: Text(
                text,
                style: sairaStyle(
                  size: 14,
                  weight: 600,
                  color: const Color(0xFFEDEDED),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// Opens a bottom sheet: pushed up in 360 ms with the mechanical curve,
/// closed in 240 ms, no bounce; the scrim fades. Put a [SheetFrame] in it.
Future<T?> showAppSheet<T>(
  BuildContext context,
  WidgetBuilder builder, {
  bool scrollable = true,
}) {
  final still = Motion.reduced(context);
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: scrollable,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    elevation: 0,
    shape: const RoundedRectangleBorder(),
    sheetAnimationStyle: AnimationStyle(
      curve: Motion.mech,
      reverseCurve: Motion.mech.flipped,
      duration: still ? Duration.zero : Motion.sheetIn,
      reverseDuration: still ? Duration.zero : Motion.sheetOut,
    ),
    builder: builder,
  );
}

/// The frame of a bottom sheet: the top-left corner cut, a hatched band with
/// a grabber, the name of what it acts on, then [children].
class SheetFrame extends ConsumerWidget {
  const SheetFrame({
    super.key,
    required this.title,
    required this.children,
    this.code,
    this.padBottom = true,
  });

  final String title;
  final String? code;
  final List<Widget> children;
  final bool padBottom;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: theme.cardSurface,
        shape: const CutBorder(topLeft: 24),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 18,
            child: Hatch(
              child: Center(
                child: Container(
                  width: 40,
                  height: 4,
                  color: theme.textPrimary,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: SectionTitle(
              title: title,
              code: code,
              size: 19,
              padding: EdgeInsets.zero,
            ),
          ),
          ...children,
          if (padBottom)
            SizedBox(height: 12 + MediaQuery.paddingOf(context).bottom),
        ],
      ),
    );
  }
}

/// A bottom sheet without a heading of its own (its content names itself):
/// the panel with its top-left corner cut and the hatched grabber band.
class PlainSheet extends ConsumerWidget {
  const PlainSheet({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: theme.cardSurface,
        shape: const CutBorder(topLeft: 24),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 18,
            child: Hatch(
              child: Center(
                child:
                    Container(width: 40, height: 4, color: theme.textPrimary),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Flexible(child: child),
        ],
      ),
    );
  }
}

/// One action in a sheet or a settings list: a row at least 52 high with a
/// hairline above, a label, an optional field on the right and a `›`.
/// [danger] writes it in red (deleting).
class ActionRow extends ConsumerWidget {
  const ActionRow({
    super.key,
    required this.label,
    this.description,
    this.meta,
    this.icon,
    this.danger = false,
    this.selected = false,
    this.onTap,
    this.trailing,
    this.showChevron = true,
  });

  final String label;
  final String? description;
  final String? meta;
  final IconData? icon;
  final bool danger;

  /// The current choice in a list of choices: an accent block at its left.
  final bool selected;
  final VoidCallback? onTap;
  final Widget? trailing;
  final bool showChevron;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    final fg = danger ? theme.danger : theme.textPrimary;
    return Semantics(
      button: onTap != null,
      selected: selected,
      child: PressRow(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 52),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: theme.divider)),
          ),
          child: Row(
            children: [
              if (selected) ...[
                Container(width: 8, height: 20, color: theme.accentPrimary),
                const SizedBox(width: 12),
              ],
              if (icon != null) ...[
                Icon(
                  icon,
                  size: 22,
                  color: danger ? theme.danger : theme.textSecondary,
                ),
                const SizedBox(width: 14),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style:
                          theme.ui(16, weight: selected ? 700 : 600, color: fg),
                    ),
                    if (description != null && description!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        description!,
                        style: theme.text(
                          13,
                          color: theme.textSecondary,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (meta != null) ...[
                const SizedBox(width: 8),
                Text(meta!, style: theme.field()),
              ],
              if (trailing != null) ...[
                const SizedBox(width: 8),
                trailing!,
              ] else if (showChevron && onTap != null) ...[
                const SizedBox(width: 4),
                ExcludeSemantics(
                  child: Icon(
                    Icons.chevron_right_sharp,
                    size: 22,
                    color: theme.textMuted,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

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
  });

  final Widget head;

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
          top: 0,
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

/// A dialog: a panel with an ink tab, the question in bold Chinese, one
/// sentence on what follows, the buttons at the bottom right (the
/// confirming one last).
class AppDialog extends ConsumerWidget {
  const AppDialog({
    super.key,
    required this.title,
    this.message,
    this.content,
    this.actions = const [],
    this.code,
  });

  final String title;
  final String? message;
  final Widget? content;
  final List<Widget> actions;
  final String? code;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    return InkPanel(
      cut: 20,
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionTitle(
            title: title,
            code: code,
            size: 19,
            padding: EdgeInsets.zero,
          ),
          if (message != null) ...[
            const SizedBox(height: 10),
            Text(message!, style: theme.text(15, color: theme.textSecondary)),
          ],
          if (content != null) ...[const SizedBox(height: 14), content!],
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 16),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              children: actions,
            ),
          ],
        ],
      ),
    );
  }
}

/// Asks to confirm an action; true when confirmed. [danger] for deleting.
Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  String? message,
  required String confirm,
  bool danger = false,
  Key? confirmKey,
  String? cancel,
}) async {
  final ok = await showAppDialog<bool>(
    context,
    (context) => AppDialog(
      title: title,
      message: message,
      actions: [
        AppButton(
          cancel ?? MaterialLocalizations.of(context).cancelButtonLabel,
          small: true,
          kind: ButtonKind.quiet,
          onPressed: () => Navigator.of(context).pop(false),
        ),
        AppButton(
          confirm,
          key: confirmKey,
          small: true,
          kind: danger ? ButtonKind.danger : ButtonKind.go,
          onPressed: () {
            if (danger) HapticFeedback.heavyImpact();
            Navigator.of(context).pop(true);
          },
        ),
      ],
    ),
  );
  return ok ?? false;
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
