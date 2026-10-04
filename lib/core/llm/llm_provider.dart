import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/providers/settings_provider.dart';
import 'embedding_client.dart';
import 'llm_client.dart';
import 'openai_client.dart';
import 'usage_meter.dart';

/// Adds up the LLM usage of the question that is running (the Ask page
/// resets it per question and reads it for the line under the answer).
final usageMeterProvider = Provider<UsageMeter>((ref) => UsageMeter());

/// Chat clients per [ReasoningLevel] (R16). All share the configured
/// endpoint and model and rebuild whenever the API config changes.
///
/// Every role runs at [ReasoningLevel.off] by default: routing, planning,
/// note extraction and disambiguation are mechanical, and the answer writer
/// works from text that was already retrieved (high effort over-interpreted
/// the story). The "深度思考" switch moves only the writer to
/// [ReasoningLevel.low]; nothing uses [ReasoningLevel.high].
final llmClientProvider =
    Provider.family<LLMClient, ReasoningLevel>((ref, level) {
  final meter = ref.read(usageMeterProvider);
  final client = OpenAICompatibleClient(
    config: ref.watch(apiConfigProvider),
    reasoning: level,
    // Every call of every client adds to the one meter of the running
    // question (tokens, calls, time shown under the answer).
    onCompletion: meter.add,
  );
  ref.onDispose(client.dispose);
  return client;
});

/// Whether the answer writer may think ([ReasoningLevel.low]); off by
/// default, toggled from the Ask input row.
final deepThinkingProvider = StateProvider<bool>((ref) => false);

/// Embedding client for vector recall (R12); null when no key is set, in
/// which case `FIND` runs keyword-only.
final embeddingClientProvider = Provider<EmbeddingClient?>((ref) {
  final config = ref.watch(embeddingConfigProvider);
  if (!config.isValid) return null;
  final client = OpenAICompatibleEmbeddingClient(config: config);
  ref.onDispose(client.dispose);
  return client;
});
