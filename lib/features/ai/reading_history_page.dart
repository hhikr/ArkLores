import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/userdata/library_ref.dart';
import '../../core/userdata/user_data_provider.dart';
import '../../core/userdata/user_data_store.dart';
import '../../shared/l10n/l10n.dart';
import '../../shared/providers/theme_provider.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/floating_bar.dart';
import '../../shared/widgets/page_bar.dart';
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

    return FloatingScaffold(
      title: context.t.readingHistoryTitle,
      scrollUnder: true,
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
                  ? PageBar(
                      theme: theme,
                      keyPrefix: 'reading-history',
                      page: page,
                      pages: pages,
                      onPage: _goTo,
                    )
                  : null;
              return ListView(
                key: ValueKey('reading-history-page-$page'),
                padding: floatingPadding(
                  context,
                  const EdgeInsets.symmetric(vertical: 8),
                ),
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

  void _goTo(int page) {
    if (mounted) setState(() => _page = page);
  }

  /// Takes [entry] out of the history (the swipe and the button of a row).
  Future<void> _remove(ReadingEntry entry) async {
    setState(() => _removed.add(entry.ref));
    final item = LibraryRef.tryParse(entry.ref);
    if (item != null) {
      final store = await ref.read(userDataStoreProvider.future);
      await store.clearHistory(item);
    }
    _refresh();
  }

  Widget _empty(BuildContext context, AppThemeTokens theme) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.menu_book_sharp,
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
        child: Icon(Icons.delete_outline_sharp, color: theme.danger),
      ),
      onDismissed: (_) => _remove(entry),
      child: LibraryRow(
        key: ValueKey('reading-tile-${entry.ref}'),
        leading: Icon(Icons.menu_book_sharp, color: theme.accentText),
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
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (entry.progress != null) readMark(context, theme, entry),
            IconButton(
              key: ValueKey('reading-history-remove-${entry.ref}'),
              visualDensity: VisualDensity.compact,
              tooltip: context.t.readingHistoryRemove,
              onPressed: () => _remove(entry),
              icon: Icon(
                Icons.delete_outline_sharp,
                size: 20,
                color: theme.textSecondary,
              ),
            ),
          ],
        ),
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
