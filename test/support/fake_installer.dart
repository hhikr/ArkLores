import 'package:arklores/core/gamedata/gamedata_installer.dart';
import 'package:http/http.dart' as http;

GameDataInstallStatus installStatus({
  required bool installed,
  String? installedSha,
  String? releaseSha,
}) =>
    GameDataInstallStatus(
      installed: installed,
      dbPath: installed ? 'db' : '',
      bytes: installed ? 1 : 0,
      manifest: const {},
      installedAssetSha: installedSha,
      releaseAssetSha: releaseSha,
    );

/// An installer that reports [status] and counts downloads, which succeed.
class FakeInstaller extends GameDataInstaller {
  FakeInstaller(this.status);
  final GameDataInstallStatus status;
  var downloads = 0;

  @override
  Future<GameDataInstallStatus> getStatus() async => status;

  @override
  Future<bool> installFromReleaseAsset({
    http.Client? client,
    void Function(int receivedBytes, int? totalBytes)? onProgress,
    void Function(GameDataInstallPhase phase, int attempt)? onPhase,
    GameDataDownloadToken? cancelToken,
    bool overwrite = false,
    int maxAttempts = 5,
    Duration retryDelay = const Duration(seconds: 3),
    Duration connectTimeout = const Duration(seconds: 90),
    Duration stallTimeout = const Duration(seconds: 60),
  }) async {
    downloads++;
    return true;
  }
}

/// An installer whose server never answers: it reports the second
/// connection attempt and waits until the user cancels.
class SilentInstaller extends FakeInstaller {
  SilentInstaller(super.status);

  @override
  Future<bool> installFromReleaseAsset({
    http.Client? client,
    void Function(int receivedBytes, int? totalBytes)? onProgress,
    void Function(GameDataInstallPhase phase, int attempt)? onPhase,
    GameDataDownloadToken? cancelToken,
    bool overwrite = false,
    int maxAttempts = 5,
    Duration retryDelay = const Duration(seconds: 3),
    Duration connectTimeout = const Duration(seconds: 90),
    Duration stallTimeout = const Duration(seconds: 60),
  }) async {
    onPhase?.call(GameDataInstallPhase.connecting, 2);
    await cancelToken!.whenCancelled;
    throw const GameDataDownloadCancelled();
  }
}
