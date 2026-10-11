import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/l10n.dart';
import '../theme/app_theme.dart';

/// How many pages [total] items make at [pageSize] a page (at least one).
int pageCountOf(int total, int pageSize) =>
    total <= 0 ? 1 : (total + pageSize - 1) ~/ pageSize;

/// Page boxes of a paged list: first / previous / numbers around the current
/// page / next / last, and the "page x / y" label, which opens a page-number
/// prompt. [keyPrefix] names the list in the keys of its parts.
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
    final target = await showDialog<int>(
      context: context,
      builder: (_) => _JumpDialog(keyPrefix: keyPrefix, pages: pages),
    );
    if (target != null) onPage(target);
  }

  @override
  Widget build(BuildContext context) {
    Widget step(String name, IconData icon, int? to) => IconButton(
          key: ValueKey('$keyPrefix-$name'),
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints.tightFor(width: 34, height: 34),
          padding: EdgeInsets.zero,
          onPressed: to == null ? null : () => onPage(to),
          icon: Icon(icon, size: 22),
        );
    Widget box(int i) {
      final here = i == page;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: InkWell(
          key: ValueKey('$keyPrefix-page-box-${i + 1}'),
          borderRadius: BorderRadius.zero,
          onTap: here ? null : () => onPage(i),
          child: Container(
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            padding: const EdgeInsets.symmetric(horizontal: 6),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: here ? theme.accentPrimary : null,
              border: Border.all(color: here ? theme.accentPrimary : theme.divider),
              borderRadius: BorderRadius.zero,
            ),
            child: Text(
              '${i + 1}',
              style: theme.bodyFont.copyWith(
                fontSize: 14,
                fontWeight: here ? FontWeight.w700 : FontWeight.w400,
                color: here ? theme.onAccent : theme.textPrimary,
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      child: Column(
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                step('first', Icons.first_page_sharp, page == 0 ? null : 0),
                step(
                  'previous',
                  Icons.chevron_left_sharp,
                  page == 0 ? null : page - 1,
                ),
                for (final i in _slots)
                  i == null
                      ? Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Text(
                            '…',
                            style: theme.bodyFont
                                .copyWith(color: theme.textSecondary),
                          ),
                        )
                      : box(i),
                step(
                  'next',
                  Icons.chevron_right_sharp,
                  page >= pages - 1 ? null : page + 1,
                ),
                step(
                  'last',
                  Icons.last_page_sharp,
                  page >= pages - 1 ? null : pages - 1,
                ),
              ],
            ),
          ),
          TextButton(
            key: ValueKey('$keyPrefix-jump'),
            onPressed: () => _jump(context),
            child: Text(
              context.t.readingHistoryPage(page + 1, pages),
              style: theme.bodyFont.copyWith(color: theme.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

/// The page-number prompt; owns its text controller so that it outlives the
/// closing animation.
class _JumpDialog extends StatefulWidget {
  const _JumpDialog({required this.keyPrefix, required this.pages});

  final String keyPrefix;
  final int pages;

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
  Widget build(BuildContext context) => AlertDialog(
        title: Text(context.t.readingHistoryJumpTitle),
        content: TextField(
          key: ValueKey('${widget.keyPrefix}-jump-field'),
          controller: _controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(
            hintText: context.t.readingHistoryJumpHint(widget.pages),
          ),
          onSubmitted: (_) => _submit(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
          ),
          TextButton(
            key: ValueKey('${widget.keyPrefix}-jump-go'),
            onPressed: _submit,
            child: Text(context.t.readingHistoryJumpGo),
          ),
        ],
      );
}
