import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

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

  void attachClient(http.Client? client) => _client = client;

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

/// Streams [url] into [part], continuing an existing partial file with a
/// Range request. A server that ignores the range (HTTP 200) restarts the
/// file; 416 means the partial file is already complete.
Future<void> downloadResumable(
  http.Client client,
  Uri url,
  File part, {
  required Duration connectTimeout,
  required Duration stallTimeout,
  GameDataDownloadToken? cancelToken,
  void Function(int receivedBytes, int? totalBytes)? onProgress,
  void Function()? onResponse,
}) async {
  if (cancelToken?.cancelled ?? false) throw const GameDataDownloadCancelled();
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
