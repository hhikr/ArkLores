import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/llm/llm_client.dart';
import '../../core/rag/embedder_provider.dart';
import '../../core/rag/vector_store_provider.dart';
import '../../shared/providers/settings_provider.dart';
import '../../shared/providers/theme_provider.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/theme_aware_card.dart';
import 'book_import_service.dart';
import 'book_import_sheet.dart';
import 'book_list_item.dart';

/// Provider for the [BookImportService].
final bookImportServiceProvider = Provider<BookImportService>((ref) {
  final vectorStore = ref.watch(vectorStoreProvider);
  final embedder = ref.watch(embedderProvider);
  return BookImportService(vectorStore: vectorStore, embedder: embedder);
});

/// Materials tab — book list, PDF/TXT import, display name edit, delete.
class MaterialsPage extends ConsumerWidget {
  const MaterialsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    final config = ref.watch(apiConfigProvider);
    final booksAsync = ref.watch(_booksProvider);

    return Scaffold(
      backgroundColor: theme.bgPrimary,
      body: Column(
        children: [
          // ── Header ──────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 48, 16, 12),
            child: Row(
              children: [
                Icon(Icons.menu_book_rounded,
                    color: theme.warning, size: 28),
                const SizedBox(width: 10),
                Text(
                  'Materials',
                  style: theme.titleFont.copyWith(fontSize: 22),
                ),
              ],
            ),
          ),

          // ── Warning banner ──────────────────────────────────
          ThemeAwareCard(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.warning_amber_rounded,
                    color: theme.warning, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '⚠️ 资料内容属用户导入，可能包含非官方解读、翻译误差或个人总结。'
                    'AI 将小心引用并以 Wiki 内容为优先参考。',
                    style: theme.bodyFont.copyWith(
                      color: theme.textSecondary,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // ── Book list or empty state ───────────────────────
          Expanded(
            child: booksAsync.when(
              data: (books) {
                if (books.isEmpty) {
                  return _buildEmptyState(context, theme, config);
                }
                return _buildBookList(context, ref, books, config, theme);
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => Center(
                child: Text(
                  'Failed to load books: $err',
                  style: theme.bodyFont.copyWith(color: theme.danger),
                ),
              ),
            ),
          ),

          // ── Import FAB ───────────────────────────────────────
          if (config.isValid)
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => _importBooks(context, ref),
                    icon: const Icon(Icons.add_rounded, size: 20),
                    label: Text(
                      'Import Books',
                      style: theme.titleFont.copyWith(fontSize: 15),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.accentPrimary,
                      foregroundColor: theme.bgPrimary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(
      BuildContext context, AppThemeTokens theme, LLMConfig config) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.menu_book_rounded,
              size: 64,
              color: theme.accentPrimary.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            Text(
              'No books yet',
              style: theme.titleFont.copyWith(fontSize: 20),
            ),
            const SizedBox(height: 8),
            Text(
              'Import PDF or TXT files to build your\npersonal lore reference library.',
              textAlign: TextAlign.center,
              style: theme.bodyFont.copyWith(
                color: theme.textSecondary,
                fontSize: 14,
                height: 1.4,
              ),
            ),
            if (!config.isValid) ...[
              const SizedBox(height: 24),
              Text(
                'Configure your API Key in Settings to enable import.',
                textAlign: TextAlign.center,
                style: theme.bodyFont.copyWith(
                  color: theme.warning,
                  fontSize: 13,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBookList(
    BuildContext context,
    WidgetRef ref,
    List<Map<String, dynamic>> books,
    LLMConfig config,
    AppThemeTokens theme,
  ) {
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(_booksProvider);
      },
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: books.length,
        itemBuilder: (context, index) {
          final book = books[index];
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: BookListItem(
              id: book['id'] as String,
              fileName: book['file_name'] as String,
              displayName: (book['display_name'] as String?) ??
                  book['file_name'] as String,
              chunkCount: (book['chunk_count'] as int?) ?? 0,
              importedAt: (book['imported_at'] as int?) ?? 0,
              onTap: () => _editDisplayName(context, ref, book),
              onDelete: () => _deleteBook(context, ref, book),
            ),
          );
        },
      ),
    );
  }

  Future<void> _importBooks(BuildContext context, WidgetRef ref) async {
    final theme = ref.read(themeProvider);
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'txt'],
      allowMultiple: true,
    );

    if (result == null || result.files.isEmpty) return;

    final service = ref.read(bookImportServiceProvider);

    // Show initial progress sheet.
    BookImportSheet.show(
      context,
      BookImportProgress(fileName: result.files.first.name),
    );

    try {
      for (final file in result.files) {
        // Update the sheet for each file.
        if (context.mounted) {
          Navigator.of(context).pop(); // Dismiss previous.
          BookImportSheet.show(
            context,
            BookImportProgress(fileName: file.name),
          );
        }

        await service.importFile(
          file,
          onProgress: (progress) {
            // Update bottom sheet with progress.
            if (context.mounted) {
              Navigator.of(context).pop(); // Dismiss previous.
              BookImportSheet.show(context, progress);
            }
          },
        );

        if (context.mounted) {
          Navigator.of(context).pop(); // Dismiss done sheet.
        }
      }

      // Refresh book list.
      ref.invalidate(_booksProvider);
      ref.invalidate(vectorStoreStatsProvider);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Import failed: $e'),
            backgroundColor: theme.danger,
          ),
        );
      }
    }
  }

  Future<void> _editDisplayName(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic> book,
  ) async {
    final theme = ref.read(themeProvider);
    final controller = TextEditingController(
      text: (book['display_name'] as String?) ?? book['file_name'] as String,
    );

    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: theme.cardSurface,
        title: Text(
          'Edit Display Name',
          style: theme.titleFont.copyWith(fontSize: 18),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: theme.bodyFont.copyWith(color: theme.textPrimary),
          decoration: InputDecoration(
            hintText: 'Enter a display name',
            hintStyle: TextStyle(color: theme.textSecondary),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: theme.divider),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: theme.accentPrimary),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Cancel',
                style: theme.bodyFont.copyWith(color: theme.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: Text('Save',
                style: theme.bodyFont.copyWith(color: theme.accentPrimary)),
          ),
        ],
      ),
    );

    if (newName != null && newName.isNotEmpty) {
      final store = ref.read(vectorStoreProvider);
      await store.updateBookDisplayName(book['id'] as String, newName);
      ref.invalidate(_booksProvider);
    }
  }

  Future<void> _deleteBook(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic> book,
  ) async {
    final store = ref.read(vectorStoreProvider);
    await store.deleteBook(book['id'] as String);
    ref.invalidate(_booksProvider);
    ref.invalidate(vectorStoreStatsProvider);
  }
}

/// Internal provider that fetches the book list.
final _booksProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final store = ref.watch(vectorStoreProvider);
  return await store.getBooks();
});
