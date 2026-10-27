// Usage of one answer (calls, tokens, cache, time). How it is shown under
// the answer is tested with the chat bubble.
import 'package:arklores/core/agent/turn_stats.dart';
import 'package:arklores/core/llm/token_prices.dart';
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

  test('cost: uncached input, cached input at its share, output', () {
    // The question this was measured on: 3.15M in (96% cached), 12.8k out.
    const stats = TurnStats(
      calls: 34,
      promptTokens: 3152773,
      cachedPromptTokens: 3031104,
      completionTokens: 12758,
      elapsed: Duration(seconds: 486),
    );
    const prices = TokenPrices(
      inputPerMillion: 2,
      outputPerMillion: 8,
      cachedPercent: 20,
    );
    // (121669 + 3031104 × 0.2) × 2 + 12758 × 8, per million.
    expect(stats.costAt(prices), closeTo(1.5578, 1e-4));
    expect(formatUsageLine(stats, prices: prices), endsWith(' / 8m06s / cost 1.56'));
    // Nothing set, or nothing reported: no cost.
    expect(stats.costAt(const TokenPrices()), isNull);
    expect(formatUsageLine(stats, prices: const TokenPrices()),
        isNot(contains('cost')),);
    expect(const TurnStats(calls: 1).costAt(prices), isNull);
    // No discount by default; a cache larger than the input is clamped.
    expect(
      const TokenPrices(inputPerMillion: 1)
          .cost(prompt: 1000000, cached: 2000000, completion: 0),
      1.0,
    );
  });

  test('cost format and stored prices', () {
    expect(formatCost(12.4), '12.40');
    expect(formatCost(0.38512), '0.385');
    expect(formatCost(0.0041234), '0.00412');
    expect(formatCost(0), '0');
    const prices =
        TokenPrices(inputPerMillion: 2.5, outputPerMillion: 10, cachedPercent: 25);
    expect(TokenPrices.fromJson(prices.toJson().cast<String, dynamic>()), prices);
    // Bad values fall back: no price, no discount.
    expect(
      TokenPrices.fromJson({'input': -1, 'output': 'x', 'cached_percent': 300}),
      const TokenPrices(cachedPercent: 100),
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
