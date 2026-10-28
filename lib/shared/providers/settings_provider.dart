import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/agent/answer_options.dart';
import '../../core/library/story_art.dart';
import '../../core/llm/embedding_client.dart';
import '../../core/llm/llm_client.dart';
import '../../core/llm/token_prices.dart';
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
final initialMainTabIndexProvider =
    Provider<int>((ref) => throw UnimplementedError());
final initialSessionLogsEnabledProvider =
    Provider<bool>((ref) => throw UnimplementedError());

final wikiSourcesRevisionProvider = StateProvider<int>((ref) => 0);

/// The reader's form of address, loaded at startup (empty by default).
final initialNicknameProvider = Provider<String>((ref) => '');

/// What the stories call the reader in place of {@nickname} (see
/// withPlaceholders); set in Settings → Profile.
final nicknameProvider = StateProvider<String>((ref) {
  return ref.watch(initialNicknameProvider);
});

/// Whether the parts of an operator's file open unfolded, loaded at startup.
final initialProfileSectionsOpenProvider = Provider<bool>((ref) => true);

/// Whether the parts of an operator's file in the library ([ProfileText])
/// open unfolded (on) or all folded; set in Settings.
final profileSectionsOpenProvider = StateProvider<bool>((ref) {
  return ref.watch(initialProfileSectionsOpenProvider);
});

/// Whether an unread open stays out of the history, loaded at startup.
final initialSkipUnreadOpensProvider = Provider<bool>((ref) => true);

/// Whether a story opened and left without the reading position moving
/// from where it opened is kept out of the reading history (the reader
/// records the visit only once it moves). Set in Settings, default on.
final skipUnreadOpensProvider = StateProvider<bool>((ref) {
  return ref.watch(initialSkipUnreadOpensProvider);
});

/// Whether answers leave operators' names plain, loaded at startup.
final initialSkipOperatorNamesProvider = Provider<bool>((ref) => false);

/// Whether answers leave operators' names plain (players know them); other
/// highlighted names keep their link. Set in Settings, default off.
final skipOperatorNamesProvider = StateProvider<bool>((ref) {
  return ref.watch(initialSkipOperatorNamesProvider);
});

/// Whether the user enabled per-session AI logs (default on; applied to
/// [AgentLogger] at startup and on toggle in Settings).
final sessionLogsEnabledProvider = StateProvider<bool>((ref) {
  return ref.watch(initialSessionLogsEnabledProvider);
});

/// The Ask answer options loaded at startup; overridden in main().
final initialAnswerOptionsProvider =
    Provider<AnswerOptions>((ref) => const AnswerOptions());

/// The Ask answer options (wikis, sub-agents), saved on change.
class AnswerOptionsNotifier extends StateNotifier<AnswerOptions> {
  AnswerOptionsNotifier(this._service, AnswerOptions initial) : super(initial);
  final SettingsService _service;

  Future<void> set(AnswerOptions options) async {
    state = options;
    await _service.saveAnswerOptions(options);
  }
}

final answerOptionsProvider =
    StateNotifierProvider<AnswerOptionsNotifier, AnswerOptions>((ref) {
  return AnswerOptionsNotifier(
    ref.watch(settingsServiceProvider),
    ref.watch(initialAnswerOptionsProvider),
  );
});

/// Active state for onboarding status.
final onboardingStatusProvider = StateProvider<bool>((ref) {
  return ref.watch(onboardingDoneProvider);
});

/// Notifier that holds the current [LLMConfig] and persists changes
/// to secure storage.
class ApiConfigNotifier extends StateNotifier<LLMConfig> {

  ApiConfigNotifier(this._service, LLMConfig initial) : super(initial);
  final SettingsService _service;

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

/// Embedding endpoint loaded at startup (R12); overridden in main().
final initialEmbeddingConfigProvider =
    Provider<EmbeddingConfig>((ref) => defaultEmbeddingConfig);

/// Holds the embedding config and persists changes to secure storage.
class EmbeddingConfigNotifier extends StateNotifier<EmbeddingConfig> {
  EmbeddingConfigNotifier(this._service, EmbeddingConfig initial)
      : super(initial);
  final SettingsService _service;

  Future<void> save(EmbeddingConfig config) async {
    await _service.saveEmbeddingConfig(config);
    state = config;
  }
}

final embeddingConfigProvider =
    StateNotifierProvider<EmbeddingConfigNotifier, EmbeddingConfig>((ref) {
  return EmbeddingConfigNotifier(
    ref.watch(settingsServiceProvider),
    ref.watch(initialEmbeddingConfigProvider),
  );
});

/// Loads the optional GitHub Personal Access Token from secure storage.
///
/// Used by the in-app GameData builder; invalidated after save/clear.
final githubTokenProvider = FutureProvider<String>((ref) async {
  return ref.watch(settingsServiceProvider).loadGithubToken();
});

final initialContextWarnTokensProvider = Provider<int>((ref) => defaultContextWarnTokens);

class ContextWarnTokensNotifier extends StateNotifier<int> {
  ContextWarnTokensNotifier(this._service, int initial) : super(initial);
  final SettingsService _service;

  Future<void> set(int value) async {
    state = value;
    await _service.saveContextWarnTokens(value);
  }
}

final contextWarnTokensProvider =
    StateNotifierProvider<ContextWarnTokensNotifier, int>(
  (ref) => ContextWarnTokensNotifier(
    ref.watch(settingsServiceProvider),
    ref.watch(initialContextWarnTokensProvider),
  ),
);

final initialCompactPercentProvider =
    Provider<int>((ref) => defaultCompactPercent);

class CompactPercentNotifier extends StateNotifier<int> {
  CompactPercentNotifier(this._service, int initial) : super(initial);
  final SettingsService _service;

  Future<void> set(int value) async {
    state = value;
    await _service.saveCompactPercent(value);
  }
}

final compactPercentProvider =
    StateNotifierProvider<CompactPercentNotifier, int>(
  (ref) => CompactPercentNotifier(
    ref.watch(settingsServiceProvider),
    ref.watch(initialCompactPercentProvider),
  ),
);

final initialTokenPricesProvider =
    Provider<TokenPrices>((ref) => const TokenPrices());

class TokenPricesNotifier extends StateNotifier<TokenPrices> {
  TokenPricesNotifier(this._service, TokenPrices initial) : super(initial);
  final SettingsService _service;

  Future<void> set(TokenPrices value) async {
    if (value == state) return;
    state = value;
    await _service.saveTokenPrices(value);
  }
}

/// The prices the cost under each answer is worked out from.
final tokenPricesProvider =
    StateNotifierProvider<TokenPricesNotifier, TokenPrices>(
  (ref) => TokenPricesNotifier(
    ref.watch(settingsServiceProvider),
    ref.watch(initialTokenPricesProvider),
  ),
);

final initialStoryArtModeProvider =
    Provider<StoryArtMode>((ref) => StoryArtMode.images);

class StoryArtModeNotifier extends StateNotifier<StoryArtMode> {
  StoryArtModeNotifier(this._service, StoryArtMode initial) : super(initial);
  final SettingsService _service;

  Future<void> set(StoryArtMode value) async {
    state = value;
    await _service.saveStoryArtMode(value);
  }
}

final storyArtModeProvider =
    StateNotifierProvider<StoryArtModeNotifier, StoryArtMode>(
  (ref) => StoryArtModeNotifier(
    ref.watch(settingsServiceProvider),
    ref.watch(initialStoryArtModeProvider),
  ),
);
