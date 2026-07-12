import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/llm/llm_client.dart';
import '../../features/settings/settings_service.dart';

/// Provider for the [SettingsService] singleton.
final settingsServiceProvider = Provider<SettingsService>((ref) {
  return SettingsService();
});

/// Notifier that holds the current [LLMConfig] and persists changes
/// to secure storage.
class ApiConfigNotifier extends StateNotifier<LLMConfig> {
  final SettingsService _service;

  ApiConfigNotifier(this._service) : super(const LLMConfig());

  /// Loads the config from secure storage (call once at startup).
  Future<void> load() async {
    state = await _service.loadApiConfig();
  }

  /// Saves a new config and updates state.
  Future<void> save(LLMConfig config) async {
    await _service.saveApiConfig(config);
    state = config;
  }

  /// Updates a single field without saving to storage.
  /// Use [save] to persist.
  void updateField(LLMConfig Function(LLMConfig) updater) {
    state = updater(state);
  }
}

/// Provider for the API configuration state.
///
/// Loads from secure storage on first access. UI components watch this
/// to react to config changes (e.g. LLM client rebuild).
final apiConfigProvider =
    StateNotifierProvider<ApiConfigNotifier, LLMConfig>((ref) {
  final service = ref.watch(settingsServiceProvider);
  return ApiConfigNotifier(service);
});

/// Future provider that resolves once the initial config is loaded.
/// Use this to gate startup flows (show loading or skip).
final apiConfigLoadFuture = FutureProvider<void>((ref) async {
  final notifier = ref.read(apiConfigProvider.notifier);
  await notifier.load();
});
