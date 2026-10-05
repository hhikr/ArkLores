import 'package:flutter/material.dart';
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

  /// 0-based page of the list; the history is shown a page at a time.
  int _page = 0;
  static const int _pageSize = 15;

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider);
    final entries = ref.watch(recentReadingProvider);
    final hasAny = entries.valueOrNull?.isNotEmpty ?? false;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: theme.bgSecondary,
        elevation: 0,
        title: Text(
          context.t.readingHistoryTitle,
          style: theme.titleFont.copyWith(fontSize: 20),
        ),
        actions: [
          if (hasAny)
            TextButton(
              key: const ValueKey('reading-history-clear'),
              onPressed: _confirmClear,
              child: Text(context.t.readingHistoryClear),
            ),
        ],
      ),
      body: entries.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => _empty(context, theme),
        data: (all) {
          final list = [
            for (final e in all)
              if (!_removed.contains(e.ref)) e,
          ];
          if (list.isEmpty) return _empty(context, theme);
          final pages = (list.length + _pageSize - 1) ~/ _pageSize;
          final page = _page.clamp(0, pages - 1);
          final shown = list.skip(page * _pageSize).take(_pageSize).toList();
          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: shown.length + (pages > 1 ? 1 : 0),
            separatorBuilder: (_, __) => Divider(
              height: 1,
              indent: 16,
              endIndent: 16,
              color: theme.divider,
            ),
            itemBuilder: (context, i) => i < shown.length
                ? _tile(context, theme, shown[i])
                : _pager(context, theme, page, pages),
          );
        },
      ),
    );
  }

  Widget _pager(BuildContext context, AppThemeTokens theme, int page, int pages) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              key: const ValueKey('reading-history-previous'),
              onPressed: page == 0 ? null : () => setState(() => _page = page - 1),
              icon: const Icon(Icons.chevron_left_rounded),
            ),
            Text(
              context.t.readingHistoryPage(page + 1, pages),
              style: theme.bodyFont.copyWith(color: theme.textSecondary),
            ),
            IconButton(
              key: const ValueKey('reading-history-next'),
              onPressed:
                  page >= pages - 1 ? null : () => setState(() => _page = page + 1),
              icon: const Icon(Icons.chevron_right_rounded),
            ),
          ],
        ),
      );

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
        ref.invalidate(recentReadingProvider);
      },
      child: LibraryRow(
        key: ValueKey('reading-tile-${entry.ref}'),
        leading: Icon(Icons.menu_book_rounded, color: theme.accentText),
        title: readingTitle(ref, entry),
        subtitle: [
          '${_time(entry.openedAt)} · '
              '${context.t.readingHistoryLine(entry.lineIndex + 1)}',
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
    ref.invalidate(recentReadingProvider);
  }

  static String _time(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
  }
}
