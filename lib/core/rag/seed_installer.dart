import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Manages installation of prebuilt seed data (vector DB + wiki cache) from
/// app assets into the user-writable directory on first launch.
///
/// After install, incremental indexing updates the local copies in place.
class SeedInstaller {
  static const _manifestAsset = 'assets/seeds/seed_manifest.json';
  static const _dbAsset = 'assets/seeds/arklores_knowledge.db';
  static const _cacheZipAsset = 'assets/seeds/wiki_cache.zip';

  /// Seed metadata keys stored in the remote DB's `seed_metadata` table.
  static const schemaVersionKey = 'schema_version';
  static const seedVersionKey = 'seed_version';
  static const embedProfileIdKey = 'embedding_profile_id';
  static const embedDimensionKey = 'embedding_dimension';
  static const chunkerVersionKey = 'chunker_version';
  static const builtAtKey = 'built_at';

  /// Installs seed data if the local database does not already exist.
  ///
  /// Returns `true` if installation occurred, `false` if already installed.
  /// Throws on non-recoverable asset load failures.
  Future<bool> installIfNeeded() async {
    final dir = await _getWritableDirectory();
    final dbFile = File(p.join(dir.path, 'arklores_knowledge.db'));

    if (await dbFile.exists()) {
      // Both db and cache are presumed present; the seed_manifest.json will
      // be written below if missing, but we don't re-copy the large assets.
      await _writeLocalManifest(dir);
      return false;
    }

    // ── Install database ─────────────────────────────────────────────
    try {
      final dbData = await rootBundle.load(_dbAsset);
      final dbTmp = File(p.join(dir.path, 'arklores_knowledge.db.tmp'));
      await dbTmp.parent.create(recursive: true);
      await dbTmp.writeAsBytes(
        dbData.buffer.asUint8List(dbData.offsetInBytes, dbData.lengthInBytes),
        flush: true,
      );
      await dbTmp.rename(dbFile.path);
    } catch (e) {
      // If asset doesn't exist, create fresh DB via VectorStore later.
      // The on-disk manifest will be absent, so we won't mark as seeded.
      return false;
    }

    // ── Install wiki cache ───────────────────────────────────────────
    try {
      final zipData = await rootBundle.load(_cacheZipAsset);
      final archive = ZipDecoder().decodeBytes(
        zipData.buffer.asUint8List(zipData.offsetInBytes, zipData.lengthInBytes),
      );

      final cacheDir = Directory(p.join(dir.path, 'wiki_cache'));
      if (await cacheDir.exists()) {
        // Avoid overwriting an existing cache directory (unlikely since we
        // checked db existence above, but future resets must use a clean slate).
      } else {
        final tmpDir = Directory(p.join(dir.path, 'wiki_cache.tmp'));
        if (await tmpDir.exists()) {
          await tmpDir.delete(recursive: true);
        }

        for (final entry in archive) {
          if (entry.isFile) {
            final outPath = p.join(tmpDir.path, entry.name);
            final outFile = File(outPath);
            await outFile.parent.create(recursive: true);
            await outFile.writeAsBytes(entry.content as List<int>);
          }
        }

        await tmpDir.rename(cacheDir.path);
      }
    } catch (e) {
      // Non-fatal: cache is optional, will be rebuilt on next index.
    }

    // ── Write local manifest ─────────────────────────────────────────
    await _writeLocalManifest(dir);

    return true;
  }

  Future<Directory> _getWritableDirectory() async {
    if (Platform.isAndroid) {
      final extDir = await getExternalStorageDirectory();
      if (extDir != null) return extDir;
    }
    return await getApplicationDocumentsDirectory();
  }

  Future<void> _writeLocalManifest(Directory dir) async {
    try {
      final manifestData = await rootBundle.load(_manifestAsset);
      final manifestFile = File(p.join(dir.path, 'seed_manifest.json'));
      await manifestFile.parent.create(recursive: true);
      await manifestFile.writeAsString(
        utf8.decode(
          manifestData.buffer
              .asUint8List(manifestData.offsetInBytes, manifestData.lengthInBytes),
        ),
      );
    } catch (_) {}
  }
}
