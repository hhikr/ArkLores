import 'package:http/http.dart' as http;

/// The HTTP client of a model or embedding client that a provider may
/// dispose while a question is still using it.
///
/// Saving the service settings rebuilds the providers, which dispose the old
/// clients; `http.Client.close` breaks the connections in use, so a running
/// question failed with a network error (2026-11-13). Now closing waits for
/// the requests in flight, and a request that comes after (the next turn of
/// the same question) opens a fresh client that is closed again when it is
/// done.
class LeasedHttpClient {
  LeasedHttpClient([http.Client? client])
      : _injected = client,
        _client = client ?? http.Client();

  /// A client given from outside (tests) is never replaced.
  final http.Client? _injected;
  http.Client _client;
  int _running = 0;
  bool _disposed = false;
  bool _closed = false;

  /// The client for one request; pair every call with [end].
  http.Client begin() {
    if (_closed && _injected == null) {
      _client = http.Client();
      _closed = false;
    }
    _running++;
    return _client;
  }

  /// One request started with [begin] is done.
  void end() {
    _running--;
    if (_disposed && _running <= 0) _close();
  }

  /// Runs [request] between [begin] and [end].
  Future<T> run<T>(Future<T> Function(http.Client client) request) async {
    final client = begin();
    try {
      return await request(client);
    } finally {
      end();
    }
  }

  /// Closes now when nothing is running, otherwise after the last request.
  void dispose() {
    _disposed = true;
    if (_running <= 0) _close();
  }

  void _close() {
    if (_closed) return;
    _closed = true;
    _client.close();
  }
}
