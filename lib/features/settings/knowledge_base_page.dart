import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/rag/chunker.dart';
import '../../core/rag/embedder_provider.dart';
import '../../core/rag/vector_store.dart';
import '../../core/rag/vector_store_provider.dart';
import '../../core/wiki/wiki_crawler.dart';
import '../../core/wiki/wiki_models.dart';
import '../../shared/providers/settings_provider.dart';
import '../../shared/providers/theme_provider.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/theme_aware_card.dart';

/// Knowledge base management page — shows index status and controls
/// for updating Wiki content in the vector store.
class KnowledgeBasePage extends ConsumerStatefulWidget {
  const KnowledgeBasePage({super.key});

  @override
  ConsumerState<KnowledgeBasePage> createState() => _KnowledgeBasePageState();
}

class _KnowledgeBasePageState extends ConsumerState<KnowledgeBasePage> {
  bool _isIndexing = false;
  String _indexingStatus = '';
  double _indexingProgress = 0.0;
  String? _error;

  // Target categories for wiki indexing.
  static const List<String> _prtsCategories = [
    'Category:干员',
    'Category:剧情',
    'Category:阵营',
    'Category:角色',
  ];

  static const List<String> _endfieldCategories = [
    'Category:角色',
    'Category:剧情',
    'Category:阵营',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider);
    final statsAsync = ref.watch(vectorStoreStatsProvider);
    final config = ref.watch(apiConfigProvider);

