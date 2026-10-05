import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/userdata/library_ref.dart';
import '../../core/userdata/user_data_provider.dart';
import '../../core/userdata/user_data_store.dart';
import '../../shared/l10n/l10n.dart';
import '../../shared/providers/theme_provider.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/smooth_page_route.dart';
import 'story_reader_page.dart';

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
          return list.isEmpty
            ? _empty(context, theme)
            : ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: list.length,
                separatorBuilder: (_, __) => Divider(
                  height: 1,
                  indent: 16,
                  endIndent: 16,
                  color: theme.divider,
                ),
                itemBuilder: (context, i) => _tile(context, theme, list[i]),
              );
        },
      ),
    );
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
        ref.invalidate(recentReadingProvider);
      },
      child: ListTile(
        key: ValueKey('reading-tile-${entry.ref}'),
        leading: Icon(Icons.menu_book_rounded, color: theme.accentText),
        title: Text(
          entry.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.titleFont.copyWith(fontSize: 15),
        ),
        subtitle: Text(
          [
            '${_time(entry.openedAt)} · '
                '${context.t.readingHistoryLine(entry.lineIndex + 1)}',
            if (entry.snippet.isNotEmpty) entry.snippet,
          ].join('\n'),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.bodyFont.copyWith(
            fontSize: 12,
            color: theme.textSecondary,
          ),
        ),
        isThreeLine: entry.snippet.isNotEmpty,
        // Only stories are readable so far; other kinds are skipped.
        onTap: item == null || item.kind != LibraryRefKind.story
            ? null
            : () => Navigator.of(context).push(
                  smoothPageRoute<void>(
                    builder: (_) => StoryReaderPage(
                      storyId: item.id,
                      highlightStart: entry.lineIndex,
                      highlightEnd: entry.lineIndex,
                      snippet: entry.snippet,
                    ),
                  ),
                ),
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
