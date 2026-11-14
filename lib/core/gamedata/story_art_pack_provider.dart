import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../background/background_work.dart';
import 'gamedata_channel.dart';
import 'gamedata_provider.dart';
import 'resumable_download.dart';
import 'story_art_pack.dart';
import 'story_art_pack_installer.dart';

export 'story_art_pack_installer.dart' show StoryArtVariant;

final storyArtPackInstallerProvider =
    Provider.family<StoryArtPackInstaller, StoryArtVariant>(
  (ref, variant) => StoryArtPackInstaller(
    installDirectory: ref.watch(gameDataInstallerProvider).installDirectory,
    variant: variant,
  ),
);

/// The pack the pages draw from: the variant the user chose while it is
/// installed, else the other one if that is, else the chosen one (nothing
/// installed: the pages then show no art).
final storyArtVariantInUseProvider =
    FutureProvider<StoryArtVariant>((ref) async {
  final chosen = await ref
      .watch(storyArtPackInstallerProvider(StoryArtVariant.standard))
      .chosen();
  for (final variant in [
    chosen,
    ...StoryArtVariant.values.where((v) => v != chosen),
  ]) {
    if (await ref.watch(storyArtPackInstallerProvider(variant)).isInstalled()) {
      return variant;
    }
  }
  return chosen;
});

final storyArtPackProvider = FutureProvider<StoryArtPack>((ref) async {
  final variant = await ref.watch(storyArtVariantInUseProvider.future);
  final pack =
      StoryArtPack(await ref.watch(storyArtPackInstallerProvider(variant)).path);
  ref.onDispose(() => unawaited(pack.close()));
  return pack;
});

/// Draws the pages from [variant] (installed) from now on.
Future<void> useStoryArtVariant(WidgetRef ref, StoryArtVariant variant) async {
  await ref.read(storyArtPackInstallerProvider(variant)).choose(variant);
  ref.invalidate(storyArtVariantInUseProvider);
  ref.invalidate(storyArtPackStatusProvider);
}

final _installedStatusProvider =
    FutureProvider.family<StoryArtPackStatus, StoryArtVariant>(
        (ref, variant) async {
  await ref.watch(storyArtPackProvider.future);
  final inUse = await ref.watch(storyArtVariantInUseProvider.future);
  final offered =
      ref.watch(gameDataChannelProvider).valueOrNull?.storyArtOf(variant);
  final asset = offered?.usableBy(appBuildNumber) == true ? offered : null;
  final status =
      await ref.watch(storyArtPackInstallerProvider(variant)).status(asset: asset);
  return StoryArtPackStatus(
    installed: status.installed,
    inUse: status.installed && inUse == variant,
    bytes: status.bytes,
    spriteCount: status.spriteCount,
    backgroundCount: status.backgroundCount,
    illustrationCount: status.illustrationCount,
    kbCommit: status.kbCommit,
    installedSha: status.installedSha,
    asset: status.asset,
  );
});

final storyArtPackStatusProvider =
    FutureProvider.family<StoryArtPackStatus, StoryArtVariant>(
        (ref, variant) async {
  final progress = ref.watch(storyArtPackDownloadProvider(variant));
  final status = await ref.watch(_installedStatusProvider(variant).future);
  return StoryArtPackStatus(
    installed: status.installed,
    inUse: status.inUse,
    bytes: status.bytes,
    spriteCount: status.spriteCount,
    backgroundCount: status.backgroundCount,
    illustrationCount: status.illustrationCount,
    kbCommit: status.kbCommit,
    installedSha: status.installedSha,
    asset: status.asset,
    downloading: progress.downloading,
    received: progress.received,
    total: progress.total,
    error: progress.error,
  );
});

/// Whether any story-art pack is installed.
final storyArtInstalledProvider = FutureProvider<bool>((ref) async {
  for (final variant in StoryArtVariant.values) {
    if ((await ref.watch(storyArtPackStatusProvider(variant).future))
        .installed) {
      return true;
    }
  }
  return false;
});

final storyArtPackDownloadProvider = StateNotifierProvider.family<
    StoryArtPackDownloadNotifier, StoryArtPackStatus, StoryArtVariant>(
  StoryArtPackDownloadNotifier.new,
);

class StoryArtPackDownloadNotifier extends StateNotifier<StoryArtPackStatus> {
  StoryArtPackDownloadNotifier(this.ref, this.variant)
      : super(const StoryArtPackStatus());
  final Ref ref;
  final StoryArtVariant variant;
  GameDataDownloadToken? _token;
  bool _busy = false;
  void cancel() => _token?.cancel();

  /// Downloads this variant's pack; once installed, the pages use it.
  Future<void> start(String label) async {
    if (_busy) return;
    final asset =
        ref.read(gameDataChannelProvider).valueOrNull?.storyArtOf(variant);
    if (asset == null || !asset.usableBy(appBuildNumber)) return;
    _busy = true;
    _token = GameDataDownloadToken();
    state = const StoryArtPackStatus(downloading: true);
    final installer = ref.read(storyArtPackInstallerProvider(variant));
    try {
      await BackgroundWork.instance.run(label, () async {
        final pack = await ref.read(storyArtPackProvider.future);
        var last = -512 * 1024;
        await installer.install(
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
      await installer.choose(variant);
      ref.invalidate(storyArtVariantInUseProvider);
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
      // The open pack is closed whichever file it is; it reopens on the
      // next read.
      final pack = await ref.read(storyArtPackProvider.future);
      await ref.read(storyArtPackInstallerProvider(variant)).delete(pack);
      ref.invalidate(storyArtVariantInUseProvider);
      ref.invalidate(storyArtPackStatusProvider);
      if (mounted) state = const StoryArtPackStatus();
    } catch (e) {
      if (mounted) state = StoryArtPackStatus(error: e);
    } finally {
      _busy = false;
    }
  }
}
