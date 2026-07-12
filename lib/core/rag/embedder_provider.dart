import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/llm/llm_provider.dart';
import 'embedder.dart';

/// Provider for the [Embedder] service.
///
/// Depends on the [llmClientProvider] — when the API config changes,
/// the LLM client is rebuilt, and consequently the embedder picks up
/// the new config automatically.
final embedderProvider = Provider<Embedder>((ref) {
  final client = ref.watch(llmClientProvider);
  return Embedder(client);
});
