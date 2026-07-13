import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/providers/settings_provider.dart';
import 'vector_store.dart';

/// Singleton provider for the [VectorStore] instance.
///
/// The vector store is initialized lazily on first database operation.
/// Call `ref.read(vectorStoreProvider).initialize()` explicitly if eager
/// init is desired (e.g. at app startup).
final vectorStoreProvider = Provider<VectorStore>((ref) {
  final store = VectorStore();
  ref.onDispose(() => store.dispose());
  return store;
});

/// Future provider that resolves when the vector store is initialized.
/// Use this to gate UI behind a loading state while the DB initializes.
final vectorStoreInitProvider = FutureProvider<void>((ref) async {
  final store = ref.read(vectorStoreProvider);
  await store.initialize();
});

/// Provider for knowledge base statistics.
final vectorStoreStatsProvider = FutureProvider<VectorStoreStats>((ref) async {
  final store = ref.read(vectorStoreProvider);
  final profileId = ref.watch(embeddingSettingsProvider).activeProfile?.id;
  return await store.getStats(profileId: profileId);
});
