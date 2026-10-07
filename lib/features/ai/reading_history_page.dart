import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/userdata/library_ref.dart';
import '../../core/userdata/user_data_provider.dart';
import '../../core/userdata/user_data_store.dart';
import '../../shared/l10n/l10n.dart';
import '../../shared/providers/theme_provider.dart';
import '../../shared/theme/app_theme.dart';
import '../library/library_widgets.dart';

/// "Recently read": the stories the user opened, newest first. Tapping one
/// reopens it at the line it was left at (found again by its text if the
/// story changed since).
class ReadingHistoryPage extends ConsumerStatefulWidget {
  const ReadingHistoryPage({super.key});

  @override
  ConsumerState<ReadingHistoryPage> createState() => _ReadingHistoryPageState();
}

class _ReadingHistoryPageState extends ConsumerState<ReadingHistoryPage> {
  /// Swiped away, not yet gone from the database: a Dismissible must leave
  /// the tree in the same frame.
  final Set<String> _removed = {};

  /// 0-based page of the list; only the page shown is read from the database.
  int _page = 0;

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider);
    final count = ref.watch(readingCountProvider);
    final total = count.valueOrNull ?? 0;
    final pages = total == 0 ? 1 : (total + historyPageSize - 1) ~/ historyPageSize;
    final page = _page.clamp(0, pages - 1);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: theme.bgSecondary,
        elevation: 0,
        title: Text(
          context.t.readingHistoryTitle,
          style: theme.titleFont.copyWith(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        actions: [
          if (total > 0)
            TextButton(
              key: const ValueKey('reading-history-clear'),
              onPressed: _confirmClear,
              // Not the theme's primary (the signal yellow, faint as text).
              style: TextButton.styleFrom(foregroundColor: theme.textPrimary),
              child: Text(context.t.readingHistoryClear),
            ),
        ],
      ),
      body: count.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => _empty(context, theme),
        data: (_) {
          if (total == 0) return _empty(context, theme);
          final entries = ref.watch(readingPageProvider(page));
          return entries.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, __) => _empty(context, theme),
            data: (all) {
              final shown = [
                for (final e in all)
                  if (!_removed.contains(e.ref)) e,
              ];
              final divider = Divider(
                height: 1,
                indent: 16,
                endIndent: 16,
                color: theme.divider,
              );
              final pager = pages > 1
                  ? _Pager(
                      theme: theme,
                      page: page,
                      pages: pages,
                      onPage: _goTo,
                      onJump: () => _jump(page, pages),
                    )
                  : null;
              return ListView(
                key: ValueKey('reading-history-page-$page'),
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  if (pager != null) ...[
                    KeyedSubtree(
                      key: const ValueKey('reading-history-pager-top'),
                      child: pager,
                    ),
                    divider,
                  ],
                  for (final e in shown) ...[
                    _tile(context, theme, e),
                    divider,
                  ],
                  if (pager != null)
                    KeyedSubtree(
                      key: const ValueKey('reading-history-pager-bottom'),
                      child: pager,
                    ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  void _goTo(int page) => setState(() => _page = page);

  /// Asks for a page number and goes there.
  Future<void> _jump(int page, int pages) async {
    final target = await showDialog<int>(
      context: context,
      builder: (_) => _JumpDialog(pages: pages),
    );
    if (target != null && mounted) _goTo(target);
  }
  Widget _empty(BuildContext context, AppThemeTokens theme) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.menu_book_rounded,
                size: 56,
                color: theme.textSecondary.withValues(alpha: 0.4),
              ),
              const SizedBox(height: 16),
              Text(
                context.t.readingHistoryEmpty,
                style: theme.bodyFont.copyWith(color: theme.textSecondary),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );

  Widget _tile(
    BuildContext context,
    AppThemeTokens theme,
    ReadingEntry entry,
  ) {
    final item = LibraryRef.tryParse(entry.ref);
    return Dismissible(
      key: ValueKey('reading-${entry.ref}'),
      direction: DismissDirection.endToStart,
      background: Container(
        color: theme.danger.withValues(alpha: 0.15),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: Icon(Icons.delete_outline_rounded, color: theme.danger),
      ),
      onDismissed: (_) async {
        setState(() => _removed.add(entry.ref));
        if (item != null) {
          final store = await ref.read(userDataStoreProvider.future);
          await store.clearHistory(item);
        }
        _refresh();
      },
      child: LibraryRow(
        key: ValueKey('reading-tile-${entry.ref}'),
        leading: Icon(Icons.menu_book_rounded, color: theme.accentText),
        title: readingTitle(ref, entry),
        subtitle: [
          '${_time(entry.openedAt)} · '
              '${context.t.readingHistoryLine(entry.lineIndex + 1)}'
              '${entry.hasCompleted ? ' · ${context.t.libraryReadTimes(entry.completedCount)}' : ''}',
          if (entry.snippet.isNotEmpty) entry.snippet,
        ].join('\n'),
        progress: entry.progress != null && !entry.finished
            ? entry.progress
            : null,
        trailing: entry.progress == null
            ? null
            : readMark(context, theme, entry),
        // Only stories are readable so far; other kinds are skipped.
        onTap: item == null || item.kind != LibraryRefKind.story
            ? null
            : () => openStory(context, item.id, resume: entry),
      ),
    );
  }

  void _refresh() {
    ref
      ..invalidate(recentReadingProvider)
      ..invalidate(readingCountProvider)
      ..invalidate(readingPageProvider);
  }

  Future<void> _confirmClear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(ctx.t.readingHistoryClearConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
          ),
          TextButton(
            key: const ValueKey('reading-history-clear-confirm'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(ctx.t.readingHistoryClear),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(_removed.clear);
    final store = await ref.read(userDataStoreProvider.future);
    await store.clearHistory();
    _page = 0;
    _refresh();
  }

  static String _time(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
  }
}

/// Page boxes: first / previous / numbers around the current page / next /
/// last, and the "page x / y" label, which opens a page-number prompt.
class _Pager extends StatelessWidget {
  const _Pager({
    required this.theme,
    required this.page,
    required this.pages,
    required this.onPage,
    required this.onJump,
  });

  final AppThemeTokens theme;
  final int page;
  final int pages;
  final ValueChanged<int> onPage;
  final VoidCallback onJump;

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

  @override
  Widget build(BuildContext context) {
    Widget step(Key key, IconData icon, int? to) => IconButton(
          key: key,
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
          key: ValueKey('reading-history-page-box-${i + 1}'),
          borderRadius: BorderRadius.circular(6),
          onTap: here ? null : () => onPage(i),
          child: Container(
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            padding: const EdgeInsets.symmetric(horizontal: 6),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: here ? theme.accentPrimary : null,
              border: Border.all(color: here ? theme.accentPrimary : theme.divider),
              borderRadius: BorderRadius.circular(6),
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
                step(
                  const ValueKey('reading-history-first'),
                  Icons.first_page_rounded,
                  page == 0 ? null : 0,
                ),
                step(
                  const ValueKey('reading-history-previous'),
                  Icons.chevron_left_rounded,
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
                  const ValueKey('reading-history-next'),
                  Icons.chevron_right_rounded,
                  page >= pages - 1 ? null : page + 1,
                ),
                step(
                  const ValueKey('reading-history-last'),
                  Icons.last_page_rounded,
                  page >= pages - 1 ? null : pages - 1,
                ),
              ],
            ),
          ),
          TextButton(
            key: const ValueKey('reading-history-jump'),
            onPressed: onJump,
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
  const _JumpDialog({required this.pages});

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
          key: const ValueKey('reading-history-jump-field'),
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
            key: const ValueKey('reading-history-jump-go'),
            onPressed: _submit,
            child: Text(context.t.readingHistoryJumpGo),
          ),
        ],
      );
}