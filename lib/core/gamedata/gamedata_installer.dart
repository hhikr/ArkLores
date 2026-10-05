import 'dart:async';
import 'dart:io';

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
  /// DBs installed before v0.10.1 or built in the app).
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

/// Network failures worth retrying (and resuming): TLS handshakes cut by the
/// network, dropped sockets, stalled streams.
bool isTransientNetworkError(Object error) {
  if (error is SocketException ||
      error is HandshakeException ||
      error is TlsException ||
      error is HttpException ||
      error is TimeoutException ||
      error is http.ClientException) {
    return true;
  }
  final text = '$error';
  return text.contains('Connection terminated') ||
      text.contains('Connection reset') ||
      text.contains('Connection closed');
}

/// Where an installation is, for the page to word.
enum GameDataInstallPhase {
  /// Waiting for the server's answer (attempt [GameDataInstallProgress]).
  connecting,
  downloading,

  /// Checking the downloaded file's SHA-256.
  verifying,

  /// Unzipping, validating and swapping the database in.
  installing,
}

/// Lets the page stop a download that is waiting for a server that does not
/// answer. The partial file stays, so the next start resumes it.
class GameDataDownloadToken {
  bool _cancelled = false;
  http.Client? _client;
  final Completer<void> _signal = Completer<void>();

  bool get cancelled => _cancelled;

  /// Completes when [cancel] is called.
  Future<void> get whenCancelled => _signal.future;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    _signal.complete();
    _client?.close();
  }
}

/// A download stopped by its [GameDataDownloadToken].
class GameDataDownloadCancelled implements Exception {
  const GameDataDownloadCancelled();

  @override
  String toString() => 'GameData download cancelled';
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

  /// Partial download of the compressed asset (resumed across attempts).
  static const _partialSuffix = '.download.gz';
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

  /// Downloads, verifies and installs the official asset.
  ///
  /// The compressed file is streamed to `<db>.download.gz` (never held in
  /// memory: the DB is ~600 MB), so an interrupted download resumes with an
  /// HTTP Range request on the next attempt or the next tap. Transient
  /// network errors (TLS handshake, socket, stalled stream) are retried up
  /// to [maxAttempts] times. The gz is checked against the expected SHA-256,
  /// then decompressed by streaming into a temp file, validated and swapped
  /// in; the installed DB is untouched until then.
  ///
  /// [onPhase] reports where the installation is (the page shows it, so a
  /// server that does not answer is visible as "connecting, attempt 2 of 5"
  /// rather than a bar that never moves); [cancelToken] stops a download
  /// that waits for a server. A compressed file placed by hand at
  /// `<db>.download.gz` is used as the partial download (and checked against
  /// the SHA-256 like any other), for networks that cannot reach the server.
  Future<bool> installFromReleaseAsset({
    http.Client? client,
    void Function(int receivedBytes, int? totalBytes)? onProgress,
    void Function(GameDataInstallPhase phase, int attempt)? onPhase,
    GameDataDownloadToken? cancelToken,
    bool overwrite = false,
    int maxAttempts = 6,
    Duration retryDelay = const Duration(seconds: 3),
    Duration connectTimeout = const Duration(seconds: 45),
    Duration stallTimeout = const Duration(seconds: 60),
  }) async {
    final asset = await getReleaseAsset();
    if (asset == null) return false;

    final dbFile = await _dbFile();
    if (!overwrite && await dbFile.exists()) return false;
    await dbFile.parent.create(recursive: true);

    // A partial download only resumes for the same asset. A file without a
    // key (placed by hand) is tried: the checksum below refuses a wrong one.
    final part = File('${dbFile.path}$_partialSuffix');
    final partKey = File('${part.path}.key');
    final key = asset.sha256 ?? asset.url.toString();
    if (await part.exists() &&
        await partKey.exists() &&
        (await partKey.readAsString()) != key) {
      await part.delete();
    }
    await partKey.writeAsString(key, flush: true);

    try {
      return await _install(
        asset: asset,
        dbFile: dbFile,
        part: part,
        partKey: partKey,
        client: client,
        onProgress: onProgress,
        onPhase: onPhase,
        cancelToken: cancelToken,
        maxAttempts: maxAttempts,
        retryDelay: retryDelay,
        connectTimeout: connectTimeout,
        stallTimeout: stallTimeout,
      );
    } catch (_) {
      // The key only means something next to a partial file.
      if (!await part.exists() && await partKey.exists()) {
        await partKey.delete();
      }
      rethrow;
    }
  }

