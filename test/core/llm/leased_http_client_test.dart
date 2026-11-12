// A client disposed while a request is running (a service setting saved
// mid-question) closes only after that request.
import 'package:arklores/core/llm/leased_http_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('disposing waits for the request in flight', () async {
    final inner = _Closing();
    final client = LeasedHttpClient(inner);
    final running = client.begin();
    client.dispose();
    expect(inner.closed, isFalse, reason: 'a request is still running');
    expect(running, same(inner));
    client.end();
    expect(inner.closed, isTrue);
  });

  test('disposing an idle client closes it at once', () {
    final inner = _Closing();
    LeasedHttpClient(inner).dispose();
    expect(inner.closed, isTrue);
  });

  test('run ends its request even when it throws', () async {
    final inner = _Closing();
    final client = LeasedHttpClient(inner);
    client.dispose();
    // Closed already (nothing ran); an injected client is not replaced.
    expect(inner.closed, isTrue);
    final other = _Closing();
    final second = LeasedHttpClient(other);
    final failing = second.run<void>((_) async => throw StateError('x'));
    second.dispose();
    await expectLater(failing, throwsStateError);
    expect(other.closed, isTrue);
  });
}

class _Closing extends MockClient {
  _Closing() : super((_) async => http.Response('', 200));
  bool closed = false;

  @override
  void close() {
    closed = true;
    super.close();
  }
}
