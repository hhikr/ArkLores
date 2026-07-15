import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' as sqflite;

class GameDataInstallStatus {
  final bool installed;
  final String dbPath;
  final int bytes;
  final Map<String, String> manifest;

  const GameDataInstallStatus({
    required this.installed,
    required this.dbPath,
    required this.bytes,
    required this.manifest,
  });

  String? get sourceCommit => manifest['source_arknights_commit'];
  String? get builtAt => manifest['built_at'];
  String? get entityCount => manifest['entity_count'];
  String? get recordCount => manifest['normalized_record_count'];
  String? get chunkCount => manifest['lore_chunk_count'];
}

class GameDataReleaseAsset {
  final Uri url;
  final String? sha256;
  final int? compressedBytes;
  final int? uncompressedBytes;

  const GameDataReleaseAsset({
    required this.url,
    this.sha256,
    this.compressedBytes,
    this.uncompressedBytes,
  });
}

class GameDataInstaller {
  static const _dbFileName = 'arklores_gamedata_zh.db';
  final Directory? installDirectory;

  // Development/test path before a public release exists. Example:
  // flutter run --dart-define=ARKLORES_GAMEDATA_DB_URL=http://192.168.1.2:8000/arklores_gamedata_zh.db.gz
  static const _definedUrl = String.fromEnvironment('ARKLORES_GAMEDATA_DB_URL');
  static const _definedSha =
      String.fromEnvironment('ARKLORES_GAMEDATA_DB_SHA256');

  const GameDataInstaller({this.installDirectory});

  Future<GameDataInstallStatus> getStatus() async {
    final file = await _dbFile();
    final exists = await file.exists();
    return GameDataInstallStatus(
      installed: exists,
      dbPath: file.path,
      bytes: exists ? await file.length() : 0,
      manifest: exists ? await _readManifest(file.path) : const {},
    );
  }

  Future<GameDataReleaseAsset?> getReleaseAsset() async {
    if (_definedUrl.trim().isEmpty) return null;
    return GameDataReleaseAsset(
      url: Uri.parse(_definedUrl.trim()),
      sha256: _definedSha.trim().isEmpty ? null : _definedSha.trim(),
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
      if (expectedSha != null && expectedSha.isNotEmpty) {
        final actualSha = sha256.convert(compressedBytes).toString();
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
      const requiredTables = {
        'gamedata_manifest',
        'entities',
        'entity_aliases',
        'entity_documents',
        'normalized_records',
        'story_lines',
        'story_scopes',
        'lore_chunks',
        'entity_documents_fts',
        'lore_chunks_fts',
      };
      final tableRows = await db.rawQuery(
        '''
        SELECT name
        FROM sqlite_master
        WHERE type IN ('table', 'virtual') AND name IN (${List.filled(requiredTables.length, '?').join(',')})
        ''',
        requiredTables.toList(growable: false),
      );
      final presentTables = {
        for (final row in tableRows) '${row['name']}',
      };
      final missingTables = requiredTables.difference(presentTables);
      if (missingTables.isNotEmpty) {
        throw StateError(
          'Downloaded GameData database is missing required table(s): ${missingTables.join(', ')}',
        );
      }

      final manifest = {
        for (final row in await db.query('gamedata_manifest'))
          '${row['key']}': '${row['value']}',
      };
      final schemaVersion = manifest['schema_version'];
      if (schemaVersion == null || schemaVersion.trim().isEmpty) {
        throw StateError(
          'Downloaded GameData database manifest is missing schema_version.',
        );
      }
      if (schemaVersion != '2') {
        throw StateError(
          'Downloaded GameData database schema_version $schemaVersion is incompatible; expected 2.',
        );
      }

      for (final entry in const {
        'entity_count': 'entities',
        'normalized_record_count': 'records',
        'lore_chunk_count': 'chunks',
      }.entries) {
        final value = int.tryParse(manifest[entry.key] ?? '');
        if (value == null || value <= 0) {
          throw StateError(
            'Downloaded GameData database manifest has invalid ${entry.key} ${entry.value} count.',
          );
        }
      }
    } finally {
      await db?.close();
    }
  }
}
