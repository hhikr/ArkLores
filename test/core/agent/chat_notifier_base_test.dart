import 'package:arklores/core/agent/chat_notifier_base.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('the coalescer flushes once per interval and on demand',
      (tester) async {
    var flushes = 0;
    final coalescer = StreamCoalescer(
      () => flushes++,
      interval: const Duration(milliseconds: 60),
    );
    for (var i = 0; i < 10; i++) {
      coalescer.schedule();
    }
    expect(flushes, 0);
    await tester.pump(const Duration(milliseconds: 70));
    expect(flushes, 1);
    coalescer
      ..schedule()
      ..flushNow();
    expect(flushes, 2);
    await tester.pump(const Duration(milliseconds: 70));
    expect(flushes, 2);
  });
}
