import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' as sqflite;

import 'gamedata_channel.dart';
import 'resumable_download.dart';
import 'story_art_pack.dart';

/// The two story-art packs (developer 2026-11-12): the user downloads either
/// or both and picks the one the pages draw from. Each is its own file and
/// its own entry in the channel file.
enum StoryArtVariant {
  /// Portraits 800 high, WebP 80.
  standard('arklores_story_art_zh.db', 'arknights_story_art'),

  /// Every image at its source's size, WebP 92.
  hd('arklores_story_art_hd_zh.db', 'arknights_story_art_hd');

  const StoryArtVariant(this.fileName, this.channelKey);
  final String fileName;

  /// The key of its entry in the channel file.
  final String channelKey;
}

class StoryArtPackStatus {
  const StoryArtPackStatus({
    this.installed = false,
    this.inUse = false,
    this.bytes = 0,
    this.spriteCount = 0,
    this.backgroundCount = 0,
    this.illustrationCount = 0,
    this.kbCommit = '',
    this.installedSha,
    this.asset,
    this.downloading = false,
    this.received = 0,
    this.total,
    this.error,
  });
  final bool installed, downloading;

  /// Installed, and the pack the pages draw from.
  final bool inUse;
  final int bytes, spriteCount, backgroundCount, illustrationCount, received;
  final int? total;
  final String kbCommit;
  final String? installedSha;
  final StoryArtPackAsset? asset;
  final Object? error;
  bool get updateAvailable =>
      installed &&
      asset != null &&
      installedSha?.toLowerCase() != asset!.sha256.toLowerCase();
}

class StoryArtPackInstaller {
  const StoryArtPackInstaller({
    this.installDirectory,
    this.variant = StoryArtVariant.standard,
  });
  final Directory? installDirectory;
  final StoryArtVariant variant;

  /// Holds the name of the variant the user chose to use.
  static const choiceFileName = 'arklores_story_art_in_use';

  Future<Directory> get _directory async {
    if (installDirectory != null) return installDirectory!;
    if (Platform.isAndroid) {
      return await getExternalStorageDirectory() ??
          await getApplicationDocumentsDirectory();
    }
    return getApplicationDocumentsDirectory();
  }

  Future<String> get path async {
    final dir = await _directory;
    final old = File(p.join(dir.path, 'arklores_portraits_zh.db'));
    if (await old.exists()) await old.delete();
    return p.join(dir.path, variant.fileName);
  }

  /// The variant the user chose to use (standard until one is chosen).
  Future<StoryArtVariant> chosen() async {
    final file = File(p.join((await _directory).path, choiceFileName));
    if (!await file.exists()) return StoryArtVariant.standard;
    final name = (await file.readAsString()).trim();
    return StoryArtVariant.values.where((v) => v.name == name).firstOrNull ??
        StoryArtVariant.standard;
  }

  /// Makes [choice] the variant the pages draw from while it is installed.
  Future<void> choose(StoryArtVariant choice) async {
    final dir = await _directory;
    await dir.create(recursive: true);
    await File(p.join(dir.path, choiceFileName))
        .writeAsString(choice.name, flush: true);
  }

  /// Whether this variant's pack is in place.
  Future<bool> isInstalled() async {
    final file = File(await path);
    await _recover(file);
    final pack = StoryArtPack(file.path);
    try {
      return await pack.installed;
    } finally {
      await pack.close();
    }
  }

  /// An install stopped between moving the old pack aside and moving the new
  /// one in leaves only `.previous`: put it back. With the pack in place it
  /// is a leftover, and rename cannot replace it on every platform.
  Future<void> _recover(File file) async {
    final backup = File('${file.path}.previous');
    if (!await backup.exists()) return;
    if (await file.exists()) {
      await backup.delete();
    } else {
      await backup.rename(file.path);
    }
  }

  Future<StoryArtPackStatus> status({StoryArtPackAsset? asset}) async {
    final file = File(await path);
    await _recover(file);
    final pack = StoryArtPack(file.path);
    try {
      if (!await pack.installed) return StoryArtPackStatus(asset: asset);
      final manifest = await pack.manifest();
      final marker = File('${file.path}.asset_sha256');
      return StoryArtPackStatus(
        installed: true,
        bytes: await file.length(),
        spriteCount: int.tryParse(manifest['sprite_count'] ?? '') ?? 0,
        backgroundCount:
            (int.tryParse(manifest['background_count'] ?? '') ?? 0) -
                (int.tryParse(manifest['solid_count'] ?? '') ?? 0),
        illustrationCount:
            int.tryParse(manifest['illustration_count'] ?? '') ?? 0,
        kbCommit: manifest['kb_commit'] ?? '',
        asset: asset,
        installedSha:
            await marker.exists() ? (await marker.readAsString()).trim() : null,
      );
    } finally {
      await pack.close();
    }
  }

