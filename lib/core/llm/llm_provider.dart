import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/providers/settings_provider.dart';
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
