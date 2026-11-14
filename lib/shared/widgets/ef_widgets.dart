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

part 'ef_buttons.dart';
part 'ef_folds.dart';
part 'ef_controls.dart';

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
  });

  final String title;
  final String? code;
  final List<Widget> children;

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
