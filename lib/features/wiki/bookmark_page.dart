import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/l10n/l10n.dart';
import '../../shared/providers/bookmark_provider.dart';
import '../../shared/providers/theme_provider.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/floating_bar.dart';
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

    return FloatingScaffold(
      title: context.t.bookmarksTitle,
      scrollUnder: true,
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
            padding: floatingPadding(
              context,
              const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
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

  const _EmptyState({required this.theme});
  final AppThemeTokens theme;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.bookmark_border_sharp,
                size: 64, color: theme.accentPrimary.withValues(alpha: 0.3),),
            const SizedBox(height: 16),
            Text(context.t.bookmarksEmpty,
                style: theme.titleFont.copyWith(fontSize: 20),),
            const SizedBox(height: 8),
            Text(context.t.bookmarksEmptyDesc,
                textAlign: TextAlign.center,
                style: theme.bodyFont.copyWith(
                    color: theme.textSecondary, fontSize: 14, height: 1.4,),),
          ],
        ),
      ),
    );
  }
}

class _BookmarkListItem extends StatelessWidget {

  const _BookmarkListItem({
    required this.bookmark,
    required this.theme,
    required this.onTap,
    required this.onDelete,
  });
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
        padding: const EdgeInsets.only(right: 24),
        decoration: BoxDecoration(
          color: theme.danger,
          borderRadius: BorderRadius.zero,
        ),
        child: Icon(Icons.delete_sharp, color: Colors.white, size: 28),
      ),
      onDismissed: (_) => onDelete(),
      child: ThemeAwareCard(
        onTap: onTap,
        child: Row(
          children: [
            Icon(Icons.bookmark_sharp, color: theme.wikiBadgeColor, size: 22),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(bookmark.title,
                      style: theme.titleFont.copyWith(fontSize: 15),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,),
                  const SizedBox(height: 2),
                  Text(bookmark.siteLabel,
                      style: theme.bodyFont
                          .copyWith(color: theme.textSecondary, fontSize: 12),),
                ],
              ),
            ),
            Icon(Icons.chevron_right_sharp,
                color: theme.textSecondary, size: 20,),
          ],
        ),
      ),
    );
  }
}
