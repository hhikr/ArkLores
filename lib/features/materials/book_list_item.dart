import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/providers/theme_provider.dart';
import '../../shared/widgets/theme_aware_card.dart';

/// A single book entry in the materials list.
///
/// Displays display name, file name, chunk count, import time.
/// Supports swipe-to-delete and tap-to-edit display name.
class BookListItem extends ConsumerWidget {
  final String id;
  final String fileName;
  final String displayName;
  final int chunkCount;
  final int importedAt;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;

  const BookListItem({
    super.key,
    required this.id,
    required this.fileName,
    required this.displayName,
    required this.chunkCount,
    required this.importedAt,
    this.onTap,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);

    final timeStr = _formatTimestamp(importedAt);

    return Dismissible(
      key: ValueKey(id),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) async {
        return await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                backgroundColor: theme.cardSurface,
                title: Text(
                  'Delete Book',
                  style: theme.titleFont.copyWith(fontSize: 18),
                ),
                content: Text(
                  'Remove "$displayName" and all its chunks from the knowledge base?',
                  style: theme.bodyFont.copyWith(
                    color: theme.textPrimary,
                    fontSize: 14,
                  ),
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
            ) ??
            false;
      },
      onDismissed: (_) => onDelete?.call(),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        decoration: BoxDecoration(
          color: theme.danger,
          borderRadius: const BorderRadius.all(Radius.circular(8)),
        ),
        child: Icon(Icons.delete_rounded, color: theme.bgPrimary, size: 28),
      ),
      child: ThemeAwareCard(
        onTap: onTap,
        child: Row(
          children: [
            // Book icon with amber/brown color (book source visual cue).
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: theme.warning.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.menu_book_rounded,
                color: theme.warning,
                size: 24,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayName,
                    style: theme.titleFont.copyWith(fontSize: 15),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$chunkCount chunks · $timeStr',
                    style: theme.bodyFont.copyWith(
                      color: theme.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: theme.textSecondary,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  String _formatTimestamp(int seconds) {
    final dt =
        DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
    final now = DateTime.now();
    final diff = now.difference(dt);

    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.month}/${dt.day}/${dt.year}';
  }
}
