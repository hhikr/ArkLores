import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/rag/vector_store.dart';
import '../../core/rag/vector_store_provider.dart';
import '../../core/rag/wiki_indexing_provider.dart';
import '../../core/wiki/wiki_models.dart';
import '../../shared/l10n/l10n.dart';
import '../../shared/providers/settings_provider.dart';
import '../../shared/providers/theme_provider.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/theme_aware_card.dart';

/// Knowledge base management page.
class KnowledgeBasePage extends ConsumerWidget {
  const KnowledgeBasePage({super.key});

  static const List<String> _prtsCategories = [
    'Category:干员',
    'Category:剧情',
    'Category:阵营',
    'Category:角色',
    'Category:干员密录',
  ];

  static const List<String> _endfieldCategories = [
    'Category:角色',
    'Category:剧情',
    'Category:阵营',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    final statsAsync = ref.watch(vectorStoreStatsProvider);
    final embeddingSettings = ref.watch(embeddingSettingsProvider);
    final activeProfile = embeddingSettings.activeProfile;
    final canEmbed = embeddingSettings.canEmbed;
    final indexingState = ref.watch(wikiIndexingProvider);

    // Translate the enum status into a readable string
    String statusText = '';
    switch (indexingState.status) {
      case WikiIndexingStatus.starting:
        statusText =
            context.t.kbStartingCrawl(indexingState.currentSiteName ?? '');
        break;
      case WikiIndexingStatus.fetchingTitles:
        statusText = '正在拉取维基页面目录...';
        break;
      case WikiIndexingStatus.fetchingTouched:
        statusText = '正在检查更新时间戳...';
        break;
      case WikiIndexingStatus.cleaningUp:
        statusText = '正在清理本地已废弃的数据...';
        break;
      case WikiIndexingStatus.embedding:
        statusText =
            '正在生成向量：${indexingState.currentItemTitle} (${indexingState.processedCount}/${indexingState.totalCount}，跳过 ${indexingState.skippedCount} 页)';
        break;
      case WikiIndexingStatus.retryingFailed:
        statusText =
            '正在重试失败向量：已处理 ${indexingState.processedCount}/${indexingState.totalCount}';
        break;
      case WikiIndexingStatus.completed:
        statusText = '更新完成！';
        break;
      case WikiIndexingStatus.failed:
        statusText = '更新失败：${indexingState.error}';
        break;
      case WikiIndexingStatus.idle:
        statusText = '';
        break;
    }

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

          if (!canEmbed)
            ThemeAwareCard(
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded,
                      color: theme.warning, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '当前 embedding profile 不可用。请在 API Settings 中配置可用的 Embedding API，或切换到内置模型。',
                      style: theme.bodyFont.copyWith(
                        color: theme.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (!canEmbed) const SizedBox(height: 20),

          ThemeAwareCard(
            child: Row(
              children: [
                Icon(Icons.hub_rounded, color: theme.accentPrimary, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        activeProfile?.displayName ??
                            'No active embedding profile',
                        style: theme.titleFont.copyWith(fontSize: 15),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        activeProfile == null
                            ? '请先创建 embedding profile'
                            : 'Active profile · ${activeProfile.backend.name} · ${activeProfile.dimension > 0 ? '${activeProfile.dimension}d' : 'dimension pending'}',
                        style: theme.bodyFont.copyWith(
                          color: theme.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          Text(
            context.t.kbIndexOverview,
            style: theme.titleFont.copyWith(fontSize: 18),
          ),
          const SizedBox(height: 12),
          statsAsync.when(
            data: (stats) => _buildStatsGrid(context, stats, theme),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, _) =>
                _buildErrorCard('${context.t.materialsLoadFailed} $err', theme),
          ),
          const SizedBox(height: 24),

          // Failed chunks alert block (Q3 retry)
          statsAsync.when(
            data: (stats) {
              if (stats.failedChunks > 0) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 24),
                  child: ThemeAwareCard(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Icon(Icons.error_outline_rounded,
                            color: theme.danger, size: 28),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '发现 ${stats.failedChunks} 个条目 Embedding 失败',
                                style: theme.bodyFont.copyWith(
                                  color: theme.textPrimary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '可能由于 Token 超限或网络接口波动导致。这些条目暂以零向量存储，无法被 AI 检索。您可以点击重试重新获取其向量。',
                                style: theme.bodyFont.copyWith(
                                  color: theme.textSecondary,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton(
                          onPressed: indexingState.isIndexing
                              ? null
                              : () => ref
                                  .read(wikiIndexingProvider.notifier)
                                  .retryFailedEmbeddings(),
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                                theme.danger.withValues(alpha: 0.15),
                            foregroundColor: theme.danger,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 10),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: Text(
                            '立即重试',
                            style: theme.titleFont.copyWith(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }
              return const SizedBox.shrink();
            },
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),

          // Common indexing progress panel
          if (indexingState.isIndexing ||
              indexingState.status == WikiIndexingStatus.completed ||
              indexingState.status == WikiIndexingStatus.failed) ...[
            ThemeAwareCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (indexingState.isIndexing)
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: theme.accentPrimary,
                          ),
                        )
                      else
                        Icon(
                          indexingState.status == WikiIndexingStatus.completed
                              ? Icons.check_circle_outline_rounded
                              : Icons.error_outline_rounded,
                          color: indexingState.status ==
                                  WikiIndexingStatus.completed
                              ? theme.accentPrimary
                              : theme.danger,
                          size: 20,
                        ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          statusText,
                          style: theme.bodyFont.copyWith(fontSize: 14),
                        ),
                      ),
                      if (indexingState.status ==
                              WikiIndexingStatus.completed ||
                          indexingState.status == WikiIndexingStatus.failed)
                        IconButton(
                          icon: const Icon(Icons.close_rounded, size: 18),
                          onPressed: () =>
                              ref.read(wikiIndexingProvider.notifier).reset(),
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                        ),
                    ],
                  ),
                  if (indexingState.isIndexing) ...[
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: indexingState.progress,
                        backgroundColor: theme.divider,
                        valueColor: AlwaysStoppedAnimation(theme.accentPrimary),
                        minHeight: 6,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          Text(
            context.t.kbWikiSources,
            style: theme.titleFont.copyWith(fontSize: 18),
          ),
          const SizedBox(height: 12),
          _buildWikiSection(
            context: context,
            ref: ref,
            theme: theme,
            site: WikiSite.prts,
            icon: Icons.language_rounded,
            disabled: !canEmbed || indexingState.isIndexing,
            onUpdate: () => ref
                .read(wikiIndexingProvider.notifier)
                .indexWiki(WikiSite.prts, _prtsCategories),
          ),
          const SizedBox(height: 12),
          _buildWikiSection(
            context: context,
            ref: ref,
            theme: theme,
            site: WikiSite.endfield,
            icon: Icons.language_rounded,
            disabled: !canEmbed || indexingState.isIndexing,
            onUpdate: () => ref
                .read(wikiIndexingProvider.notifier)
                .indexWiki(WikiSite.endfield, _endfieldCategories),
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

  Widget _buildStatsGrid(
      BuildContext context, VectorStoreStats stats, AppThemeTokens theme) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _statTile(context, context.t.kbTotalChunks, '${stats.totalChunks}',
            Icons.dashboard_rounded, theme),
        _statTile(context, context.t.kbWikiChunks, '${stats.wikiChunks}',
            Icons.language_rounded, theme),
        _statTile(context, context.t.kbBookChunks, '${stats.bookChunks}',
            Icons.menu_book_rounded, theme),
        _statTile(context, context.t.kbBooks, '${stats.totalBooks}',
            Icons.book_rounded, theme),
      ],
    );
  }

  Widget _statTile(BuildContext context, String label, String value,
      IconData icon, AppThemeTokens theme) {
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
                style: theme.bodyFont
                    .copyWith(color: theme.textSecondary, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _buildWikiSection({
    required BuildContext context,
    required WidgetRef ref,
    required AppThemeTokens theme,
    required WikiSite site,
    required IconData icon,
    required bool disabled,
    required VoidCallback onUpdate,
  }) {
    final indexingState = ref.watch(wikiIndexingProvider);
    final isCurrentIndexing = indexingState.isIndexing &&
        indexingState.currentSiteName == site.displayName;

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
                    style: theme.bodyFont
                        .copyWith(color: theme.textSecondary, fontSize: 11),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          const SizedBox(width: 12),
          ElevatedButton.icon(
            onPressed: disabled ? null : onUpdate,
            icon: Icon(
                isCurrentIndexing
                    ? Icons.hourglass_empty_rounded
                    : Icons.sync_rounded,
                size: 18),
            label: Text(
              isCurrentIndexing ? context.t.kbIndexing : context.t.kbUpdate,
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
                style: theme.bodyFont
                    .copyWith(color: theme.textPrimary, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}
