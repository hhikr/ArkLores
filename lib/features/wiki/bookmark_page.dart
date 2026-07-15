import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/l10n/l10n.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/providers/bookmark_provider.dart';
import '../../shared/providers/theme_provider.dart';
import '../../shared/widgets/theme_aware_card.dart';
import 'bookmark_service.dart';

/// Bookmark management page.
class BookmarkPage extends ConsumerWidget {
  const BookmarkPage({super.key});

  static const routeName = '/bookmarks';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    final bookmarkAsync = ref.watch(bookmarkProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: theme.bgSecondary,
        title: Text(
          context.t.bookmarksTitle,
          style: theme.titleFont.copyWith(fontSize: 18),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          color: theme.accentPrimary,
          onPressed: () => Navigator.of(context).pop(),
        ),
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: bookmarkAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(
          child: Text(
            context.t.bookmarksLoadFailed(err.toString()),
            style: theme.bodyFont.copyWith(color: theme.danger),
          ),
        ),
        data: (bookmarks) {
          if (bookmarks.isEmpty) {
            return _EmptyState(theme: theme);
          }
          return ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            itemCount: bookmarks.length,
            itemBuilder: (context, index) {
              final bookmark = bookmarks[index];
              return _BookmarkListItem(
                bookmark: bookmark,
                theme: theme,
                onTap: () => Navigator.of(context).pop(bookmark),
                onDelete: () {
                  ref.read(bookmarkProvider.notifier).remove(bookmark.id);
                },
              );
            },
          );
        },
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final AppThemeTokens theme;

  const _EmptyState({required this.theme});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.bookmark_border_rounded,
                size: 64, color: theme.accentPrimary.withValues(alpha: 0.3)),
            const SizedBox(height: 16),
            Text(context.t.bookmarksEmpty,
                style: theme.titleFont.copyWith(fontSize: 20)),
            const SizedBox(height: 8),
            Text(context.t.bookmarksEmptyDesc,
                textAlign: TextAlign.center,
                style: theme.bodyFont.copyWith(
                    color: theme.textSecondary, fontSize: 14, height: 1.4)),
          ],
        ),
      ),
    );
  }
}

class _BookmarkListItem extends StatelessWidget {
  final Bookmark bookmark;
  final AppThemeTokens theme;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _BookmarkListItem({
    required this.bookmark,
    required this.theme,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: ValueKey(bookmark.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        decoration: BoxDecoration(
          color: theme.danger,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(Icons.delete_rounded, color: Colors.white, size: 28),
      ),
      onDismissed: (_) => onDelete(),
      child: ThemeAwareCard(
        onTap: onTap,
        child: Row(
          children: [
            Icon(Icons.bookmark_rounded, color: theme.wikiBadgeColor, size: 22),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(bookmark.title,
                      style: theme.titleFont.copyWith(fontSize: 15),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(bookmark.siteLabel,
                      style: theme.bodyFont
                          .copyWith(color: theme.textSecondary, fontSize: 12)),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                color: theme.textSecondary, size: 20),
          ],
        ),
      ),
    );
  }
}