  Future<void> install(
    StoryArtPackAsset asset, {
    required StoryArtPack pack,
    GameDataDownloadToken? cancelToken,
    http.Client? client,
    void Function(int, int?)? onProgress,
    int maxAttempts = 6,
    Duration retryDelay = const Duration(seconds: 3),
    Duration connectTimeout = const Duration(seconds: 45),
    Duration stallTimeout = const Duration(seconds: 60),
  }) async {
    final file = File(await path);
    final part = File('${file.path}.download');
    final key = File('${part.path}.key');
    await file.parent.create(recursive: true);
    await _recover(file);
    void checkCancelled() {
      if (cancelToken?.cancelled ?? false) {
        throw const GameDataDownloadCancelled();
      }
    }

    // A download cancelled or cut off keeps its partial file (and the key
    // naming its asset), so the next start resumes it; only a file that
    // fails the checks is thrown away (2026-11-13: every stop threw away
    // what had come of an 800 MB pack).
    Future<void> discard() async {
      if (await part.exists()) await part.delete();
      if (await key.exists()) await key.delete();
    }

    checkCancelled();
    if (await part.exists() &&
        await key.exists() &&
        await key.readAsString() != asset.sha256) {
      await part.delete();
    }
    await key.writeAsString(asset.sha256, flush: true);
    for (var attempt = 1;; attempt++) {
      checkCancelled();
      final c = client ?? http.Client();
      cancelToken?.attachClient(c);
      try {
        await downloadResumable(
          c,
          Uri.parse(asset.url),
          part,
          connectTimeout: connectTimeout,
          stallTimeout: stallTimeout,
          cancelToken: cancelToken,
          onProgress: onProgress,
        );
        break;
      } catch (e) {
        checkCancelled();
        if (attempt >= maxAttempts || !isTransientNetworkError(e)) rethrow;
        await Future.any([
          Future<void>.delayed(retryDelay * attempt),
          if (cancelToken != null) cancelToken.whenCancelled,
        ]);
      } finally {
        cancelToken?.attachClient(null);
        if (client == null) c.close();
      }
    }
    checkCancelled();
    final actual = (await sha256.bind(part.openRead()).first).toString();
    if (actual.toLowerCase() != asset.sha256.toLowerCase()) {
      await discard();
      throw StateError('Portrait pack checksum mismatch');
    }
    sqflite.Database? db;
    try {
      db = await sqflite.openDatabase(
        part.path,
        readOnly: true,
        singleInstance: false,
      );
      final manifest = {
        for (final row in await db.query('pack_manifest'))
          row['key']: row['value'],
      };
      // Packs built before there were two have no variant: standard.
      if (manifest['pack_version'] != '2' ||
          (manifest['variant'] ?? StoryArtVariant.standard.name) !=
              variant.name ||
          (await db.query('portrait_images', limit: 1)).isEmpty) {
        throw StateError('Invalid portrait pack');
      }
    } catch (_) {
      await db?.close();
      db = null;
      await discard();
      rethrow;
    } finally {
      await db?.close();
    }
    checkCancelled();
    await pack.close();
    checkCancelled();
    // Keep a rollback copy on platforms where rename cannot replace a file.
    final backup = File('${file.path}.previous');
    if (await file.exists()) await file.rename(backup.path);
    try {
      await part.rename(file.path);
    } catch (_) {
      if (await backup.exists()) await backup.rename(file.path);
      rethrow;
    }
    await File('${file.path}.asset_sha256').writeAsString(actual, flush: true);
    if (await backup.exists()) await backup.delete();
    await discard();
  }

  Future<void> delete(StoryArtPack pack) async {
    await pack.close();
    final filePath = await path;
    for (final suffix in ['', '.asset_sha256']) {
      final file = File('$filePath$suffix');
      if (await file.exists()) await file.delete();
    }
  }
}
