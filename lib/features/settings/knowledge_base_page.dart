import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/gamedata/gamedata_build_provider.dart';
import '../../core/gamedata/gamedata_installer.dart';
import '../../core/gamedata/gamedata_provider.dart';
import '../../shared/l10n/l10n.dart';
import '../../shared/providers/settings_provider.dart';
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

  final TextEditingController _tokenController = TextEditingController();
  bool _tokenVisible = false;
  bool _tokenLoaded = false;

  @override
  void dispose() {
    _tokenController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider);
    final gameDataStatusAsync = ref.watch(gameDataInstallStatusProvider);

    // Fill the token field once from secure storage (async, outside build).
    ref.listen(githubTokenProvider, (previous, next) {
      final token = next.valueOrNull;
      if (!_tokenLoaded && token != null) {
        _tokenLoaded = true;
        _tokenController.text = token;
      }
    });

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
            context.t.kbStructuredTitle,
            style: theme.titleFont.copyWith(fontSize: 18),
          ),
          const SizedBox(height: 12),
          ThemeAwareCard(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded,
                    color: theme.accentPrimary, size: 22,),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    context.t.kbScopeDescription,
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
            error: (err, _) => _buildErrorCard(
                context.t.kbStatusError(err.toString()), theme,),
          ),
          const SizedBox(height: 16),
          gameDataStatusAsync.when(
            data: (status) => status.installed
                ? _buildManifestGrid(context, status, theme)
                : const SizedBox.shrink(),
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),
          const SizedBox(height: 16),
          _buildSourceBuildCard(context, theme),
        ],
      ),
    );
  }

  Widget _buildSourceBuildCard(
    BuildContext context,
    AppThemeTokens theme,
  ) {
    final build = ref.watch(gameDataBuildProvider);
    return ThemeAwareCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.sync_rounded, color: theme.accentPrimary, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.t.kbBuildSectionTitle,
                      style: theme.titleFont.copyWith(fontSize: 15),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      context.t.kbBuildSectionDesc,
                      style: theme.bodyFont.copyWith(
                        color: theme.textSecondary,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (build.latestCommit != null)
            Text(
              '${context.t.kbBuildLatestCommit}: ${_shortCommit(build.latestCommit)}'
              '${build.installedCommit != null ? ' (${context.t.kbBuildInstalledCommit}: ${_shortCommit(build.installedCommit)})' : ''}',
              style: theme.bodyFont.copyWith(
                color: theme.textSecondary,
                fontSize: 12,
              ),
            ),
          if (build.phase == GameDataBuildPhase.done) ...[
            const SizedBox(height: 8),
            Text(
              build.incremental
                  ? context.t.kbBuildIncrementalDone
                  : context.t.kbBuildFullDone,
              style: theme.bodyFont.copyWith(
                color: theme.accentPrimary,
                fontSize: 12,
              ),
            ),
          ],
          if (build.error != null) ...[
            const SizedBox(height: 8),
            Text(
              '${context.t.kbBuildError}: ${build.error}',
              style: theme.bodyFont.copyWith(
                color: theme.danger,
                fontSize: 12,
              ),
            ),
          ],
          if (build.busy) ...[
            const SizedBox(height: 12),
            Text(
              _buildStageLabel(context, build),
              style: theme.bodyFont.copyWith(
                color: theme.textPrimary,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: build.total > 0
                  ? (build.done / build.total).clamp(0.0, 1.0)
                  : null,
              backgroundColor: theme.divider,
              valueColor: AlwaysStoppedAnimation(theme.accentPrimary),
              minHeight: 6,
            ),
            if (build.total > 0) ...[
              const SizedBox(height: 4),
              Text(
                '${build.done} / ${build.total}',
                style: theme.bodyFont.copyWith(
                  color: theme.textSecondary,
                  fontSize: 11,
                ),
              ),
            ],
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: build.busy
                    ? null
                    : () => ref
                        .read(gameDataBuildProvider.notifier)
                        .checkForUpdates(githubToken: _currentGithubToken()),
                icon: const Icon(Icons.manage_search_rounded, size: 18),
                label: Text(context.t.kbBuildCheckUpdates),
                style: OutlinedButton.styleFrom(
                  foregroundColor: theme.accentPrimary,
                  side: BorderSide(color: theme.divider),
                ),
              ),
              const SizedBox(width: 8),
              if (build.busy)
                OutlinedButton.icon(
                  onPressed: () =>
                      ref.read(gameDataBuildProvider.notifier).cancel(),
                  icon: const Icon(Icons.close_rounded, size: 18),
                  label: Text(context.t.kbBuildCancel),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: theme.danger,
                    side: BorderSide(color: theme.divider),
                  ),
                )
              else
                ElevatedButton.icon(
                  onPressed: () => ref
                      .read(gameDataBuildProvider.notifier)
                      .buildFromSource(githubToken: _currentGithubToken()),
                  icon: const Icon(Icons.build_rounded, size: 18),
                  label: Text(context.t.kbBuildFromSource),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.accentPrimary,
                    foregroundColor: theme.bgPrimary,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          _buildGithubTokenSection(context, theme),
        ],
      ),
    );
  }

  /// Optional GitHub Personal Access Token section: raises the GitHub API
  /// quota from 60 to 5000 requests/hour, avoiding rate-limit failures when
  /// pulling GameData source. Stored in OS secure storage.
  Widget _buildGithubTokenSection(
    BuildContext context,
    AppThemeTokens theme,
  ) {
    final tokenAsync = ref.watch(githubTokenProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Divider(color: theme.divider, height: 1),
        const SizedBox(height: 12),
        Text(
          context.t.kbBuildTokenTitle,
          style: theme.titleFont.copyWith(fontSize: 13),
        ),
        const SizedBox(height: 2),
        Text(
          context.t.kbBuildTokenDesc,
          style: theme.bodyFont.copyWith(
            color: theme.textSecondary,
            fontSize: 11,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _tokenController,
                obscureText: !_tokenVisible,
                style: theme.bodyFont.copyWith(color: theme.textPrimary),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: context.t.kbBuildTokenPlaceholder,
                  hintStyle: theme.bodyFont.copyWith(
                    color: theme.textSecondary,
                    fontSize: 12,
                  ),
                  filled: true,
                  fillColor: theme.bgPrimary,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(color: theme.divider),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(color: theme.divider),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            IconButton(
              onPressed: () => setState(() => _tokenVisible = !_tokenVisible),
              icon: Icon(
                _tokenVisible
                    ? Icons.visibility_off_rounded
                    : Icons.visibility_rounded,
                size: 18,
                color: theme.textSecondary,
              ),
              visualDensity: VisualDensity.compact,
            ),
            const SizedBox(width: 4),
            FilledButton(
              onPressed: _saveGithubToken,
              style: FilledButton.styleFrom(
                backgroundColor: theme.accentPrimary,
                foregroundColor: theme.bgPrimary,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              child: Text(
                context.t.kbBuildTokenSave,
                style: theme.titleFont.copyWith(fontSize: 12),
              ),
            ),
          ],
        ),
        if (tokenAsync.valueOrNull?.isNotEmpty ?? false) ...[
          const SizedBox(height: 4),
          Text(
            context.t.kbBuildTokenSetHint,
            style: theme.bodyFont.copyWith(
              color: theme.accentPrimary,
              fontSize: 11,
            ),
          ),
        ],
      ],
    );
  }

  String? _currentGithubToken() {
    final text = _tokenController.text.trim();
    if (text.isNotEmpty) return text;
    return ref.read(githubTokenProvider).valueOrNull;
  }

  Future<void> _saveGithubToken() async {
    final token = _tokenController.text.trim();
    await ref.read(settingsServiceProvider).saveGithubToken(token);
    ref.invalidate(githubTokenProvider);
    _tokenLoaded = false;
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          token.isEmpty
              ? context.t.kbBuildTokenCleared
              : context.t.kbBuildTokenSaved,
        ),
      ),
    );
  }

  String _buildStageLabel(
    BuildContext context,
    GameDataBuildUiState build,
  ) {
    switch (build.phase) {
      case GameDataBuildPhase.checking:
        return context.t.kbBuildChecking;
      case GameDataBuildPhase.downloading:
        return build.stage == 'zip'
            ? context.t.kbBuildDownloadingZip
            : context.t.kbBuildDownloadingChanges;
      case GameDataBuildPhase.extracting:
        return context.t.kbBuildExtracting;
      case GameDataBuildPhase.swapping:
        return context.t.kbBuildSwapping;
      case GameDataBuildPhase.building:
        switch (build.stage) {
          case 'copy':
            return context.t.kbBuildStageCopy;
          case 'incremental':
            return context.t.kbBuildStageIncremental;
          case 'profiles':
            return context.t.kbBuildStageProfiles;
          case 'voices':
            return context.t.kbBuildStageVoices;
          case 'structured':
            return context.t.kbBuildStageStructured;
          case 'stories':
            return context.t.kbBuildStageStories;
          case 'coverage':
            return context.t.kbBuildStageCoverage;
          case 'coverage_speakers':
            return context.t.kbBuildStageCoverageSpeakers;
          case 'coverage_trie':
            return context.t.kbBuildStageCoverageTrie;
          case 'coverage_scan':
            return context.t.kbBuildStageCoverageScan;
          case 'coverage_rare':
            return context.t.kbBuildStageCoverageRare;
          case 'coverage_profiles':
            return context.t.kbBuildStageCoverageProfiles;
          case 'fts':
            return context.t.kbBuildStageFts;
          case 'start':
            return context.t.kbBuildStageStart;
          default:
            return build.stage;
        }
      case GameDataBuildPhase.idle:
      case GameDataBuildPhase.done:
        return '';
    }
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
              ? context.t.kbInstalled
              : context.t.kbNoAssetUrl,),
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
      return context.t.kbErrorInvalidUrl;
    }
    if (text.contains('Connection timed out') || text.contains('timed out')) {
      return context.t.kbErrorTimeout;
    }
    if (text.contains('HTTP 404')) {
      return context.t.kbErrorNotFound;
    }
    if (text.contains('checksum mismatch')) {
      return context.t.kbErrorChecksum;
    }
    return context.t.kbDownloadFailed(text);
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
                : context.t.kbNotInstalled;
    final subtitle = status.installed
        ? [
            if (status.entityCount != null) 'entities ${status.entityCount}',
            if (status.recordCount != null) 'records ${status.recordCount}',
            if (status.chunkCount != null) 'chunks ${status.chunkCount}',
          ].join(' · ')
        : context.t.kbDevAssetHint;

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
                      context.t.kbStructuredTitle,
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
                      ? context.t.kbDownloading
                      : status.installed
                          ? context.t.kbUpdate
                          : context.t.kbDownload,
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
        _statTile(context, context.t.kbStatEntities, status.entityCount ?? '-',
            Icons.account_tree_rounded, theme,),
        _statTile(context, context.t.kbStatRecords, status.recordCount ?? '-',
            Icons.dataset_rounded, theme,),
        _statTile(context, context.t.kbStatChunks, status.chunkCount ?? '-',
            Icons.article_rounded, theme,),
        _statTile(
          context,
          context.t.kbStatSourceCommit,
          _shortCommit(status.sourceCommit),
          Icons.commit_rounded,
          theme,
        ),
      ],
    );
  }

  Widget _statTile(BuildContext context, String label, String value,
      IconData icon, AppThemeTokens theme,) {
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