    return Scaffold(
      backgroundColor: theme.bgPrimary,
      appBar: AppBar(
        backgroundColor: theme.bgSecondary,
        title: Text(
          'Knowledge Base',
          style: theme.titleFont.copyWith(fontSize: 18),
        ),
        iconTheme: IconThemeData(color: theme.textPrimary),
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Header icon ──────────────────────────────────────
          Center(
            child: Icon(
              Icons.storage_rounded,
              size: 48,
              color: theme.accentPrimary.withValues(alpha: 0.4),
            ),
          ),
          const SizedBox(height: 24),

          // ── Configuration warning ────────────────────────────
          if (!config.isValid)
            ThemeAwareCard(
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded,
                      color: theme.warning, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Please configure your API Key in Settings before '
                      'building the knowledge base.',
                      style: theme.bodyFont.copyWith(
                        color: theme.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (!config.isValid) const SizedBox(height: 20),

          // ── Stats overview ──────────────────────────────────
          Text(
            'Index Overview',
            style: theme.titleFont.copyWith(fontSize: 18),
          ),
          const SizedBox(height: 12),
          statsAsync.when(
            data: (stats) => _buildStatsGrid(stats, theme),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, _) => _buildErrorCard('Failed to load stats: $err', theme),
          ),
          const SizedBox(height: 24),

          // ── Indexing status ─────────────────────────────────
          if (_isIndexing) ...[
            ThemeAwareCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: theme.accentPrimary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _indexingStatus,
                          style: theme.bodyFont.copyWith(fontSize: 14),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: _indexingProgress,
                      backgroundColor: theme.divider,
                      valueColor: AlwaysStoppedAnimation(theme.accentPrimary),
                      minHeight: 6,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // ── Error display ────────────────────────────────────
          if (_error != null) ...[
            _buildErrorCard(_error!, theme),
            const SizedBox(height: 16),
          ],

          // ── PRTS Wiki section ────────────────────────────────
          Text(
            'Wiki Sources',
            style: theme.titleFont.copyWith(fontSize: 18),
          ),
          const SizedBox(height: 12),
          _buildWikiSection(
            theme: theme,
            site: WikiSite.prts,
            icon: Icons.language_rounded,
            disabled: !config.isValid || _isIndexing,
            onUpdate: () => _indexWiki(WikiSite.prts, _prtsCategories),
          ),
          const SizedBox(height: 12),
          _buildWikiSection(
            theme: theme,
            site: WikiSite.endfield,
            icon: Icons.language_rounded,
            disabled: !config.isValid || _isIndexing,
            onUpdate: () => _indexWiki(WikiSite.endfield, _endfieldCategories),
          ),
          const SizedBox(height: 32),

          // ── Engine info ──────────────────────────────────────
          statsAsync.when(
            data: (stats) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 32),
                child: Center(
                  child: Text(
                    'Search engine: pure Dart (fallback)',
                    style: theme.bodyFont.copyWith(
                      color: theme.textSecondary.withValues(alpha: 0.6),
                      fontSize: 12,
                    ),
                  ),
                ),
              );
            },
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  /// Builds the 4-stat grid (total, wiki, book, books count).
  Widget _buildStatsGrid(VectorStoreStats stats, AppThemeTokens theme) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _statTile('Total Chunks', '${stats.totalChunks}', Icons.dashboard_rounded, theme),
        _statTile('Wiki Chunks', '${stats.wikiChunks}', Icons.language_rounded, theme),
        _statTile('Book Chunks', '${stats.bookChunks}', Icons.menu_book_rounded, theme),
        _statTile('Books', '${stats.totalBooks}', Icons.book_rounded, theme),
      ],
    );
  }

  Widget _statTile(String label, String value, IconData icon, AppThemeTokens theme) {
    return SizedBox(
      width: (MediaQuery.of(context).size.width - 56) / 2,
      child: ThemeAwareCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: theme.accentPrimary, size: 20),
            const SizedBox(height: 8),
            Text(
              value,
              style: theme.titleFont.copyWith(fontSize: 28, height: 1.1),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: theme.bodyFont.copyWith(
                color: theme.textSecondary,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Builds a wiki source section card.
  Widget _buildWikiSection({
    required AppThemeTokens theme,
    required WikiSite site,
    required IconData icon,
    required bool disabled,
    required VoidCallback onUpdate,
  }) {
    return ThemeAwareCard(
      child: Row(
        children: [
          Icon(icon, color: theme.accentPrimary, size: 28),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  site.displayName,
                  style: theme.titleFont.copyWith(fontSize: 16),
                ),
                const SizedBox(height: 2),
                Text(
                  site.apiUrl,
                  style: theme.bodyFont.copyWith(
                    color: theme.textSecondary,
                    fontSize: 11,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          ElevatedButton.icon(
            onPressed: disabled ? null : onUpdate,
            icon: const Icon(Icons.sync_rounded, size: 18),
            label: Text(
              _isIndexing ? 'Indexing...' : 'Update',
              style: theme.titleFont.copyWith(fontSize: 13),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: theme.accentPrimary,
              foregroundColor: theme.bgPrimary,
              disabledBackgroundColor: theme.divider,
              disabledForegroundColor: theme.textSecondary,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorCard(String message, AppThemeTokens theme) {
    return ThemeAwareCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, color: theme.danger, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: theme.bodyFont.copyWith(
                color: theme.textPrimary,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Runs the full indexing pipeline: crawl → chunk → embed → store.
  Future<void> _indexWiki(WikiSite site, List<String> categories) async {
    if (_isIndexing) return;

    setState(() {
      _isIndexing = true;
      _indexingProgress = 0.0;
      _indexingStatus = 'Starting crawl of ${site.displayName}...';
      _error = null;
    });

    try {
      final crawler = MediaWikiCrawler();
      final chunker = const Chunker();
      final vectorStore = ref.read(vectorStoreProvider);
      final embedder = ref.read(embedderProvider);

      var totalPages = 0;
      var processedPages = 0;
      var totalChunks = 0;

      for (var ci = 0; ci < categories.length; ci++) {
        final category = categories[ci];

        setState(() {
          _indexingStatus =
              'Crawling ${site.displayName}: $category (${ci + 1}/${categories.length})';
          _indexingProgress = ci / categories.length;
        });

        // Crawl
        final pages = await crawler.crawlCategory(
          site: site,
          categoryName: category,
          onProgress: (progress) {
            setState(() {
              _indexingStatus =
                  'Crawling ${site.displayName}: ${progress.pagesFetched} pages...';
            });
          },
        );

        if (pages.isEmpty) continue;
        totalPages += pages.length;

        // Chunk each page
        for (final page in pages) {
          final chunks = chunker.chunkByHeadings(
            page.content,
            pageTitle: page.title,
          );

          if (chunks.isEmpty) continue;

          // Embed chunks
          setState(() {
            _indexingStatus =
                'Embedding ${page.title} (${chunks.length} chunks)...';
          });

          final texts = chunks.map((c) => c.content).toList();
          final result = await embedder.embedBatch(texts);

          if (result.vectors.isNotEmpty) {
            await vectorStore.insertChunks(
              chunks,
              result.vectors,
              sourceType: 'wiki',
              sourceUrl:
                  '${site == WikiSite.prts ? 'https://prts.wiki' : 'https://wiki.endfield.moe'}/w/${page.title}',
              wiki: site.key,
            );
            totalChunks += result.vectors.length;
          }

          processedPages++;
          setState(() {
            _indexingProgress =
                (ci + (processedPages / (totalPages > 0 ? totalPages : pages.length)) / categories.length)
                    .clamp(0.0, 1.0);
          });
        }
      }

      // Refresh stats.
      ref.invalidate(vectorStoreStatsProvider);

      setState(() {
        _isIndexing = false;
        _indexingProgress = 1.0;
        _indexingStatus =
            'Completed: $totalChunks chunks from $totalPages pages across ${categories.length} categories.';
      });

      // Clear status after 5 seconds.
      Future.delayed(const Duration(seconds: 5), () {
        if (mounted) {
          setState(() {
            _indexingStatus = '';
            _indexingProgress = 0.0;
          });
        }
      });
    } catch (e) {
      setState(() {
        _isIndexing = false;
        _error = 'Indexing failed: $e';
        _indexingStatus = '';
      });

      // Clear error after 8 seconds.
      Future.delayed(const Duration(seconds: 8), () {
        if (mounted) setState(() => _error = null);
      });
    }
  }
}
