// Several conversations answering at once share the clients and their
// meter; each counts its own calls (UsageMeter.runWith).
import 'package:arklores/core/llm/llm_client.dart';
import 'package:arklores/core/llm/usage_meter.dart';
import 'package:flutter_test/flutter_test.dart';

ChatCompletionResult _call(int prompt) => ChatCompletionResult(
      content: 'x',
      promptTokens: prompt,
      completionTokens: 1,
    );

void main() {
  test('a shared meter counts into the meter of the run it is used in',
      () async {
    final shared = UsageMeter();
    final a = UsageMeter();
    final b = UsageMeter();
    Future<void> later(int prompt) async {
      await Future<void>.delayed(const Duration(milliseconds: 5));
      shared.add(_call(prompt));
      shared.addSpan('tool', DateTime(2026), DateTime(2026));
    }

    await Future.wait([
      UsageMeter.runWith(a, () => later(10)),
      UsageMeter.runWith(b, () async {
        await later(20);
        await later(30);
      }),
    ]);
    expect((a.calls, a.promptTokens, a.spans.length), (1, 10, 1));
    expect((b.calls, b.promptTokens, b.spans.length), (2, 50, 2));
    expect(shared.calls, 0);

    // Outside any run: the shared meter itself.
    shared.add(_call(5));
    expect(shared.promptTokens, 5);
  });
}
