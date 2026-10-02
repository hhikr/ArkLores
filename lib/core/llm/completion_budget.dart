/// Token-budget handling for reasoning models (R12).
///
/// Reasoning models (e.g. deepseek flash, qwen thinking variants) spend
/// hidden reasoning tokens against `max_tokens`. With a tight ceiling the
/// visible `content` comes back EMPTY with `finish_reason=length` — verified:
/// `max_tokens=64` -> 64 reasoning tokens, content ''. Earlier rounds read
/// those empty replies as "the model has nothing to say" (R11.2) and the
/// 32-token disambiguator almost always fell back to candidate #1.
///
/// `max_tokens` is only a ceiling (billing follows tokens actually produced),
/// so callers use generous ceilings and this helper retries a truncated reply
/// once more with a larger one.
library;

import 'llm_client.dart';

/// Hard ceiling for escalated retries.
const int maxCompletionTokens = 16384;

/// Calls [client] and, when the reply was cut off by the token ceiling,
/// retries with a 4x larger ceiling (up to [maxCompletionTokens]) at most
/// [retries] times. With [retryPartial] false only EMPTY truncated replies
/// are retried (one-line answers may still parse when cut short).
Future<ChatCompletionResult> completeWithHeadroom(
  LLMClient client,
  List<Message> messages, {
  required double temperature,
  required int maxTokens,
  int retries = 1,
  bool retryPartial = false,
}) async {
  var budget = maxTokens;
  var result = await client.chatCompletion(
    messages,
    temperature: temperature,
    maxTokens: budget,
  );
  for (var attempt = 0; attempt < retries; attempt++) {
    final truncated = result.wasTruncated &&
        (retryPartial || result.content.trim().isEmpty);
    if (!truncated || budget >= maxCompletionTokens) break;
    budget = (budget * 4).clamp(budget, maxCompletionTokens);
    result = await client.chatCompletion(
      messages,
      temperature: temperature,
      maxTokens: budget,
    );
  }
  return result;
}
