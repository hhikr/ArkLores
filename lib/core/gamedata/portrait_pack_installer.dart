import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' as sqflite;

import 'gamedata_channel.dart';
import 'portrait_pack.dart';
import 'resumable_download.dart';

class PortraitPackStatus {
  const PortraitPackStatus({
    this.installed = false,
    this.bytes = 0,
    this.spriteCount = 0,
    this.kbCommit = '',
    this.installedSha,
    this.asset,
    this.downloading = false,
    this.received = 0,
    this.total,
    this.error,
  });
  final bool installed, downloading;
  final int bytes, spriteCount, received;
  final int? total;
  final String kbCommit;
  final String? installedSha;
  final PortraitPackAsset? asset;
  final Object? error;
  bool get updateAvailable =>
      installed &&
      asset != null &&
      installedSha?.toLowerCase() != asset!.sha256.toLowerCase();
}

class PortraitPackInstaller {
  const PortraitPackInstaller({this.installDirectory});
  final Directory? installDirectory;
  static const fileName = 'arklores_portraits_zh.db';

  Future<String> get path async {
    final Directory dir;
    if (installDirectory != null) {
      dir = installDirectory!;
    } else if (Platform.isAndroid) {
      dir = await getExternalStorageDirectory() ??
          await getApplicationDocumentsDirectory();
    } else {
      dir = await getApplicationDocumentsDirectory();
    }
    return p.join(dir.path, fileName);
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

  Future<PortraitPackStatus> status({PortraitPackAsset? asset}) async {
    final file = File(await path);
    await _recover(file);
    final pack = PortraitPack(file.path);
    try {
      if (!await pack.installed) return PortraitPackStatus(asset: asset);
      final manifest = await pack.manifest();
      final marker = File('${file.path}.asset_sha256');
      return PortraitPackStatus(
        installed: true,
        bytes: await file.length(),
        spriteCount: int.tryParse(manifest['sprite_count'] ?? '') ?? 0,
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
    PortraitPackAsset asset, {
    required PortraitPack pack,
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

    try {
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
        throw StateError('Portrait pack checksum mismatch');
      }
      sqflite.Database? db;
      try {
        db = await sqflite.openDatabase(part.path,
            readOnly: true, singleInstance: false,);
        final manifest = {
          for (final row in await db.query('pack_manifest'))
            row['key']: row['value'],
        };
        if (manifest['pack_version'] != '1' ||
            (await db.query('portrait_images', limit: 1)).isEmpty) {
          throw StateError('Invalid portrait pack');
        }
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
      await File('${file.path}.asset_sha256')
          .writeAsString(actual, flush: true);
      if (await backup.exists()) await backup.delete();
    } finally {
      if (await part.exists()) await part.delete();
      if (await key.exists()) await key.delete();
    }
  }

  Future<void> delete(PortraitPack pack) async {
    await pack.close();
    final filePath = await path;
    for (final suffix in ['', '.asset_sha256']) {
      final file = File('$filePath$suffix');
      if (await file.exists()) await file.delete();
    }
  }
}
