import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
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

    final installed = await _installBundledDatabase(dbFile);
    if (!installed) {
      // v0.3+ ships the large seed DB as a GitHub release asset instead of a
      // Flutter asset. VectorStore will create an empty DB until the user
      // downloads the release seed from the knowledge base flow.
      await _writeLocalManifest(dir);
      return false;
    }

    await _installWikiCache(dir);

    // ── Write local manifest ─────────────────────────────────────────
    await _writeLocalManifest(dir);

    return true;
  }

  Future<SeedDatabaseAsset?> getReleaseDatabaseAsset() async {
    final manifest = await _loadManifest();
    final database = manifest['database'];
    if (database is! Map<String, dynamic>) return null;
    if (database['delivery'] != 'release-asset') return null;

    final url = database['url'] as String?;
    final sha = database['sha256'] as String?;
    final fileName = database['fileName'] as String?;
    final compressedBytes = database['compressedBytes'] as int?;
    final uncompressedBytes = database['uncompressedBytes'] as int?;
    if (url == null || sha == null || fileName == null) return null;

    return SeedDatabaseAsset(
      url: Uri.parse(url),
      fileName: fileName,
      sha256: sha.toLowerCase(),
      compressedBytes: compressedBytes,
      uncompressedBytes: uncompressedBytes,
    );
  }

  /// Downloads the release seed DB (`.db.gz`), verifies its SHA256, decompresses
  /// it, and atomically installs it into the writable knowledge base directory.
  Future<bool> installFromReleaseAsset({
    http.Client? client,
    void Function(int receivedBytes, int? totalBytes)? onProgress,
    bool overwrite = false,
  }) async {
    final asset = await getReleaseDatabaseAsset();
    if (asset == null) return false;

    final dir = await _getWritableDirectory();
    final dbFile = File(p.join(dir.path, 'arklores_knowledge.db'));
    if (!overwrite && await dbFile.exists()) {
      await _writeLocalManifest(dir);
      return false;
    }

    final ownsClient = client == null;
    final httpClient = client ?? http.Client();
    try {
      final request = http.Request('GET', asset.url);
      final response = await httpClient.send(request);
      if (response.statusCode != 200) {
        throw StateError(
          'Failed to download seed database: HTTP ${response.statusCode}',
        );
      }

      final compressed = BytesBuilder(copy: false);
      var received = 0;
      final contentLength = response.contentLength;
      final total = contentLength != null && contentLength >= 0
          ? contentLength
          : null;
      await for (final chunk in response.stream) {
        compressed.add(chunk);
        received += chunk.length;
        onProgress?.call(received, total);
      }

      final compressedBytes = compressed.takeBytes();
      final actualSha = sha256.convert(compressedBytes).toString();
      if (actualSha.toLowerCase() != asset.sha256) {
        throw StateError(
          'Seed database checksum mismatch: expected ${asset.sha256}, got $actualSha',
        );
      }

      final dbBytes = Uint8List.fromList(gzip.decode(compressedBytes));
      final expectedSize = asset.uncompressedBytes;
      if (expectedSize != null && dbBytes.length != expectedSize) {
        throw StateError(
          'Seed database size mismatch: expected $expectedSize, got ${dbBytes.length}',
        );
      }

      final dbTmp = File(p.join(dir.path, 'arklores_knowledge.db.tmp'));
      await dbTmp.parent.create(recursive: true);
      await dbTmp.writeAsBytes(dbBytes, flush: true);
      if (await dbFile.exists()) {
        await dbFile.delete();
      }
      await dbTmp.rename(dbFile.path);

      await _installWikiCache(dir);
      await _writeLocalManifest(dir);
      return true;
    } finally {
      if (ownsClient) httpClient.close();
    }
  }

  Future<Directory> _getWritableDirectory() async {
    if (Platform.isAndroid) {
      final extDir = await getExternalStorageDirectory();
      if (extDir != null) return extDir;
    }
    return await getApplicationDocumentsDirectory();
  }

  Future<bool> _installBundledDatabase(File dbFile) async {
    try {
      final dbData = await rootBundle.load(_dbAsset);
      final dbTmp = File('${dbFile.path}.tmp');
      await dbTmp.parent.create(recursive: true);
      await dbTmp.writeAsBytes(
        dbData.buffer.asUint8List(dbData.offsetInBytes, dbData.lengthInBytes),
        flush: true,
      );
      await dbTmp.rename(dbFile.path);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _installWikiCache(Directory dir) async {
    try {
      final zipData = await rootBundle.load(_cacheZipAsset);
      final archive = ZipDecoder().decodeBytes(
        zipData.buffer.asUint8List(zipData.offsetInBytes, zipData.lengthInBytes),
      );

      final cacheDir = Directory(p.join(dir.path, 'wiki_cache'));
      if (await cacheDir.exists()) return;

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
    } catch (_) {
      // Non-fatal: cache is optional, will be rebuilt on next index.
    }
  }

  Future<Map<String, dynamic>> _loadManifest() async {
    final manifestData = await rootBundle.load(_manifestAsset);
    final jsonText = utf8.decode(
      manifestData.buffer
          .asUint8List(manifestData.offsetInBytes, manifestData.lengthInBytes),
    );
    return json.decode(jsonText) as Map<String, dynamic>;
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

class SeedDatabaseAsset {
  const SeedDatabaseAsset({
    required this.url,
    required this.fileName,
    required this.sha256,
    this.compressedBytes,
    this.uncompressedBytes,
  });

  final Uri url;
  final String fileName;
  final String sha256;
  final int? compressedBytes;
  final int? uncompressedBytes;
}
