import 'llm_client.dart';

/// One finished completion, as the usage meter saw it.
class UsageRecord {
  const UsageRecord({
    required this.promptTokens,
    required this.completionTokens,
    required this.cachedPromptTokens,
    required this.toolNames,
    required this.contentHead,
    required this.contentChars,
    required this.finishReason,
    this.timing,
  });

  final int? promptTokens;
  final int? completionTokens;
  final int? cachedPromptTokens;
  final List<String> toolNames;

  /// First characters of the reply (to tell an answer from a review).
  final String contentHead;
  final int contentChars;
  final String? finishReason;
  final CallTiming? timing;
}

/// Adds up the usage of every completion of one question (all clients: the
/// main agent, sub-agents, the reviewer, the reorganiser). Passive: it never
/// changes a request or a result.
class UsageMeter {
  int calls = 0;
  int promptTokens = 0;
  int completionTokens = 0;
  int cachedPromptTokens = 0;
  int rateLimitRetries = 0;
  Duration rateLimitSleep = Duration.zero;

  /// Per-call records (for timing analysis).
  final List<UsageRecord> records = [];

  /// Tool runs and local checks (name, start, end), for the same analysis.
  final List<({String name, DateTime start, DateTime end})> spans = [];

  /// Records one finished tool run or local check.
  void addSpan(String name, DateTime start, DateTime end) =>
      spans.add((name: name, start: start, end: end));

  /// Called after each add (the app uses it to show running totals).
  void Function()? onChanged;

  void add(ChatCompletionResult result) {
    calls++;
    promptTokens += result.promptTokens ?? 0;
    completionTokens += result.completionTokens ?? 0;
    cachedPromptTokens += result.cachedPromptTokens ?? 0;
    rateLimitRetries += result.timing?.rateLimitRetries ?? 0;
    rateLimitSleep += result.timing?.rateLimitSleep ?? Duration.zero;
    records.add(
      UsageRecord(
        promptTokens: result.promptTokens,
        completionTokens: result.completionTokens,
        cachedPromptTokens: result.cachedPromptTokens,
        toolNames: [for (final c in result.toolCalls) c.name],
        contentHead: result.content.length <= 24
            ? result.content
            : result.content.substring(0, 24),
        contentChars: result.content.length,
        finishReason: result.finishReason,
        timing: result.timing,
      ),
    );
    onChanged?.call();
  }

  void reset() {
    calls = 0;
    promptTokens = 0;
    completionTokens = 0;
    cachedPromptTokens = 0;
    rateLimitRetries = 0;
    rateLimitSleep = Duration.zero;
    records.clear();
    spans.clear();
    onChanged?.call();
  }

  Map<String, int> toJson() => {
        'llm_calls': calls,
        'prompt_tokens': promptTokens,
        'cached_prompt_tokens': cachedPromptTokens,
        'completion_tokens': completionTokens,
        'rate_limit_retries': rateLimitRetries,
        'rate_limit_sleep_ms': rateLimitSleep.inMilliseconds,
      };

  /// Timeline relative to [origin], in start order: every LLM call (when it
  /// started, how long it took, tokens) and every tool run or local check
  /// (`span`). Gaps between rows are time spent nowhere we measure.
  List<Map<String, Object?>> timeline(DateTime origin) {
    final rows = <(DateTime, Map<String, Object?>)>[
      for (final r in records)
        (
          r.timing?.startedAt ?? origin,
          {
            if (r.timing != null)
              'start_ms': r.timing!.startedAt.difference(origin).inMilliseconds,
            ...?r.timing?.toJson(),
            'prompt': r.promptTokens,
            'cached': r.cachedPromptTokens,
            'completion': r.completionTokens,
            'content_chars': r.contentChars,
            'head': r.contentHead,
            if (r.toolNames.isNotEmpty) 'tools': r.toolNames,
            'finish': r.finishReason,
          },
        ),
      for (final s in spans)
        (
          s.start,
          {
            'span': s.name,
            'start_ms': s.start.difference(origin).inMilliseconds,
            'total_ms': s.end.difference(s.start).inMilliseconds,
          },
        ),
    ]..sort((a, b) => a.$1.compareTo(b.$1));
    return [for (final row in rows) row.$2];
  }
}
