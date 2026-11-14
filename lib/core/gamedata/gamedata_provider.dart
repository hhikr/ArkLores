import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../background/background_work.dart';
import 'game.dart';
import 'gamedata_channel.dart';
import 'gamedata_installer.dart';

final gameDataInstallerProvider = Provider<GameDataInstaller>((ref) {
  return GameDataInstaller();
});

/// What is installed (the file and its manifest), whatever the channel file
/// says. The library's queries wait on this, not on the status, so reading
/// the channel does not run them all again (2026-11-12: opening the
/// knowledge-base page did, and every page below stuttered). Invalidate it
/// when the database is replaced; the status follows.
final gameDataInstalledProvider = FutureProvider<GameDataInstallStatus>(
  (ref) => ref.watch(gameDataInstallerProvider).getStatus(),
);

/// The installation measured against the channel's asset (the knowledge-base
/// page and the update check).
final gameDataInstallStatusProvider =
    FutureProvider<GameDataInstallStatus>((ref) async {
  await ref.watch(gameDataInstalledProvider.future);
  return channelInstaller(ref, Game.arknights, watch: true).getStatus();
});

/// 0.12: the Endfield knowledge base's installer (its own file and asset).
final endfieldInstallerProvider = Provider<GameDataInstaller>((ref) {
  return const GameDataInstaller.forGame(Game.endfield);
});

final endfieldInstalledProvider = FutureProvider<GameDataInstallStatus>(
  (ref) => ref.watch(endfieldInstallerProvider).getStatus(),
);

final endfieldInstallStatusProvider =
    FutureProvider<GameDataInstallStatus>((ref) async {
  await ref.watch(endfieldInstalledProvider.future);
  return channelInstaller(ref, Game.endfield, watch: true).getStatus();
});

/// What of [game] is installed ([gameDataInstalledProvider]).
FutureProvider<GameDataInstallStatus> installedOf(Game game) =>
    game == Game.endfield ? endfieldInstalledProvider : gameDataInstalledProvider;

/// [game]'s installer, pointed at the official asset of the channel file
/// when it has a newer one than this build ([withChannel]). The status
/// [watch]es the channel, so it is worked out again when the file arrives;
/// until then (and without one) it is the asset baked into the build.
GameDataInstaller channelInstaller(Ref ref, Game game, {bool watch = false}) {
  final channel = watch
      ? ref.watch(gameDataChannelProvider)
      : ref.read(gameDataChannelProvider);
  return withChannel(ref.read(installerOf(game)), channel.valueOrNull);
}

/// [game]'s installer.
ProviderListenable<GameDataInstaller> installerOf(Game game) =>
    game == Game.endfield ? endfieldInstallerProvider : gameDataInstallerProvider;

/// [game]'s installation status.
FutureProvider<GameDataInstallStatus> installStatusOf(Game game) =>
    game == Game.endfield
        ? endfieldInstallStatusProvider
        : gameDataInstallStatusProvider;

/// [game]'s download.
StateNotifierProvider<GameDataDownloadNotifier, GameDataDownloadState>
    downloadOf(Game game) => game == Game.endfield
        ? endfieldDownloadProvider
        : gameDataDownloadProvider;

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
    this.phase = GameDataInstallPhase.connecting,
    this.attempt = 1,
  });
  final bool downloading;
  final int received;
  final int? total;

  /// Where a running download is, and the connection attempt it is on.
  final GameDataInstallPhase phase;
  final int attempt;

  /// Raw error of the last failed attempt (the page words it for users).
  final Object? error;
  final GameDataDownloadResult result;
}

/// R14: the download lives here, not in the knowledge-base page, so leaving
/// the page neither loses its progress nor lets a second tap start a
/// parallel download of the same file (two concurrent ~185 MB downloads
/// broke TLS handshakes on a phone).
class GameDataDownloadNotifier extends StateNotifier<GameDataDownloadState> {
  GameDataDownloadNotifier(this._ref, {this.game = Game.arknights})
      : super(const GameDataDownloadState());
  final Ref _ref;

  /// Whose knowledge base this downloads.
  final Game game;

  /// Progress updates are throttled to this many bytes.
  static const int _progressStep = 512 * 1024;

  GameDataDownloadToken? _token;

  /// Stops a running download (e.g. one that waits for a server that does
  /// not answer). The partial file is kept for the next start.
  void cancel() => _token?.cancel();

  /// Starts a download unless one is already running. An installed asset
  /// that is already the one this app points at is not downloaded again
  /// unless [force] (the page asks the user first).
  Future<void> start({bool force = false}) async {
    if (state.downloading) return;
    if (!force) {
      try {
        final status = await channelInstaller(_ref, game).getStatus();
        if (status.installed && !status.updateAvailable) return;
      } catch (_) {
        // Cannot tell: download as before.
      }
    }
    if (state.downloading) return;
    state = const GameDataDownloadState(downloading: true);
    _token = GameDataDownloadToken();
    await BackgroundWork.instance.run(
      BackgroundWork.text(
        game == Game.endfield ? '正在下载终末地知识库' : '正在下载知识库',
        game == Game.endfield
            ? 'Downloading the Endfield knowledge base'
            : 'Downloading the knowledge base',
      ),
      _download,
    );
  }

  Future<void> _download() async {
    var lastReported = 0;
    try {
      final installed =
          await channelInstaller(_ref, game).installFromReleaseAsset(
        overwrite: true,
        cancelToken: _token,
        onPhase: (phase, attempt) {
          if (!mounted) return;
          state = GameDataDownloadState(
            downloading: true,
            received: state.received,
            total: state.total,
            phase: phase,
            attempt: attempt,
          );
        },
        onProgress: (received, total) {
          if (!mounted) return;
          final done = total != null && received >= total;
          // The first report carries the size: show it at once.
          final first = state.total == null && total != null;
          if (received - lastReported < _progressStep &&
              !done &&
              !first &&
              received >= lastReported) {
            return;
          }
          lastReported = received;
          state = GameDataDownloadState(
            downloading: true,
            received: received,
            total: total,
            phase: GameDataInstallPhase.downloading,
            attempt: state.attempt,
          );
        },
      );
      _ref.invalidate(installedOf(game));
      if (!mounted) return;
      state = GameDataDownloadState(
        result: installed
            ? GameDataDownloadResult.installed
            : GameDataDownloadResult.noAssetUrl,
      );
    } on GameDataDownloadCancelled {
      if (!mounted) return;
      state = const GameDataDownloadState();
    } catch (e) {
      if (!mounted) return;
      state = GameDataDownloadState(
        error: e,
        result: GameDataDownloadResult.failed,
      );
    } finally {
      _token = null;
    }
  }
}

final gameDataDownloadProvider =
    StateNotifierProvider<GameDataDownloadNotifier, GameDataDownloadState>(
  GameDataDownloadNotifier.new,
);

final endfieldDownloadProvider =
    StateNotifierProvider<GameDataDownloadNotifier, GameDataDownloadState>(
  (ref) => GameDataDownloadNotifier(ref, game: Game.endfield),
);
