import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/llm/embedding_profile.dart';
import '../../shared/providers/settings_provider.dart';
import 'api_embedding_client.dart';
import 'embedder.dart';
import 'embedding_client.dart';
import 'local_embedding/builtin_embedding_client.dart';
import 'local_embedding/builtin_embedding_model.dart';

/// Provider for the [Embedder] service.
///
/// Depends on the [llmClientProvider] — when the API config changes,
/// the LLM client is rebuilt, and consequently the embedder picks up
/// the new config automatically.
final embeddingClientProvider = Provider<EmbeddingClient>((ref) {
  final settings = ref.watch(embeddingSettingsProvider);
  final active = settings.activeProfile;

  if (active == null) {
    throw StateError('No active embedding profile configured.');
  }

  switch (active.backend) {
    case EmbeddingBackend.api:
      final client = ApiEmbeddingClient(
        config: active.toEmbeddingConfig(),
        providerId: active.id,
      );
      ref.onDispose(client.dispose);
      return client;
    case EmbeddingBackend.builtin:
      final client = LazyBuiltinEmbeddingClient(
        providerId: active.id,
        dimension: active.dimension > 0
            ? active.dimension
            : BuiltinEmbeddingModel.expectedDimension,
      );
      ref.onDispose(client.dispose);
      return client;
  }
});

final embedderProvider = Provider<Embedder>((ref) {
  final client = ref.watch(embeddingClientProvider);
  return Embedder(client);
});