  Future<bool> _install({
    required GameDataReleaseAsset asset,
    required File dbFile,
    required File part,
    required File partKey,
    required http.Client? client,
    required void Function(int receivedBytes, int? totalBytes)? onProgress,
    required void Function(GameDataInstallPhase phase, int attempt)? onPhase,
    required GameDataDownloadToken? cancelToken,
    required int maxAttempts,
    required Duration retryDelay,
    required Duration connectTimeout,
    required Duration stallTimeout,
  }) async {
    for (var attempt = 1;; attempt++) {
      final ownsClient = client == null;
      final httpClient = client ?? http.Client();
      cancelToken?._client = httpClient;
      try {
        if (cancelToken?.cancelled ?? false) {
          throw const GameDataDownloadCancelled();
        }
        onPhase?.call(GameDataInstallPhase.connecting, attempt);
        await _downloadResumable(
          httpClient,
          asset.url,
          part,
          onProgress: onProgress,
          onResponse: () => onPhase?.call(GameDataInstallPhase.downloading, attempt),
          connectTimeout: connectTimeout,
          stallTimeout: stallTimeout,
          cancelToken: cancelToken,
        );
        break;
      } catch (e) {
        // Closing the client to cancel makes the pending request fail.
        if (cancelToken?.cancelled ?? false) {
          throw const GameDataDownloadCancelled();
        }
        if (attempt >= maxAttempts || !isTransientNetworkError(e)) rethrow;
        await Future<void>.delayed(retryDelay * attempt);
      } finally {
        if (ownsClient) httpClient.close();
        cancelToken?._client = null;
      }
    }

    onPhase?.call(GameDataInstallPhase.verifying, 0);
    final actualSha = (await sha256.bind(part.openRead()).first).toString();
    final expectedSha = asset.sha256;
    if (expectedSha != null &&
        expectedSha.isNotEmpty &&
        actualSha.toLowerCase() != expectedSha.toLowerCase()) {
      // A corrupt partial must not be resumed again.
      await part.delete();
      throw StateError(
        'GameData checksum mismatch: expected $expectedSha, got $actualSha',
      );
    }

    onPhase?.call(GameDataInstallPhase.installing, 0);
    final tmp = File('${dbFile.path}.tmp');
    await part.openRead().transform(gzip.decoder).pipe(tmp.openWrite());
    final expectedSize = asset.uncompressedBytes;
    if (expectedSize != null && await tmp.length() != expectedSize) {
      await tmp.delete();
      throw StateError(
        'GameData database size mismatch: expected $expectedSize, '
        'got ${await tmp.length()}',
      );
    }
    await _installTempFile(tmp, dbFile);
    await File('${dbFile.path}$_assetMarkerSuffix')
        .writeAsString(actualSha, flush: true);
    await part.delete();
    if (await partKey.exists()) await partKey.delete();
    return true;
  }

  /// Streams [url] into [part], continuing an existing partial file with a
  /// Range request. A server that ignores the range (HTTP 200) restarts the
  /// file; 416 means the partial file is already complete.
  Future<void> _downloadResumable(
    http.Client client,
    Uri url,
    File part, {
    required Duration connectTimeout,
    required Duration stallTimeout,
    GameDataDownloadToken? cancelToken,
    void Function(int receivedBytes, int? totalBytes)? onProgress,
    void Function()? onResponse,
  }) async {
    var existing = await part.exists() ? await part.length() : 0;
    final request = http.Request('GET', url);
    if (existing > 0) request.headers['Range'] = 'bytes=$existing-';
    // A client that is stuck connecting may not give up when closed, so the
    // wait itself also ends when the user cancels.
    final sending = client.send(request).timeout(connectTimeout);
    final token = cancelToken;
    final http.StreamedResponse response;
    if (token == null) {
      response = await sending;
    } else {
      unawaited(sending.then<void>((_) {}, onError: (Object _) {}));
      response = await Future.any([
        sending,
        token.whenCancelled.then<http.StreamedResponse>(
          (_) => throw const GameDataDownloadCancelled(),
        ),
      ]);
    }
    onResponse?.call();
    if (existing > 0 && response.statusCode == 416) {
      await response.stream.drain<void>();
      return;
    }
    final resumed = response.statusCode == 206;
    if (response.statusCode != 200 && !resumed) {
      await response.stream.drain<void>();
      throw StateError(
        'Failed to download GameData database: HTTP ${response.statusCode}',
      );
    }
    if (!resumed) existing = 0;
    final length = response.contentLength;
    final total = length != null && length >= 0 ? existing + length : null;
    final sink = part.openWrite(
      mode: resumed ? FileMode.writeOnlyAppend : FileMode.writeOnly,
    );
    var received = existing;
    onProgress?.call(received, total);
    try {
      await for (final chunk in response.stream.timeout(stallTimeout)) {
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(received, total);
      }
    } finally {
      await sink.flush();
      await sink.close();
    }
    if (total != null && received < total) {
      throw const SocketException('GameData download ended early');
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
    await _installTempFile(tmp, dbFile);
  }

  /// Validates [tmp] and swaps it over [dbFile]; a DB that fails validation
  /// is deleted and the installed one stays.
  Future<void> _installTempFile(File tmp, File dbFile) async {
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
