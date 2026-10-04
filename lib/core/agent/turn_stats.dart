import '../llm/usage_meter.dart';

/// What one question cost: LLM calls, tokens and wall-clock time (shown in
/// grey under the answer and stored with the session turn).
class TurnStats {
  const TurnStats({
    this.calls = 0,
    this.promptTokens = 0,
    this.cachedPromptTokens = 0,
    this.completionTokens = 0,
    this.elapsed = Duration.zero,
    this.rateLimitRetries = 0,
    this.rateLimitSleep = Duration.zero,
  });

  /// Totals of [meter] over [elapsed].
  factory TurnStats.of(UsageMeter meter, Duration elapsed) => TurnStats(
        calls: meter.calls,
        promptTokens: meter.promptTokens,
        cachedPromptTokens: meter.cachedPromptTokens,
        completionTokens: meter.completionTokens,
        elapsed: elapsed,
        rateLimitRetries: meter.rateLimitRetries,
        rateLimitSleep: meter.rateLimitSleep,
      );

  factory TurnStats.fromJson(Map<String, dynamic> json) {
    int n(String key) => (json[key] as num?)?.toInt() ?? 0;
    return TurnStats(
      calls: n('llm_calls'),
      promptTokens: n('prompt_tokens'),
      cachedPromptTokens: n('cached_prompt_tokens'),
      completionTokens: n('completion_tokens'),
      elapsed: Duration(milliseconds: n('elapsed_ms')),
      rateLimitRetries: n('rate_limit_retries'),
      rateLimitSleep: Duration(milliseconds: n('rate_limit_sleep_ms')),
    );
  }

  final int calls;
  final int promptTokens;
  final int cachedPromptTokens;
  final int completionTokens;
  final Duration elapsed;
  final int rateLimitRetries;
  final Duration rateLimitSleep;

  /// Whether the provider reported any token usage.
  bool get hasTokens => promptTokens > 0 || completionTokens > 0;

  /// Share of the input served from the provider's prompt cache (0–1), or
  /// null when there is no input or the provider does not report it.
  double? get cacheRate => promptTokens > 0 && cachedPromptTokens > 0
      ? cachedPromptTokens / promptTokens
      : null;

  Map<String, Object?> toJson() => {
        'llm_calls': calls,
        'prompt_tokens': promptTokens,
        'cached_prompt_tokens': cachedPromptTokens,
        'completion_tokens': completionTokens,
        'elapsed_ms': elapsed.inMilliseconds,
        'rate_limit_retries': rateLimitRetries,
        'rate_limit_sleep_ms': rateLimitSleep.inMilliseconds,
      };
}

/// A token count for people: `53.4 万` / `1.4 万` (Chinese), `534.0k` /
/// `1.4M` (English), the plain number below 10 000 / 1 000.
String formatTokenCount(int tokens, {required bool zh}) {
  if (zh) {
    return tokens >= 10000
        ? '${(tokens / 10000).toStringAsFixed(1)} 万'
        : '$tokens';
  }
  if (tokens >= 1000000) return '${(tokens / 1000000).toStringAsFixed(1)}M';
  if (tokens >= 1000) return '${(tokens / 1000).toStringAsFixed(1)}k';
  return '$tokens';
}

/// A duration for people: `6 分 0 秒` / `6m 0s`, seconds only below a minute.
String formatElapsed(Duration d, {required bool zh}) {
  final total = d.inSeconds;
  final minutes = total ~/ 60;
  final seconds = total % 60;
  if (zh) return minutes == 0 ? '$seconds 秒' : '$minutes 分 $seconds 秒';
  return minutes == 0 ? '${seconds}s' : '${minutes}m ${seconds}s';
}
