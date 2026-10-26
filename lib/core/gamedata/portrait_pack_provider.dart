import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../background/background_work.dart';
import 'gamedata_channel.dart';
import 'gamedata_provider.dart';
import 'portrait_pack.dart';
import 'portrait_pack_installer.dart';
import 'resumable_download.dart';

final portraitPackInstallerProvider = Provider<PortraitPackInstaller>(
  (ref) => PortraitPackInstaller(
      installDirectory: ref.watch(gameDataInstallerProvider).installDirectory,),
);

final portraitPackProvider = FutureProvider<PortraitPack>((ref) async {
  final pack =
      PortraitPack(await ref.watch(portraitPackInstallerProvider).path);
  ref.onDispose(() => unawaited(pack.close()));
  return pack;
});

final _installedStatusProvider =
    FutureProvider<PortraitPackStatus>((ref) async {
  await ref.watch(portraitPackProvider.future);
  final offered = ref.watch(gameDataChannelProvider).valueOrNull?.portraits;
  final asset = offered?.usableBy(appBuildNumber) == true ? offered : null;
  return ref.watch(portraitPackInstallerProvider).status(asset: asset);
});

final portraitPackStatusProvider =
    FutureProvider<PortraitPackStatus>((ref) async {
  final progress = ref.watch(portraitPackDownloadProvider);
  final status = await ref.watch(_installedStatusProvider.future);
  final asset = status.asset;
  return PortraitPackStatus(
    installed: status.installed,
    bytes: status.bytes,
    spriteCount: status.spriteCount,
    kbCommit: status.kbCommit,
    installedSha: status.installedSha,
    asset: asset,
    downloading: progress.downloading,
    received: progress.received,
    total: progress.total,
    error: progress.error,
  );
});

final portraitPackDownloadProvider =
    StateNotifierProvider<PortraitPackDownloadNotifier, PortraitPackStatus>(
  PortraitPackDownloadNotifier.new,
);

class PortraitPackDownloadNotifier extends StateNotifier<PortraitPackStatus> {
  PortraitPackDownloadNotifier(this.ref) : super(const PortraitPackStatus());
  final Ref ref;
  GameDataDownloadToken? _token;
  bool _busy = false;
  void cancel() => _token?.cancel();

  Future<void> start(String label) async {
    if (_busy) return;
    final asset = ref.read(gameDataChannelProvider).valueOrNull?.portraits;
    if (asset == null || !asset.usableBy(appBuildNumber)) return;
    _busy = true;
    _token = GameDataDownloadToken();
    state = const PortraitPackStatus(downloading: true);
    try {
      await BackgroundWork.instance.run(label, () async {
        final pack = await ref.read(portraitPackProvider.future);
        var last = -512 * 1024;
        await ref.read(portraitPackInstallerProvider).install(
          asset,
          pack: pack,
          cancelToken: _token,
          onProgress: (received, total) {
            if (!mounted || (received - last < 512 * 1024 && received != total)) {
              return;
            }
            last = received;
            state = PortraitPackStatus(
                downloading: true, received: received, total: total,);
          },
        );
      });
      ref.invalidate(portraitPackProvider);
      if (mounted) state = const PortraitPackStatus();
    } on GameDataDownloadCancelled {
      if (mounted) state = const PortraitPackStatus();
    } catch (e) {
      if (mounted) state = PortraitPackStatus(error: e);
    } finally {
      _token = null;
      _busy = false;
      ref.invalidate(portraitPackStatusProvider);
    }
  }

  Future<void> delete() async {
    if (_busy) return;
    _busy = true;
    try {
      final pack = await ref.read(portraitPackProvider.future);
      await ref.read(portraitPackInstallerProvider).delete(pack);
      ref.invalidate(portraitPackProvider);
      ref.invalidate(portraitPackStatusProvider);
      if (mounted) state = const PortraitPackStatus();
    } catch (e) {
      if (mounted) state = PortraitPackStatus(error: e);
    } finally {
      _busy = false;
    }
  }
}
