import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/gamedata/game.dart';
import '../../core/gamedata/gamedata_installer.dart';
import '../../core/gamedata/gamedata_provider.dart';
import '../../shared/l10n/l10n.dart';
import '../../shared/providers/theme_provider.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/ef_widgets.dart';
import '../../shared/widgets/theme_aware_card.dart';
import 'kb_common.dart';

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
      if (message != null) showToast(context, message);
    });
    return ref.watch(installStatusOf(widget.game)).when(
          data: (status) => _buildGameDataCard(context, status, theme),
          loading: () => const LoadingView(),
          error: (err, _) => NoticeBox(context.t.kbStatusError(err.toString())),
        );
  }

  void _downloadGameData() {
    ref.read(downloadOf(widget.game).notifier).start();
  }

  /// "Download again" of an already current knowledge base: asks first.
  /// [local]: the installed one was updated on this device, so this goes
  /// back to the official asset.
  Future<void> _redownloadGameData({bool local = false}) async {
    final ok = await confirmAction(
      context,
      title: local ? context.t.kbBackToOfficialTitle : context.t.kbRedownloadTitle,
      message: local ? context.t.kbBackToOfficialBody : context.t.kbRedownloadBody,
      confirm: context.t.kbRedownloadConfirm,
      cancel: context.t.kbCancel,
      confirmKey: Key('kb-redownload-confirm${widget.keySuffix}'),
    );
    if (ok && mounted) {
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
    // What is in it, in the reader's words, and which game data it is.
    final subtitle = status.installed
        ? [
            if (status.storyLineCount != null)
              context.t.kbCountLines(status.storyLineCount!),
            if (status.recordCount != null)
              context.t.kbCountRecords(status.recordCount!),
            if ((status.sourceCommit ?? '').isNotEmpty)
              context.t.kbDataVersion(shortCommit(status.sourceCommit)),
            // Where it came from: an official asset, or an update run here.
            status.builtLocally
                ? context.t.kbOriginLocal
                : context.t.kbOriginOfficial,
          ]
        : [context.t.kbDevAssetHint];
    final local = status.builtLocally && !_isDownloadingGameData;

    return ThemeAwareCard(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          KbCardHeader(
            icon: status.installed
                ? Icons.verified_sharp
                : Icons.dataset_linked_sharp,
            title: widget.title,
            // In effect (current, or updated here): a solid stamp. A missing
            // one is flagged. The rest (a download, an update to take) is
            // said by the button and the line below.
            stamp: _isDownloadingGameData
                ? null
                : upToDate
                    ? StateStamp(
                        local ? context.t.kbLocalBuild : context.t.kbUpToDate,
                        key: Key(
                          '${local ? 'kb-status-local' : 'kb-status-current'}'
                          '${widget.keySuffix}',
                        ),
                      )
                    : !status.installed
                        ? StateStamp(
                            context.t.kbNotInstalled,
                            kind: StampKind.alert,
                          )
                        : null,
          ),
          const SizedBox(height: 10),
          FactsRow([
            if (status.installed || _isDownloadingGameData) progressText,
            for (final s in subtitle)
              // The stamp already says it was updated here.
              if (!(upToDate && local && s == context.t.kbOriginLocal)) s,
          ]),
          if (status.updateAvailable && !_isDownloadingGameData) ...[
            const SizedBox(height: 10),
            kbFlag(
              switch (status.updateReason) {
                GameDataUpdateReason.newerData => context.t.kbUpdateNewerData(
                    shortCommit(status.releaseAssetCommit),
                  ),
                GameDataUpdateReason.sameDataOfficial =>
                  context.t.kbUpdateSameData,
                _ => context.t.kbUpdateAvailable,
              },
              theme,
            ),
          ],
          if (local && upToDate) ...[
            const SizedBox(height: 10),
            kbNote(context.t.kbLocalBuildNote, theme, theme.textSecondary),
          ],
          if (_isDownloadingGameData) ...[
            const SizedBox(height: 14),
            SegmentProgress(value: progress),
            if (phase == GameDataInstallPhase.connecting &&
                _download.attempt >= 2) ...[
              const SizedBox(height: 8),
              kbNote(
                context.t.kbManualHint(widget.game.dbFileName, _installDir(status)),
                theme,
                theme.textSecondary,
              ),
            ],
          ],
          if (_gameDataDownloadError != null) ...[
            const SizedBox(height: 12),
            NoticeBox(
              _gameDataDownloadError!,
              action: isTransientNetworkError(_download.error!)
                  ? kbNote(
                      context.t.kbManualHint(
                        widget.game.dbFileName,
                        _installDir(status),
                      ),
                      theme,
                      theme.textSecondary,
                    )
                  : null,
            ),
          ],
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.end,
            children: [
              if (_isDownloadingGameData &&
                  (phase == GameDataInstallPhase.connecting ||
                      phase == GameDataInstallPhase.downloading))
                AppButton(
                  context.t.kbCancelDownload,
                  key: Key('kb-cancel-download${widget.keySuffix}'),
                  icon: Icons.close_sharp,
                  onPressed: ref.read(downloadOf(widget.game).notifier).cancel,
                ),
              if (upToDate && !_isDownloadingGameData)
                AppButton(
                  local ? context.t.kbBackToOfficial : context.t.kbRedownload,
                  key: Key('kb-redownload${widget.keySuffix}'),
                  icon: Icons.refresh_sharp,
                  onPressed: () => _redownloadGameData(local: local),
                )
              else
                AppButton(
                  _isDownloadingGameData
                      ? context.t.kbDownloading
                      : status.installed
                          ? context.t.kbUpdate
                          : context.t.kbDownload,
                  key: Key('kb-download-button${widget.keySuffix}'),
                  kind: ButtonKind.go,
                  icon: Icons.download_sharp,
                  busy: _isDownloadingGameData,
                  onPressed: _downloadGameData,
                ),
            ],
          ),
          if (status.installed && status.dbPath.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              status.dbPath,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.field(size: 12),
            ),
          ],
        ],
      ),
    );
  }
}
