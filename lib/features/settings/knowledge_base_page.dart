import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/rag/chunker.dart';
import '../../core/rag/embedder_provider.dart';
import '../../core/rag/vector_store.dart';
import '../../core/rag/vector_store_provider.dart';
import '../../core/wiki/wiki_crawler.dart';
import '../../core/wiki/wiki_models.dart';
import '../../shared/l10n/l10n.dart';
import '../../shared/providers/settings_provider.dart';
import '../../shared/providers/theme_provider.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/theme_aware_card.dart';

/// Knowledge base management page.
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
          context.t.kbTitle,
          style: theme.titleFont.copyWith(fontSize: 18),
        ),
        iconTheme: IconThemeData(color: theme.textPrimary),
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: Icon(
              Icons.storage_rounded,
              size: 48,
              color: theme.accentPrimary.withValues(alpha: 0.4),
            ),
          ),
          const SizedBox(height: 24),

          if (!config.isValid)
            ThemeAwareCard(
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded,
                      color: theme.warning, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      context.t.kbConfigWarning,
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

          Text(
            context.t.kbIndexOverview,
            style: theme.titleFont.copyWith(fontSize: 18),
          ),
          const SizedBox(height: 12),
          statsAsync.when(
            data: (stats) => _buildStatsGrid(stats, theme),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, _) => _buildErrorCard(
              '${context.t.materialsLoadFailed} $err', theme),
          ),
          const SizedBox(height: 24),

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

          if (_error != null) ...[
            _buildErrorCard(_error!, theme),
            const SizedBox(height: 16),
          ],

          Text(
            context.t.kbWikiSources,
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

          statsAsync.when(
            data: (stats) {
              final engineText = stats.useVectorExtension
                  ? context.t.kbEngineNative
                  : context.t.kbEngineFallback;
              final engineColor = stats.useVectorExtension
                  ? theme.textSecondary.withValues(alpha: 0.6)
                  : theme.warning.withValues(alpha: 0.8);
              return Padding(
                padding: const EdgeInsets.only(bottom: 32),
                child: Center(
                  child: Text(
                    engineText,
                    style: theme.bodyFont.copyWith(
                      color: engineColor,
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

  Widget _buildStatsGrid(VectorStoreStats stats, AppThemeTokens theme) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _statTile(context.t.kbTotalChunks, '${stats.totalChunks}',
            Icons.dashboard_rounded, theme),
        _statTile(context.t.kbWikiChunks, '${stats.wikiChunks}',
            Icons.language_rounded, theme),
        _statTile(context.t.kbBookChunks, '${stats.bookChunks}',
            Icons.menu_book_rounded, theme),
        _statTile(context.t.kbBooks, '${stats.totalBooks}',
            Icons.book_rounded, theme),
      ],
    );
  }

  Widget _statTile(
      String label, String value, IconData icon, AppThemeTokens theme) {
    return SizedBox(
      width: (MediaQuery.of(context).size.width - 56) / 2,
      child: ThemeAwareCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: theme.accentPrimary, size: 20),
            const SizedBox(height: 8),
            Text(value,
                style: theme.titleFont.copyWith(fontSize: 28, height: 1.1)),
            const SizedBox(height: 2),
            Text(label,
                style: theme.bodyFont.copyWith(
                    color: theme.textSecondary, fontSize: 12)),
          ],
        ),
      ),
    );
  }

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
                Text(site.displayName,
                    style: theme.titleFont.copyWith(fontSize: 16)),
                const SizedBox(height: 2),
                Text(site.apiUrl,
                    style: theme.bodyFont.copyWith(
                        color: theme.textSecondary, fontSize: 11),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          const SizedBox(width: 12),
          ElevatedButton.icon(
            onPressed: disabled ? null : onUpdate,
            icon: const Icon(Icons.sync_rounded, size: 18),
            label: Text(
              _isIndexing ? context.t.kbIndexing : context.t.kbUpdate,
              style: theme.titleFont.copyWith(fontSize: 13),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: theme.accentPrimary,
              foregroundColor: theme.bgPrimary,
              disabledBackgroundColor: theme.divider,
              disabledForegroundColor: theme.textSecondary,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
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
            child: Text(message,
                style: theme.bodyFont.copyWith(
                    color: theme.textPrimary, fontSize: 13)),
          ),
        ],
      ),
    );
  }

  Future<void> _indexWiki(WikiSite site, List<String> categories) async {
    if (_isIndexing) return;

    setState(() {
      _isIndexing = true;
      _indexingProgress = 0.0;
      _indexingStatus = context.t.kbStartingCrawl(site.displayName);
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
              context.t.kbCrawlingPages(0, site.displayName);
          _indexingProgress = ci / categories.length;
        });

        final pages = await crawler.crawlCategory(
          site: site,
          categoryName: category,
          onProgress: (progress) {
            setState(() {
              _indexingStatus =
                  context.t.kbCrawlingPages(progress.pagesFetched, site.displayName);
            });
          },
        );

        if (pages.isEmpty) continue;
        totalPages += pages.length;

        for (final page in pages) {
          final chunks = chunker.chunkByHeadings(
            page.content,
            pageTitle: page.title,
          );

          if (chunks.isEmpty) continue;

          setState(() {
            _indexingStatus = context.t.kbEmbedding(chunks.length, page.title);
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

      ref.invalidate(vectorStoreStatsProvider);

      setState(() {
        _isIndexing = false;
        _indexingProgress = 1.0;
        _indexingStatus =
            context.t.kbCompleted(totalChunks, totalPages);
      });

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
        _error = context.t.kbFailed(e.toString());
        _indexingStatus = '';
      });

      Future.delayed(const Duration(seconds: 8), () {
        if (mounted) setState(() => _error = null);
      });
    }
  }
}
