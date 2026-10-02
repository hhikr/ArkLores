import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'gamedata_installer.dart';

final gameDataInstallerProvider = Provider<GameDataInstaller>((ref) {
  return GameDataInstaller();
});

final gameDataInstallStatusProvider =
    FutureProvider<GameDataInstallStatus>((ref) async {
  return ref.read(gameDataInstallerProvider).getStatus();
});

/// Outcome of the last finished download.
enum GameDataDownloadResult { none, installed, noAssetUrl, failed }

/// State of the official knowledge-base download.
class GameDataDownloadState {
  const GameDataDownloadState({
    this.downloading = false,
    this.received = 0,
    this.total,
    this.error,
    this.result = GameDataDownloadResult.none,
  });
  final bool downloading;
  final int received;
  final int? total;

  /// Raw error of the last failed attempt (the page words it for users).
  final Object? error;
  final GameDataDownloadResult result;
}

/// R14: the download lives here, not in the knowledge-base page, so leaving
/// the page neither loses its progress nor lets a second tap start a
/// parallel download of the same file (two concurrent ~185 MB downloads
/// broke TLS handshakes on a phone).
class GameDataDownloadNotifier extends StateNotifier<GameDataDownloadState> {
  GameDataDownloadNotifier(this._ref) : super(const GameDataDownloadState());
  final Ref _ref;

  /// Progress updates are throttled to this many bytes.
  static const int _progressStep = 512 * 1024;

  /// Starts a download unless one is already running.
  Future<void> start() async {
    if (state.downloading) return;
    state = const GameDataDownloadState(downloading: true);
    var lastReported = 0;
    try {
      final installed =
          await _ref.read(gameDataInstallerProvider).installFromReleaseAsset(
        overwrite: true,
        onProgress: (received, total) {
          if (!mounted) return;
          final done = total != null && received >= total;
          if (received - lastReported < _progressStep &&
              !done &&
              received >= lastReported) {
            return;
          }
          lastReported = received;
          state = GameDataDownloadState(
            downloading: true,
            received: received,
            total: total,
          );
        },
      );
      _ref.invalidate(gameDataInstallStatusProvider);
      if (!mounted) return;
      state = GameDataDownloadState(
        result: installed
            ? GameDataDownloadResult.installed
            : GameDataDownloadResult.noAssetUrl,
      );
    } catch (e) {
      if (!mounted) return;
      state = GameDataDownloadState(
        error: e,
        result: GameDataDownloadResult.failed,
      );
    }
  }
}

final gameDataDownloadProvider =
    StateNotifierProvider<GameDataDownloadNotifier, GameDataDownloadState>(
  GameDataDownloadNotifier.new,
);
