import 'dart:async';

import 'package:arklores/core/background/background_work.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('test/background_work');
  final calls = <String>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add('${call.method}:${(call.arguments as Map)['text']}');
      return true;
    });
  });

  test('the service runs from the first operation to the last', () async {
    final work = BackgroundWork(channel: channel, enabled: true);
    final slow = Completer<void>();
    final first = work.run('A', () => slow.future);
    await Future<void>.delayed(Duration.zero);
    final second = work.run('B', () async {});
    await second;
    // B ended while A still runs: the service stays, the text shrinks to A.
    expect(calls, ['begin:A', 'begin:A · B', 'begin:A']);
    expect(work.activeKeys, hasLength(1));
    slow.complete();
    await first;
    expect(calls.last, startsWith('end'));
    expect(work.activeKeys, isEmpty);
  });

  test('an operation that throws still ends', () async {
    final work = BackgroundWork(channel: channel, enabled: true);
    await expectLater(
      work.run('A', () async => throw StateError('x')),
      throwsStateError,
    );
    expect(calls.last, startsWith('end'));
    expect(work.activeKeys, isEmpty);
  });

  test('a service that cannot start does not stop the operation', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(code: 'start_failed');
    });
    final work = BackgroundWork(channel: channel, enabled: true);
    expect(await work.run('A', () async => 42), 42);
  });

  test('off Android nothing is called', () async {
    final work = BackgroundWork(channel: channel, enabled: false);
    expect(await work.run('A', () async => 1), 1);
    expect(calls, isEmpty);
  });
}
