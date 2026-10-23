import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/userdata/library_ref.dart';
import '../../core/userdata/user_data_provider.dart';
import '../../core/userdata/user_data_store.dart';
import '../../shared/l10n/l10n.dart';
import '../../shared/providers/theme_provider.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/ef_widgets.dart';
import '../../shared/widgets/page_bar.dart';
import '../../shared/widgets/page_frame.dart';
import '../library/library_widgets.dart';

/// "Recently read": the stories the user opened, newest first. Tapping one
/// reopens it at the line it was left at (found again by its text if the
/// story changed since). A row is removed with its button or a swipe to the
/// left; clearing all asks first.
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

    return PageScaffold(
      title: context.t.readingHistoryTitle,
      scrollUnder: true,
      actions: [
        if (total > 0)
          AppButton(
            context.t.readingHistoryClear,
            key: const ValueKey('reading-history-clear'),
            small: true,
            kind: ButtonKind.quiet,
            onPressed: _confirmClear,
          ),
      ],
      body: count.when(
        loading: () => const LoadingView(),
        error: (_, __) => _empty(context, theme),
        data: (_) {
          if (total == 0) return _empty(context, theme);
          final entries = ref.watch(readingPageProvider(page));
          return entries.when(
            loading: () => const LoadingView(),
            error: (_, __) => _empty(context, theme),
            data: (all) {
              final shown = [
                for (final e in all)
                  if (!_removed.contains(e.ref)) e,
              ];
              final divider = rowDivider(theme);
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
                padding: pagePadding(
                  context,
                  const EdgeInsets.fromLTRB(16, 8, 16, 24),
                ),
                children: [
                  if (pager != null)
                    KeyedSubtree(
                      key: const ValueKey('reading-history-pager-top'),
                      child: pager,
                    ),
                  SectionTitle(
                    title: context.t.readingHistoryTitle,
                    code: 'recent',
                    trailing: Text('$total', style: theme.field()),
                  ),
                  for (final e in shown) ...[
                    divider,
                    _tile(context, theme, e),
                  ],
                  divider,
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
          padding: const EdgeInsets.all(24),
          child: EmptyState(text: context.t.readingHistoryEmpty),
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
        color: theme.danger,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: Text(
          context.t.readingHistoryRemove,
          style: theme.ui(15, weight: 700, color: theme.cardSurface),
        ),
      ),
      onDismissed: (_) => _remove(entry),
      child: LibraryRow(
        key: ValueKey('reading-tile-${entry.ref}'),
        title: readingTitle(ref, entry),
        subtitle: [
          [
            _time(entry.openedAt),
            context.t.readingHistoryLine(entry.lineIndex + 1),
            if (entry.hasCompleted)
              context.t.libraryReadTimes(entry.completedCount),
          ].join(' / '),
          if (entry.snippet.isNotEmpty) entry.snippet,
        ].join('\n'),
        progress: entry.progress != null && !entry.finished
            ? entry.progress
            : null,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (entry.progress != null) readMark(context, theme, entry),
            SquareIconButton(
              key: ValueKey('reading-history-remove-${entry.ref}'),
              tooltip: context.t.readingHistoryRemove,
              onPressed: () => _remove(entry),
              icon: Icons.delete_outline_sharp,
              color: theme.danger,
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
    final ok = await confirmAction(
      context,
      title: context.t.readingHistoryClearConfirm,
      confirm: context.t.readingHistoryClear,
      danger: true,
      confirmKey: const ValueKey('reading-history-clear-confirm'),
    );
    if (!ok) return;
    setState(_removed.clear);
    final store = await ref.read(userDataStoreProvider.future);
    await store.clearHistory();
    _page = 0;
    _refresh();
  }

  static String _time(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year}.${two(t.month)}.${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
  }
}
