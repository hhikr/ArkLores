import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/llm/embedding_profile.dart';
import '../../core/llm/llm_client.dart';
import '../../features/settings/settings_service.dart';

/// Provider for the [SettingsService] singleton.
final settingsServiceProvider = Provider<SettingsService>((ref) {
  return SettingsService();
});

/// Pre-loaded providers overridden in main()
final onboardingDoneProvider =
    Provider<bool>((ref) => throw UnimplementedError());
final initialApiConfigProvider =
    Provider<LLMConfig>((ref) => throw UnimplementedError());
final initialEmbeddingSettingsProvider = Provider<EmbeddingSettingsState>(
  (ref) => throw UnimplementedError(),
);

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

class EmbeddingSettingsNotifier extends StateNotifier<EmbeddingSettingsState> {
  final SettingsService _service;

  EmbeddingSettingsNotifier(this._service, EmbeddingSettingsState initial)
      : super(initial);

  Future<void> upsertProfile(EmbeddingProfile profile,
      {bool activate = true}) async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final profiles = [...state.profiles];
    final existingIndex = profiles.indexWhere(
      (p) => p.id == profile.id || p.matchKey == profile.matchKey,
    );

    late final EmbeddingProfile savedProfile;
    if (existingIndex >= 0) {
      final existing = profiles[existingIndex];
      savedProfile = profile.copyWith(
        id: existing.id,
        createdAt: existing.createdAt,
        updatedAt: now,
        dimension:
            profile.dimension > 0 ? profile.dimension : existing.dimension,
      );
      profiles[existingIndex] = savedProfile;
    } else {
      savedProfile = profile.copyWith(updatedAt: now);
      profiles.add(savedProfile);
    }

    final next = EmbeddingSettingsState(
      profiles: profiles,
      activeProfileId: activate ? savedProfile.id : state.activeProfileId,
    );
    await _service.saveEmbeddingSettings(next);
    state = next;
  }

  Future<void> activateProfile(String profileId) async {
    if (!state.profiles.any((p) => p.id == profileId)) return;
    final next = state.withActiveProfileId(profileId);
    await _service.saveEmbeddingSettings(next);
    state = next;
  }

  Future<void> updateActiveProfileDimension(int dimension) async {
    if (dimension <= 0) return;
    final active = state.activeProfile;
    if (active == null || active.dimension == dimension) return;

    final profiles = [
      for (final profile in state.profiles)
        if (profile.id == active.id)
          profile.copyWith(
            dimension: dimension,
            updatedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
          )
        else
          profile,
    ];
    final next = state.copyWith(profiles: profiles);
    await _service.saveEmbeddingSettings(next);
    state = next;
  }

  Future<void> deleteProfile(String profileId) async {
    final profiles = state.profiles.where((p) => p.id != profileId).toList();
    final nextActive = state.activeProfileId == profileId
        ? (profiles.isNotEmpty ? profiles.first.id : null)
        : state.activeProfileId;
    final next = EmbeddingSettingsState(
      profiles: profiles,
      activeProfileId: nextActive,
    );
    await _service.saveEmbeddingSettings(next);
    state = next;
  }
}

final embeddingSettingsProvider =
    StateNotifierProvider<EmbeddingSettingsNotifier, EmbeddingSettingsState>(
        (ref) {
  final service = ref.watch(settingsServiceProvider);
  final initial = ref.watch(initialEmbeddingSettingsProvider);
  return EmbeddingSettingsNotifier(service, initial);
});
