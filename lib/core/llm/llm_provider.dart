import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/providers/settings_provider.dart';
import 'embedding_client.dart';
import 'llm_client.dart';
import 'openai_client.dart';

/// Provider that creates and manages an [LLMClient] instance.
///
/// Rebuilds whenever the API config changes, so all downstream
/// consumers automatically use the new configuration.
final llmClientProvider = Provider<LLMClient>((ref) {
  final config = ref.watch(apiConfigProvider);

  final client = OpenAICompatibleClient(config: config);

  // Dispose the client when the provider is disposed.
  ref.onDispose(() => client.dispose());

  return client;
});

/// Same endpoint/model as [llmClientProvider] but asking hybrid reasoning
/// models to skip hidden reasoning (R12 cost control) — for mechanical roles
/// (evidence extraction, candidate picking, per-step intents).
final auxLlmClientProvider = Provider<LLMClient>((ref) {
  final client = OpenAICompatibleClient(
    config: ref.watch(apiConfigProvider),
    reasoning: false,
  );
  ref.onDispose(client.dispose);
  return client;
});

/// Embedding client for vector recall (R12); null when no key is set, in
/// which case `FIND` runs keyword-only.
final embeddingClientProvider = Provider<EmbeddingClient?>((ref) {
  final config = ref.watch(embeddingConfigProvider);
  if (!config.isValid) return null;
  final client = OpenAICompatibleEmbeddingClient(config: config);
  ref.onDispose(client.dispose);
  return client;
});
