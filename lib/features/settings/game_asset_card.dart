import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/gamedata/game.dart';
import '../../core/gamedata/gamedata_installer.dart';
import '../../core/gamedata/gamedata_provider.dart';
import '../../shared/l10n/l10n.dart';
import '../../shared/providers/theme_provider.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/theme_aware_card.dart';

/// One game's official knowledge base: its state, download / update,
/// progress, errors and the manual-install hint. 0.12: one per game.
class GameAssetCard extends ConsumerStatefulWidget {
  const GameAssetCard({
    super.key,
    required this.game,
    required this.title,
  });

  final Game game;
  final String title;

  /// Keeps the Arknights card's widget keys as they were.
  String get keySuffix => game == Game.arknights ? '' : '-${game.key}';

  @override
  ConsumerState<GameAssetCard> createState() => _GameAssetCardState();
}

class _GameAssetCardState extends ConsumerState<GameAssetCard> {
  // The download runs in its provider so it survives leaving this page and
  // cannot be started twice.
  GameDataDownloadState get _download => ref.watch(downloadOf(widget.game));
  bool get _isDownloadingGameData => _download.downloading;
  int get _gameDataDownloadedBytes => _download.received;
  int? get _gameDataTotalBytes => _download.total;
  String? get _gameDataDownloadError => _download.error == null
      ? null
      : _friendlyGameDataError(_download.error!);

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider);
    // A finished download reports once, even if it ended while the user was
    // on another page and came back.
    ref.listen(downloadOf(widget.game), (previous, next) {
      if (previous?.downloading != true || next.downloading) return;
      final message = switch (next.result) {
        GameDataDownloadResult.installed => context.t.kbInstalled,
        GameDataDownloadResult.noAssetUrl => context.t.kbNoAssetUrl,
        _ => null,
      };
      if (message != null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
      }
    });
    return ref.watch(installStatusOf(widget.game)).when(
          data: (status) => _buildGameDataCard(context, status, theme),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, _) => ThemeAwareCard(
            child: Text(
              context.t.kbStatusError(err.toString()),
              style: theme.bodyFont.copyWith(color: theme.danger, fontSize: 13),
            ),
          ),
        );
  }

  void _downloadGameData() {
    ref.read(downloadOf(widget.game).notifier).start();
  }

  /// "Download again" of an already current knowledge base: asks first.
  Future<void> _redownloadGameData() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(context.t.kbRedownloadTitle),
        content: Text(context.t.kbRedownloadBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: Text(context.t.kbCancel),
          ),
          TextButton(
            key: Key('kb-redownload-confirm${widget.keySuffix}'),
            onPressed: () => Navigator.pop(dialog, true),
            child: Text(context.t.kbRedownloadConfirm),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      unawaited(ref.read(downloadOf(widget.game).notifier).start(force: true));
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
    if (isTransientNetworkError(error)) {
      return context.t.kbErrorNetwork;
    }
    if (text.contains('HTTP 404')) {
      return context.t.kbErrorNotFound;
    }
    if (text.contains('checksum mismatch')) {
      return context.t.kbErrorChecksum;
    }
    return context.t.kbDownloadFailed(text);
  }

  /// The folder the knowledge base lives in (where a hand-downloaded file
  /// goes).
  String _installDir(GameDataInstallStatus status) {
    final path = status.dbPath.replaceAll('\\', '/');
    final cut = path.lastIndexOf('/');
    return cut > 0 ? path.substring(0, cut) : path;
  }

  Widget _buildGameDataCard(
    BuildContext context,
    GameDataInstallStatus status,
    AppThemeTokens theme,
  ) {
    // Installed and not older than the asset this app points at.
    final upToDate = status.installed && !status.updateAvailable;
    final total = _gameDataTotalBytes;
    final progress = total != null && total > 0
        ? (_gameDataDownloadedBytes / total).clamp(0.0, 1.0)
        : null;
    final phase = _download.phase;
    final progressText = _isDownloadingGameData &&
            phase != GameDataInstallPhase.downloading
        ? switch (phase) {
            GameDataInstallPhase.connecting =>
              context.t.kbConnecting(_download.attempt),
            GameDataInstallPhase.verifying => context.t.kbVerifying,
            _ => context.t.kbInstalling,
          }
        : total != null && total > 0
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
                    ? Icons.verified_sharp
                    : Icons.dataset_linked_sharp,
                color: status.installed ? theme.accentPrimary : theme.warning,
                size: 24,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  widget.title,
                  style: theme.titleFont.copyWith(fontSize: 15),
                ),
              ),
              if (upToDate && !_isDownloadingGameData)
                Container(
                  key: Key('kb-status-current${widget.keySuffix}'),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: theme.accentPrimary.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.zero,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_sharp,
                          size: 14, color: theme.accentText,),
                      const SizedBox(width: 3),
                      Text(
                        context.t.kbUpToDate,
                        style: theme.bodyFont.copyWith(
                          color: theme.accentText,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: 36),
            child: Text(
              subtitle.isEmpty ? progressText : '$progressText · $subtitle',
              style: theme.bodyFont.copyWith(
                color: theme.textSecondary,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (upToDate && !_isDownloadingGameData)
                OutlinedButton.icon(
                  key: Key('kb-redownload${widget.keySuffix}'),
                  onPressed: _redownloadGameData,
                  icon: const Icon(Icons.refresh_sharp, size: 18),
                  label: Text(
                    context.t.kbRedownload,
                    style: theme.titleFont.copyWith(fontSize: 13),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: theme.textPrimary,
                    side: BorderSide(color: theme.cardBorder),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.zero,
                    ),
                  ),
                )
              else
                ElevatedButton.icon(
                  key: Key('kb-download-button${widget.keySuffix}'),
                  onPressed: _isDownloadingGameData ? null : _downloadGameData,
                  icon: Icon(
                    _isDownloadingGameData
                        ? Icons.downloading_sharp
                        : Icons.download_sharp,
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
                    foregroundColor: theme.onAccent,
                    disabledBackgroundColor: theme.divider,
                    disabledForegroundColor: theme.textSecondary,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.zero,
                    ),
                  ),
                ),
            ],
          ),
          if (_isDownloadingGameData) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.zero,
              child: LinearProgressIndicator(
                value: progress,
                backgroundColor: theme.divider,
                valueColor: AlwaysStoppedAnimation(theme.accentPrimary),
                minHeight: 6,
              ),
            ),
            if (phase == GameDataInstallPhase.connecting ||
                phase == GameDataInstallPhase.downloading)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  key: Key('kb-cancel-download${widget.keySuffix}'),
                  onPressed: ref.read(downloadOf(widget.game).notifier).cancel,
                  child: Text(
                    context.t.kbCancelDownload,
                    style: theme.bodyFont.copyWith(
                      color: theme.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            if (phase == GameDataInstallPhase.connecting &&
                _download.attempt >= 2)
              Text(
                context.t.kbManualHint(_installDir(status)),
                style: theme.bodyFont.copyWith(
                  color: theme.textSecondary,
                  fontSize: 11.5,
                  height: 1.45,
                ),
              ),
          ],
          if (status.updateAvailable && !_isDownloadingGameData) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.new_releases_sharp,
                    size: 16, color: theme.accentPrimary,),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    context.t.kbUpdateAvailable,
                    style: theme.bodyFont.copyWith(
                      color: theme.accentPrimary,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
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
            if (isTransientNetworkError(_download.error!)) ...[
              const SizedBox(height: 6),
              Text(
                context.t.kbManualHint(_installDir(status)),
                style: theme.bodyFont.copyWith(
                  color: theme.textSecondary,
                  fontSize: 11.5,
                  height: 1.45,
                ),
              ),
            ],
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

}