import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../background/background_work.dart';
import 'gamedata_channel.dart';
import 'gamedata_provider.dart';
import 'resumable_download.dart';
import 'story_art_pack.dart';
import 'story_art_pack_installer.dart';

final storyArtPackInstallerProvider = Provider<StoryArtPackInstaller>(
  (ref) => StoryArtPackInstaller(
      installDirectory: ref.watch(gameDataInstallerProvider).installDirectory,),
);

final storyArtPackProvider = FutureProvider<StoryArtPack>((ref) async {
  final pack =
      StoryArtPack(await ref.watch(storyArtPackInstallerProvider).path);
  ref.onDispose(() => unawaited(pack.close()));
  return pack;
});

final _installedStatusProvider =
    FutureProvider<StoryArtPackStatus>((ref) async {
  await ref.watch(storyArtPackProvider.future);
  final offered = ref.watch(gameDataChannelProvider).valueOrNull?.storyArt;
  final asset = offered?.usableBy(appBuildNumber) == true ? offered : null;
  return ref.watch(storyArtPackInstallerProvider).status(asset: asset);
});

final storyArtPackStatusProvider =
    FutureProvider<StoryArtPackStatus>((ref) async {
  final progress = ref.watch(storyArtPackDownloadProvider);
  final status = await ref.watch(_installedStatusProvider.future);
  final asset = status.asset;
  return StoryArtPackStatus(
    installed: status.installed,
    bytes: status.bytes,
    spriteCount: status.spriteCount,
    backgroundCount: status.backgroundCount,
    illustrationCount: status.illustrationCount,
    kbCommit: status.kbCommit,
    installedSha: status.installedSha,
    asset: asset,
    downloading: progress.downloading,
    received: progress.received,
    total: progress.total,
    error: progress.error,
  );
});

final storyArtPackDownloadProvider =
    StateNotifierProvider<StoryArtPackDownloadNotifier, StoryArtPackStatus>(
  StoryArtPackDownloadNotifier.new,
);

class StoryArtPackDownloadNotifier extends StateNotifier<StoryArtPackStatus> {
  StoryArtPackDownloadNotifier(this.ref) : super(const StoryArtPackStatus());
  final Ref ref;
  GameDataDownloadToken? _token;
  bool _busy = false;
  void cancel() => _token?.cancel();

  Future<void> start(String label) async {
    if (_busy) return;
    final asset = ref.read(gameDataChannelProvider).valueOrNull?.storyArt;
    if (asset == null || !asset.usableBy(appBuildNumber)) return;
    _busy = true;
    _token = GameDataDownloadToken();
    state = const StoryArtPackStatus(downloading: true);
    try {
      await BackgroundWork.instance.run(label, () async {
        final pack = await ref.read(storyArtPackProvider.future);
        var last = -512 * 1024;
        await ref.read(storyArtPackInstallerProvider).install(
          asset,
          pack: pack,
          cancelToken: _token,
          onProgress: (received, total) {
            if (!mounted || (received - last < 512 * 1024 && received != total)) {
              return;
            }
            last = received;
            state = StoryArtPackStatus(
                downloading: true, received: received, total: total,);
          },
        );
      });
      ref.invalidate(storyArtPackProvider);
      if (mounted) state = const StoryArtPackStatus();
    } on GameDataDownloadCancelled {
      if (mounted) state = const StoryArtPackStatus();
    } catch (e) {
      if (mounted) state = StoryArtPackStatus(error: e);
    } finally {
      _token = null;
      _busy = false;
      ref.invalidate(storyArtPackStatusProvider);
    }
  }

  Future<void> delete() async {
    if (_busy) return;
    _busy = true;
    try {
      final pack = await ref.read(storyArtPackProvider.future);
      await ref.read(storyArtPackInstallerProvider).delete(pack);
      ref.invalidate(storyArtPackProvider);
      ref.invalidate(storyArtPackStatusProvider);
      if (mounted) state = const StoryArtPackStatus();
    } catch (e) {
      if (mounted) state = StoryArtPackStatus(error: e);
    } finally {
      _busy = false;
    }
  }
}
