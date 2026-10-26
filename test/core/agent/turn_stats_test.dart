// Usage of one answer (calls, tokens, cache, time). How it is shown under
// the answer is tested with the chat bubble.
import 'package:arklores/core/agent/turn_stats.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('context is latest usage, with backward-compatible defaults', () {
    expect(TurnStats.fromJson({}).contextTokens, 0);
    expect(TurnStats.fromJson({}).contextEstimated, false);
    const first = TurnStats(contextTokens: 100000, calls: 1);
    const second =
        TurnStats(contextTokens: 32000, contextEstimated: true, calls: 2);
    expect((first + second).contextTokens, 32000);
    expect((first + second).contextEstimated, true);
    expect((first + second).calls, 3);
    // A digest's cost added later reports no context: the answer's stays.
    final withDigest = second + const TurnStats(calls: 1);
    expect(withDigest.contextTokens, 32000);
    expect(withDigest.contextEstimated, true);
    expect(formatUsageLine(second), startsWith('ctx ≈32.0k / '));
    expect(formatUsageLine(first), startsWith('ctx 100k / '));
    expect(formatUsageLine(const TurnStats()), isNot(contains('ctx')));
    expect(estimateTokens(16), 10);
    expect(estimateTokens(1), 1);
  });

  test('token counts', () {
    expect(formatTokenCount(950), '950');
    expect(formatTokenCount(14000), '14.0k');
    expect(formatTokenCount(38200), '38.2k');
    expect(formatTokenCount(381562), '382k');
    expect(formatTokenCount(1500000), '1.5M');
  });

  test('elapsed time', () {
    expect(formatElapsed(const Duration(seconds: 42)), '42s');
    expect(formatElapsed(const Duration(seconds: 360)), '6m00s');
    expect(formatElapsed(const Duration(seconds: 262)), '4m22s');
  });

  test('cache rate needs input and a reported cache', () {
    expect(const TurnStats().cacheRate, isNull);
    expect(const TurnStats(promptTokens: 100).cacheRate, isNull);
    expect(
      const TurnStats(promptTokens: 200, cachedPromptTokens: 150).cacheRate,
      0.75,
    );
  });

  test('json round trip', () {
    const stats = TurnStats(
      calls: 14,
      contextTokens: 84000,
      contextEstimated: true,
      promptTokens: 381562,
      cachedPromptTokens: 332736,
      completionTokens: 11665,
      elapsed: Duration(milliseconds: 262000),
      rateLimitRetries: 2,
      rateLimitSleep: Duration(seconds: 7),
    );
    final back = TurnStats.fromJson(stats.toJson().cast<String, dynamic>());
    expect(back.calls, 14);
    expect(back.contextTokens, 84000);
    expect(back.contextEstimated, isTrue);
    expect(back.elapsed, const Duration(seconds: 262));
    expect(back.rateLimitSleep, const Duration(seconds: 7));
    expect(back.promptTokens, 381562);
  });
}
