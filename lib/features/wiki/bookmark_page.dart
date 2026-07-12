import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/theme/app_theme.dart';
import '../../shared/providers/bookmark_provider.dart';
import '../../shared/providers/theme_provider.dart';
import '../../shared/widgets/theme_aware_card.dart';
import 'bookmark_service.dart';

/// Bookmark management page.
///
/// Displays all saved bookmarks in a scrollable list with swipe-to-delete.
/// Tapping a bookmark pops the page and returns the selected [Bookmark].
class BookmarkPage extends ConsumerWidget {
  const BookmarkPage({super.key});

  /// Route name for navigation.
  static const routeName = '/bookmarks';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    final bookmarkAsync = ref.watch(bookmarkProvider);

    return Scaffold(
      backgroundColor: theme.bgPrimary,
      appBar: AppBar(
        backgroundColor: theme.bgSecondary,
        title: Text(
          'Bookmarks',
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
            'Failed to load bookmarks: $err',
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

/// Empty state shown when there are no bookmarks.
class _EmptyState extends StatelessWidget {
  final AppThemeTokens theme;

  const _EmptyState({required this.theme});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.bookmark_border_rounded,
              size: 72,
              color: theme.textSecondary.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 16),
            Text(
              'No bookmarks yet',
              style: theme.titleFont.copyWith(
                fontSize: 20,
                color: theme.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Tap the bookmark icon in the toolbar\nto save your favorite wiki pages.',
              textAlign: TextAlign.center,
              style: theme.bodyFont.copyWith(
                color: theme.textSecondary,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A single bookmark list item with swipe-to-delete.
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
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: theme.danger,
          borderRadius: theme.cardRadius,
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: Icon(
          Icons.delete_rounded,
          color: theme.textPrimary,
          size: 24,
        ),
      ),
      confirmDismiss: (_) async {
        return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: theme.cardSurface,
            title: Text(
              'Delete bookmark?',
              style: theme.titleFont,
            ),
            content: Text(
              'Remove "${bookmark.title}" from your bookmarks?',
              style: theme.bodyFont,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text(
                  'Cancel',
                  style: theme.bodyFont.copyWith(color: theme.textSecondary),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: Text(
                  'Delete',
                  style: theme.bodyFont.copyWith(color: theme.danger),
                ),
              ),
            ],
          ),
        );
      },
      onDismissed: (_) => onDelete(),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: ThemeAwareCard(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          onTap: onTap,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Site indicator
              Icon(
                Icons.public_rounded,
                size: 18,
                color: theme.wikiBadgeColor,
              ),
              const SizedBox(width: 10),

              // Text content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title
                    Text(
                      bookmark.title,
                      style: theme.titleFont.copyWith(fontSize: 14),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    // URL
                    Text(
                      bookmark.url,
                      style: theme.bodyFont.copyWith(
                        fontSize: 11,
                        color: theme.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    // Meta row: site badge + date
                    Row(
                      children: [
                        // Site badge
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: theme.wikiBadgeColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            bookmark.siteLabel,
                            style: theme.bodyFont.copyWith(
                              fontSize: 10,
                              color: theme.wikiBadgeColor,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Date
                        Text(
                          _formatDate(bookmark.createdAt),
                          style: theme.bodyFont.copyWith(
                            fontSize: 10,
                            color: theme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Chevron
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: theme.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(int timestamp) {
    final dt = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final y = dt.year;
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final h = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $h:$min';
  }
}
