import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/gamedata/gamedata_installer.dart';
import '../../core/gamedata/gamedata_provider.dart';
import '../../shared/l10n/l10n.dart';
import '../../shared/providers/theme_provider.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/theme_aware_card.dart';

/// Knowledge base management page for the structured Chinese GameData DB.
class KnowledgeBasePage extends ConsumerStatefulWidget {
  const KnowledgeBasePage({super.key});

  @override
  ConsumerState<KnowledgeBasePage> createState() => _KnowledgeBasePageState();
}

class _KnowledgeBasePageState extends ConsumerState<KnowledgeBasePage> {
  bool _isDownloadingGameData = false;
  int _gameDataDownloadedBytes = 0;
  int? _gameDataTotalBytes;
  String? _gameDataDownloadError;

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider);
    final gameDataStatusAsync = ref.watch(gameDataInstallStatusProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
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
          Text(
            'GameData 结构化知识库',
            style: theme.titleFont.copyWith(fontSize: 18),
          ),
          const SizedBox(height: 12),
          ThemeAwareCard(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded,
                    color: theme.accentPrimary, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'v0.4.5 只使用中文 GameData 结构化库：实体、别名、原始记录、剧情行、文档片段和 FTS。旧 Wiki seed 与资料导入索引链路已移除。',
                    style: theme.bodyFont.copyWith(
                      color: theme.textSecondary,
                      fontSize: 13,
                      height: 1.45,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          gameDataStatusAsync.when(
            data: (status) => _buildGameDataCard(context, status, theme),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, _) => _buildErrorCard('GameData 状态读取失败：$err', theme),
          ),
          const SizedBox(height: 16),
          gameDataStatusAsync.when(
            data: (status) => status.installed
                ? _buildManifestGrid(context, status, theme)
                : const SizedBox.shrink(),
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Future<void> _downloadGameData() async {
    setState(() {
      _isDownloadingGameData = true;
      _gameDataDownloadedBytes = 0;
      _gameDataTotalBytes = null;
      _gameDataDownloadError = null;
    });

    try {
      final installer = ref.read(gameDataInstallerProvider);
      final installed = await installer.installFromReleaseAsset(
        overwrite: true,
        onProgress: (received, total) {
          if (!mounted) return;
          setState(() {
            _gameDataDownloadedBytes = received;
            _gameDataTotalBytes = total;
          });
        },
      );
      ref.invalidate(gameDataInstallStatusProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(installed
              ? 'GameData 主知识库已安装'
              : '当前构建未配置 GameData release asset URL'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _gameDataDownloadError = _friendlyGameDataError(e);
      });
    } finally {
      if (mounted) {
        setState(() {
          _isDownloadingGameData = false;
        });
      }
    }
  }

  String _friendlyGameDataError(Object error) {
    final text = '$error';
    if (text.contains('Failed host lookup') || text.contains('errno = 7')) {
      return '无法解析下载地址。真机测试请确认手机能访问该 GitHub / 局域网 URL。';
    }
    if (text.contains('Connection timed out') || text.contains('timed out')) {
      return '连接超时。请切换网络，或确认临时 HTTP 服务和手机在同一网络。';
    }
    if (text.contains('HTTP 404')) {
      return '未找到 GameData DB 文件。未正式发布时请使用预发布 asset 或 --dart-define 指向临时 URL。';
    }
    if (text.contains('checksum mismatch')) {
      return 'GameData DB 校验失败，文件可能损坏或 SHA256 与构建参数不一致。';
    }
    return '下载 GameData 主知识库失败：$text';
  }

  Widget _buildGameDataCard(
    BuildContext context,
    GameDataInstallStatus status,
    AppThemeTokens theme,
  ) {
    final total = _gameDataTotalBytes;
    final progress = total != null && total > 0
        ? (_gameDataDownloadedBytes / total).clamp(0.0, 1.0)
        : null;
    final progressText = total != null && total > 0
        ? '${(_gameDataDownloadedBytes / 1024 / 1024).toStringAsFixed(1)} / ${(total / 1024 / 1024).toStringAsFixed(1)} MB'
        : _gameDataDownloadedBytes > 0
            ? '${(_gameDataDownloadedBytes / 1024 / 1024).toStringAsFixed(1)} MB'
            : status.installed
                ? '${(status.bytes / 1024 / 1024).toStringAsFixed(1)} MB'
                : '未安装';
    final subtitle = status.installed
        ? [
            if (status.entityCount != null) 'entities ${status.entityCount}',
            if (status.recordCount != null) 'records ${status.recordCount}',
            if (status.chunkCount != null) 'chunks ${status.chunkCount}',
          ].join(' · ')
        : '正式发布前可用 --dart-define=ARKLORES_GAMEDATA_DB_URL 指向预发布 asset 或局域网临时 .db.gz。';

    return ThemeAwareCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                status.installed
                    ? Icons.verified_rounded
                    : Icons.dataset_linked_rounded,
                color: status.installed ? theme.accentPrimary : theme.warning,
                size: 24,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'GameData 主知识库',
                      style: theme.titleFont.copyWith(fontSize: 15),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle.isEmpty
                          ? progressText
                          : '$progressText · $subtitle',
                      style: theme.bodyFont.copyWith(
                        color: theme.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: _isDownloadingGameData ? null : _downloadGameData,
                icon: Icon(
                  _isDownloadingGameData
                      ? Icons.downloading_rounded
                      : Icons.download_rounded,
                  size: 18,
                ),
                label: Text(
                  _isDownloadingGameData
                      ? '下载中'
                      : status.installed
                          ? '更新'
                          : '下载',
                  style: theme.titleFont.copyWith(fontSize: 13),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.accentPrimary,
                  foregroundColor: theme.bgPrimary,
                  disabledBackgroundColor: theme.divider,
                  disabledForegroundColor: theme.textSecondary,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
          ),
          if (_isDownloadingGameData) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                backgroundColor: theme.divider,
                valueColor: AlwaysStoppedAnimation(theme.accentPrimary),
                minHeight: 6,
              ),
            ),
          ],
          if (_gameDataDownloadError != null) ...[
            const SizedBox(height: 10),
            Text(
              _gameDataDownloadError!,
              style: theme.bodyFont.copyWith(
                color: theme.danger,
                fontSize: 12,
              ),
            ),
          ],
          if (status.installed && status.dbPath.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              status.dbPath,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.bodyFont.copyWith(
                color: theme.textSecondary.withValues(alpha: 0.7),
                fontSize: 11,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildManifestGrid(
    BuildContext context,
    GameDataInstallStatus status,
    AppThemeTokens theme,
  ) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _statTile(context, '实体', status.entityCount ?? '-',
            Icons.account_tree_rounded, theme),
        _statTile(context, '原始记录', status.recordCount ?? '-',
            Icons.dataset_rounded, theme),
        _statTile(context, '文档片段', status.chunkCount ?? '-',
            Icons.article_rounded, theme),
        _statTile(
          context,
          '来源提交',
          _shortCommit(status.sourceCommit),
          Icons.commit_rounded,
          theme,
        ),
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
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.titleFont.copyWith(fontSize: 24, height: 1.1),
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

  String _shortCommit(String? commit) {
    if (commit == null || commit.isEmpty) return '-';
    if (commit.length <= 7) return commit;
    return commit.substring(0, 7);
  }
}
