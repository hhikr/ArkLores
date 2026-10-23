import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/l10n/l10n.dart';
import '../../shared/providers/bookmark_provider.dart';
import '../../shared/providers/theme_provider.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/ef_widgets.dart';
import '../../shared/widgets/page_frame.dart';
import 'bookmark_service.dart';

/// Bookmark management page: a row per bookmark (tap opens it); removing
/// one (its button, or a swipe to the left) can be undone.
class BookmarkPage extends ConsumerWidget {
  const BookmarkPage({super.key});

  static const routeName = '/bookmarks';

  void _remove(BuildContext context, WidgetRef ref, Bookmark bookmark) {
    final notifier = ref.read(bookmarkProvider.notifier);
    notifier.remove(bookmark.id);
    showToast(
      context,
      context.t.bookmarksRemoved,
      action: SnackBarAction(
        label: context.t.commonUndo,
        onPressed: () => notifier.toggle(
          title: bookmark.title,
          url: bookmark.url,
          site: bookmark.site,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    final bookmarkAsync = ref.watch(bookmarkProvider);

    return PageScaffold(
      title: context.t.bookmarksTitle,
      scrollUnder: true,
      body: bookmarkAsync.when(
        loading: () => const LoadingView(),
        error: (err, stack) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: NoticeBox(context.t.bookmarksLoadFailed(err.toString())),
          ),
        ),
        data: (bookmarks) {
          if (bookmarks.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: EmptyState(
                  title: context.t.bookmarksEmpty,
                  text: context.t.bookmarksEmptyDesc,
                ),
              ),
            );
          }
          return ListView.builder(
            padding: pagePadding(
              context,
              const EdgeInsets.fromLTRB(16, 12, 16, 24),
            ),
            itemCount: bookmarks.length + 1,
            itemBuilder: (context, index) {
              if (index == bookmarks.length) {
                return Divider(height: 1, color: theme.divider);
              }
              final bookmark = bookmarks[index];
              return _BookmarkListItem(
                index: index,
                bookmark: bookmark,
                theme: theme,
                onTap: () => Navigator.of(context).pop(bookmark),
                onDelete: () => _remove(context, ref, bookmark),
              );
            },
          );
        },
      ),
    );
  }
}

class _BookmarkListItem extends StatelessWidget {
  const _BookmarkListItem({
    required this.index,
    required this.bookmark,
    required this.theme,
    required this.onTap,
    required this.onDelete,
  });

  final int index;
  final Bookmark bookmark;
  final AppThemeTokens theme;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: ValueKey(bookmark.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: theme.danger,
        child: Text(
          context.t.bookmarksDelete,
          style: theme.ui(15, weight: 700, color: theme.cardSurface),
        ),
      ),
      onDismissed: (_) => onDelete(),
      child: Column(
        children: [
          Divider(height: 1, color: theme.divider),
          PressRow(
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 60),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 0, 8),
                child: Row(
                  children: [
                    SizedBox(
                      width: 36,
                      child: Text(
                        (index + 1).toString().padLeft(2, '0'),
                        style: theme.field(color: theme.textMuted, size: 14),
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            bookmark.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.text(16, weight: FontWeight.w500, height: 1.4),
                          ),
                          const SizedBox(height: 2),
                          Text(bookmark.siteLabel, style: theme.field()),
                        ],
                      ),
                    ),
                    SquareIconButton(
                      icon: Icons.delete_outline_sharp,
                      tooltip: context.t.bookmarksDelete,
                      color: theme.danger,
                      onPressed: onDelete,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
