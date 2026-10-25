import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/l10n.dart';
import '../theme/app_theme.dart';
import '../theme/cut_border.dart';
import '../theme/motion.dart';
import 'ef_widgets.dart';
import 'press_feedback.dart';

/// How many pages [total] items make at [pageSize] a page (at least one).
int pageCountOf(int total, int pageSize) =>
    total <= 0 ? 1 : (total + pageSize - 1) ~/ pageSize;

/// Page boxes of a paged list: first / previous / numbers around the current
/// page / next / last, and the "page x / y" label, which opens a page-number
/// prompt. Every box is 44 to the finger; the current page is an accent
/// block. [keyPrefix] names the list in the keys of its parts.
class PageBar extends StatelessWidget {
  const PageBar({
    super.key,
    required this.theme,
    required this.keyPrefix,
    required this.page,
    required this.pages,
    required this.onPage,
  });

  final AppThemeTokens theme;
  final String keyPrefix;

  /// 0-based.
  final int page;
  final int pages;
  final ValueChanged<int> onPage;

  /// Page numbers to show (0-based); null is a gap.
  List<int?> get _slots {
    if (pages <= 7) return [for (var i = 0; i < pages; i++) i];
    final near = {0, pages - 1, page - 1, page, page + 1}
        .where((i) => i >= 0 && i < pages)
        .toList()
      ..sort();
    final out = <int?>[];
    for (var i = 0; i < near.length; i++) {
      if (i > 0 && near[i] - near[i - 1] > 1) out.add(null);
      out.add(near[i]);
    }
    return out;
  }

  /// Asks for a page number and goes there.
  Future<void> _jump(BuildContext context) async {
    final target = await showAppDialog<int>(
      context,
      (_) => _JumpDialog(keyPrefix: keyPrefix, pages: pages, theme: theme),
    );
    if (target != null) onPage(target);
  }

  @override
  Widget build(BuildContext context) {
    final m = MaterialLocalizations.of(context);
    Widget step(String name, IconData icon, String tooltip, int? to) =>
        SquareIconButton(
          key: ValueKey('$keyPrefix-$name'),
          tooltip: tooltip,
          icon: icon,
          onPressed: to == null ? null : () => onPage(to),
        );
    Widget box(int i) {
      final here = i == page;
      return Semantics(
        button: !here,
        selected: here,
        label: context.t.readingHistoryPage(i + 1, pages),
        excludeSemantics: true,
        child: PressBuilder(
          enabled: !here,
          builder: (context, down) => GestureDetector(
            key: ValueKey('$keyPrefix-page-box-${i + 1}'),
            behavior: HitTestBehavior.opaque,
            onTap: here
                ? null
                : () {
                    HapticFeedback.selectionClick();
                    onPage(i);
                  },
            child: SizedBox(
              height: 48,
              child: Center(
                child: AnimatedContainer(
                  duration: Motion.of(context, Motion.press),
                  curve: Motion.mech,
                  constraints:
                      const BoxConstraints(minWidth: 40, minHeight: 40),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  alignment: Alignment.center,
                  decoration: ShapeDecoration(
                    color: here
                        ? theme.accentPrimary
                        : down
                            ? pressTint(theme.surfaceElevated, theme.textPrimary)
                            : theme.surfaceElevated,
                    shape: here
                        ? const RoundedRectangleBorder()
                        : const CutBorder.br(6),
                  ),
                  child: Text(
                    '${i + 1}',
                    style: theme.field(
                      size: 15,
                      weight: here ? 700 : 500,
                      color: here ? theme.onAccent : theme.textPrimary,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                step(
                  'first',
                  Icons.first_page_sharp,
                  m.firstPageTooltip,
                  page == 0 ? null : 0,
                ),
                step(
                  'previous',
                  Icons.chevron_left_sharp,
                  m.previousPageTooltip,
                  page == 0 ? null : page - 1,
                ),
                for (final i in _slots)
                  i == null
                      ? Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Text('…', style: theme.field()),
                        )
                      : Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          child: box(i),
                        ),
                step(
                  'next',
                  Icons.chevron_right_sharp,
                  m.nextPageTooltip,
                  page >= pages - 1 ? null : page + 1,
                ),
                step(
                  'last',
                  Icons.last_page_sharp,
                  m.lastPageTooltip,
                  page >= pages - 1 ? null : pages - 1,
                ),
              ],
            ),
          ),
          AppButton(
            context.t.readingHistoryPage(page + 1, pages),
            key: ValueKey('$keyPrefix-jump'),
            small: true,
            kind: ButtonKind.quiet,
            icon: Icons.unfold_more_sharp,
            onPressed: () => _jump(context),
          ),
        ],
      ),
    );
  }
}

/// The page-number prompt; owns its text controller so that it outlives the
/// closing animation.
class _JumpDialog extends StatefulWidget {
  const _JumpDialog({
    required this.keyPrefix,
    required this.pages,
    required this.theme,
  });

  final String keyPrefix;
  final int pages;
  final AppThemeTokens theme;

  @override
  State<_JumpDialog> createState() => _JumpDialogState();
}

class _JumpDialogState extends State<_JumpDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final n = int.tryParse(_controller.text.trim());
    Navigator.of(context).pop(n == null ? null : n.clamp(1, widget.pages) - 1);
  }

  @override
  Widget build(BuildContext context) => AppDialog(
        title: context.t.readingHistoryJumpTitle,
        content: TextField(
          key: ValueKey('${widget.keyPrefix}-jump-field'),
          controller: _controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: widget.theme.field(color: widget.theme.textPrimary, size: 16),
          decoration: InputDecoration(
            hintText: context.t.readingHistoryJumpHint(widget.pages),
          ),
          onSubmitted: (_) => _submit(),
        ),
        actions: [
          AppButton(
            MaterialLocalizations.of(context).cancelButtonLabel,
            small: true,
            kind: ButtonKind.quiet,
            onPressed: () => Navigator.of(context).pop(),
          ),
          AppButton(
            context.t.readingHistoryJumpGo,
            key: ValueKey('${widget.keyPrefix}-jump-go'),
            small: true,
            kind: ButtonKind.go,
            onPressed: _submit,
          ),
        ],
      );
}
