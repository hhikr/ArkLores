import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' as sqflite;

import 'build/gamedata_db_validator.dart';

class GameDataInstallStatus {

  const GameDataInstallStatus({
    required this.installed,
    required this.dbPath,
    required this.bytes,
    required this.manifest,
    this.installedAssetSha,
    this.releaseAssetSha,
  });
  final bool installed;
  final String dbPath;
  final int bytes;
  final Map<String, String> manifest;

  /// SHA-256 of the official asset the installed DB came from (null for
  /// DBs installed before v0.11.0 or built in the app).
  final String? installedAssetSha;

  /// SHA-256 of the official asset this app build points at.
  final String? releaseAssetSha;

  /// The app was built for a different official knowledge base than the one
  /// installed (e.g. a new data release), so "update" is worth a tap.
  bool get updateAvailable =>
      installed &&
      releaseAssetSha != null &&
      releaseAssetSha!.isNotEmpty &&
      releaseAssetSha!.toLowerCase() != installedAssetSha?.toLowerCase();

  String? get sourceCommit => manifest['source_arknights_commit'];
  String? get builtAt => manifest['built_at'];
  String? get entityCount => manifest['entity_count'];
  String? get recordCount => manifest['normalized_record_count'];
  String? get chunkCount => manifest['lore_chunk_count'];
  String? get storyLineCount => manifest['story_line_count'];
}

class GameDataReleaseAsset {

  const GameDataReleaseAsset({
    required this.url,
    this.sha256,
    this.compressedBytes,
    this.uncompressedBytes,
  });
  final Uri url;
  final String? sha256;
  final int? compressedBytes;
  final int? uncompressedBytes;
}

class GameDataInstaller {

  const GameDataInstaller({
    this.installDirectory,
    this.releaseAssetUrl = _definedUrl,
    this.releaseAssetSha = _definedSha,
  });
  static const _dbFileName = 'arklores_gamedata_zh.db';

  /// Sidecar recording which official asset (gz SHA-256) was installed.
  static const _assetMarkerSuffix = '.asset_sha256';
  final Directory? installDirectory;

  /// Official asset this build downloads (dart-define; injectable in tests).
  final String releaseAssetUrl;
  final String releaseAssetSha;

  // Development/test path before a public release exists. Example:
  // flutter run --dart-define=ARKLORES_GAMEDATA_DB_URL=http://192.168.1.2:8000/arklores_gamedata_zh.db.gz
  static const _definedUrl = String.fromEnvironment('ARKLORES_GAMEDATA_DB_URL');
  static const _definedSha =
      String.fromEnvironment('ARKLORES_GAMEDATA_DB_SHA256');

  Future<GameDataInstallStatus> getStatus() async {
    final file = await _dbFile();
    final exists = await file.exists();
    final marker = File('${file.path}$_assetMarkerSuffix');
    return GameDataInstallStatus(
      installed: exists,
      dbPath: file.path,
      bytes: exists ? await file.length() : 0,
      manifest: exists ? await _readManifest(file.path) : const {},
      installedAssetSha: exists && await marker.exists()
          ? (await marker.readAsString()).trim()
          : null,
      releaseAssetSha: releaseAssetUrl.trim().isEmpty
          ? null
          : releaseAssetSha.trim(),
    );
  }

  Future<GameDataReleaseAsset?> getReleaseAsset() async {
    if (releaseAssetUrl.trim().isEmpty) return null;
    return GameDataReleaseAsset(
      url: Uri.parse(releaseAssetUrl.trim()),
      sha256: releaseAssetSha.trim().isEmpty ? null : releaseAssetSha.trim(),
    );
  }

  Future<bool> installFromReleaseAsset({
    http.Client? client,
    void Function(int receivedBytes, int? totalBytes)? onProgress,
    bool overwrite = false,
  }) async {
    final asset = await getReleaseAsset();
    if (asset == null) return false;

    final dbFile = await _dbFile();
    if (!overwrite && await dbFile.exists()) return false;

    final ownsClient = client == null;
    final httpClient = client ?? http.Client();
    try {
      final request = http.Request('GET', asset.url);
      final response = await httpClient.send(request);
      if (response.statusCode != 200) {
        throw StateError(
          'Failed to download GameData database: HTTP ${response.statusCode}',
        );
      }

      final compressed = BytesBuilder(copy: false);
      var received = 0;
      final contentLength = response.contentLength;
      final total =
          contentLength != null && contentLength >= 0 ? contentLength : null;
      await for (final chunk in response.stream) {
        compressed.add(chunk);
        received += chunk.length;
        onProgress?.call(received, total);
      }

      final compressedBytes = compressed.takeBytes();
      final expectedSha = asset.sha256;
      final actualSha = sha256.convert(compressedBytes).toString();
      if (expectedSha != null && expectedSha.isNotEmpty) {
        if (actualSha.toLowerCase() != expectedSha.toLowerCase()) {
          throw StateError(
            'GameData checksum mismatch: expected $expectedSha, got $actualSha',
          );
        }
      }

      final dbBytes = Uint8List.fromList(gzip.decode(compressedBytes));
      final expectedSize = asset.uncompressedBytes;
      if (expectedSize != null && dbBytes.length != expectedSize) {
        throw StateError(
          'GameData database size mismatch: expected $expectedSize, got ${dbBytes.length}',
        );
      }

      await installFromBytes(dbBytes, overwrite: overwrite);
      await File('${dbFile.path}$_assetMarkerSuffix')
          .writeAsString(actualSha, flush: true);
      return true;
    } finally {
      if (ownsClient) httpClient.close();
    }
  }

  Future<void> installFromBytes(
    List<int> dbBytes, {
    bool overwrite = false,
  }) async {
    final dbFile = await _dbFile();
    if (!overwrite && await dbFile.exists()) return;

    final tmp = File('${dbFile.path}.tmp');
    await tmp.parent.create(recursive: true);
    await tmp.writeAsBytes(dbBytes, flush: true);
    try {
      await _validateDatabase(tmp.path);
    } catch (_) {
      if (await tmp.exists()) await tmp.delete();
      rethrow;
    }
    if (await dbFile.exists()) {
      await dbFile.delete();
    }
    // The marker describes the replaced file; installFromReleaseAsset writes
    // a new one for official assets.
    final marker = File('${dbFile.path}$_assetMarkerSuffix');
    if (await marker.exists()) await marker.delete();
    await tmp.rename(dbFile.path);
  }

  Future<File> _dbFile() async {
    final dir = await _writableDirectory();
    return File(p.join(dir.path, _dbFileName));
  }

  Future<Directory> _writableDirectory() async {
    if (installDirectory != null) return installDirectory!;
    if (Platform.isAndroid) {
      final extDir = await getExternalStorageDirectory();
      if (extDir != null) return extDir;
    }
    return getApplicationDocumentsDirectory();
  }

  Future<Map<String, String>> _readManifest(String dbPath) async {
    sqflite.Database? db;
    try {
      db = await sqflite.openDatabase(dbPath, readOnly: true);
      final rows = await db.query('gamedata_manifest');
      return {
        for (final row in rows) '${row['key']}': '${row['value']}',
      };
    } catch (_) {
      return const {};
    } finally {
      await db?.close();
    }
  }

  Future<void> _validateDatabase(String dbPath) async {
    final file = File(dbPath);
    if (!await file.exists() || await file.length() == 0) {
      throw StateError('Downloaded GameData database is empty.');
    }

    sqflite.Database? db;
    try {
      db = await sqflite.openDatabase(dbPath, readOnly: true);
      await validateGameDataDatabase(db);
    } finally {
      await db?.close();
    }
  }
}
