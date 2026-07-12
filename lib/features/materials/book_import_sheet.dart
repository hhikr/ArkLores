import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/providers/theme_provider.dart';
import '../../shared/widgets/theme_aware_card.dart';
import 'book_import_service.dart';

/// Bottom sheet that shows the progress of a book import operation.
class BookImportSheet extends ConsumerWidget {
  final BookImportProgress progress;

  const BookImportSheet({super.key, required this.progress});

  /// Shows the import sheet as a modal bottom sheet.
  static void show(BuildContext context, BookImportProgress progress) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      elevation: 0,
      isDismissible: progress.stage == 'done' || progress.stage == 'error',
      builder: (_) => BookImportSheet(progress: progress),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      child: ThemeAwareCard(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Title row ────────────────────────────────────
            Row(
              children: [
                _buildStageIcon(theme),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _titleText,
                    style: theme.titleFont.copyWith(fontSize: 16),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (_isDone)
                  Icon(Icons.check_circle_rounded,
                      color: theme.accentPrimary, size: 24),
                if (_isError)
                  Icon(Icons.error_rounded,
                      color: theme.danger, size: 24),
              ],
            ),
            const SizedBox(height: 12),

            // ── Progress bar ─────────────────────────────────
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: _isError ? null : progress.fraction,
                backgroundColor: theme.divider,
                valueColor: AlwaysStoppedAnimation(
                  _isError ? theme.danger : theme.accentPrimary,
                ),
                minHeight: 6,
              ),
            ),
            const SizedBox(height: 8),

            // ── Detail text ──────────────────────────────────
            Text(
              _detailText,
              style: theme.bodyFont.copyWith(
                color: theme.textSecondary,
                fontSize: 12,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),

            // ── Error detail ─────────────────────────────────
            if (_isError && progress.error != null) ...[
              const SizedBox(height: 8),
              Text(
                progress.error!,
                style: theme.bodyFont.copyWith(
                  color: theme.danger,
                  fontSize: 12,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ],

            // ── Done / Dismiss button ────────────────────────
            if (_isDone || _isError) ...[
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        _isError ? theme.danger : theme.accentPrimary,
                    foregroundColor: theme.bgPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Text(
                    _isDone ? 'Done' : 'Dismiss',
                    style: theme.titleFont.copyWith(fontSize: 14),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String get _titleText {
    switch (progress.stage) {
      case 'extracting':
        return 'Reading ${progress.fileName}';
      case 'chunking':
        return 'Chunking text...';
      case 'embedding':
        return 'Generating embeddings...';
      case 'storing':
        return 'Saving to knowledge base...';
      case 'done':
        return 'Import complete';
      case 'error':
        return 'Import failed';
      default:
        return 'Importing...';
    }
  }

  String get _detailText {
    if (progress.error != null) return 'Error occurred during import.';
    return progress.detail ?? '';
  }

  bool get _isDone => progress.stage == 'done';
  bool get _isError => progress.stage == 'error';

  Widget _buildStageIcon(AppThemeTokens theme) {
    switch (progress.stage) {
      case 'extracting':
      case 'chunking':
      case 'embedding':
      case 'storing':
        return SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            color: theme.accentPrimary,
          ),
        );
      case 'done':
        return Icon(Icons.check_circle_rounded,
            color: theme.accentPrimary, size: 24);
      case 'error':
        return Icon(Icons.error_rounded, color: theme.danger, size: 24);
      default:
        return Icon(Icons.hourglass_empty_rounded,
            color: theme.textSecondary, size: 24);
    }
  }
}
