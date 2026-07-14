import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/l10n/l10n.dart';
import '../../shared/providers/theme_provider.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/theme_aware_card.dart';
import 'book_import_service.dart';

/// Bottom sheet that shows the progress of a book import operation.
class BookImportSheet extends ConsumerWidget {
  final BookImportProgress progress;

  const BookImportSheet({super.key, required this.progress});

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
            Row(
              children: [
                _buildStageIcon(theme),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _titleText(context),
                    style: theme.titleFont.copyWith(fontSize: 16),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (_isDone)
                  Icon(Icons.check_circle_rounded,
                      color: theme.accentPrimary, size: 24),
                if (_isError)
                  Icon(Icons.error_rounded, color: theme.danger, size: 24),
              ],
            ),
            const SizedBox(height: 12),
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
            Text(
              _isError
                  ? context.t.importErrorOccurred
                  : (progress.detail ?? ''),
              style: theme.bodyFont.copyWith(
                color: theme.textSecondary,
                fontSize: 12,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if (_isError && progress.error != null) ...[
              const SizedBox(height: 8),
              Text(progress.error!,
                  style: theme.bodyFont.copyWith(
                      color: theme.danger, fontSize: 12),
                  maxLines: 3, overflow: TextOverflow.ellipsis),
            ],
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
                        borderRadius: BorderRadius.circular(8)),
                  ),
                  child: Text(
                    _isDone ? context.t.importDismiss : context.t.importDismiss,
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

  String _titleText(BuildContext context) {
    switch (progress.stage) {
      case 'extracting':
        return context.t.importReading(progress.fileName);
      case 'chunking':
        return context.t.importChunking;
      case 'embedding':
        return context.t.importEmbedding;
      case 'storing':
        return context.t.importStoring;
      case 'done':
        return context.t.importDone;
      case 'error':
        return context.t.importFailed;
      default:
        return 'Importing...';
    }
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


