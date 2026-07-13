import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/llm/llm_client.dart';
import '../../features/settings/settings_service.dart';

/// Provider for the [SettingsService] singleton.
final settingsServiceProvider = Provider<SettingsService>((ref) {
  return SettingsService();
});

/// Pre-loaded providers overridden in main()
final onboardingDoneProvider = Provider<bool>((ref) => throw UnimplementedError());
final initialApiConfigProvider = Provider<LLMConfig>((ref) => throw UnimplementedError());

/// Active state for onboarding status.
final onboardingStatusProvider = StateProvider<bool>((ref) {
  return ref.watch(onboardingDoneProvider);
});

/// Notifier that holds the current [LLMConfig] and persists changes
/// to secure storage.
class ApiConfigNotifier extends StateNotifier<LLMConfig> {
  final SettingsService _service;

  ApiConfigNotifier(this._service, LLMConfig initial) : super(initial);

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
  final initial = ref.watch(initialApiConfigProvider);
  return ApiConfigNotifier(service, initial);
});
