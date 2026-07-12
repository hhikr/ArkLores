import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/llm/llm_client.dart';

/// Persistent storage for API configuration via flutter_secure_storage.
///
/// Keys are stored encrypted at the OS level (Keychain on iOS,
/// EncryptedSharedPreferences on Android).
class SettingsService {
  static const _keyBaseUrl = 'api_base_url';
  static const _keyApiKey = 'api_key';
  static const _keyChatModel = 'api_chat_model';
  static const _keyEmbeddingModel = 'api_embedding_model';
  static const _keyOnboardingDone = 'onboarding_done';

  final FlutterSecureStorage _storage;

  SettingsService({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  /// Loads the saved API configuration.
  Future<LLMConfig> loadApiConfig() async {
    final baseUrl = await _storage.read(key: _keyBaseUrl);
    final apiKey = await _storage.read(key: _keyApiKey);
    final chatModel = await _storage.read(key: _keyChatModel);
    final embeddingModel = await _storage.read(key: _keyEmbeddingModel);

    return LLMConfig(
      baseUrl: baseUrl ?? 'https://api.openai.com/v1',
      apiKey: apiKey ?? '',
      chatModel: chatModel ?? 'gpt-4o-mini',
      embeddingModel: embeddingModel ?? 'text-embedding-3-small',
    );
  }

  /// Saves the API configuration.
  Future<void> saveApiConfig(LLMConfig config) async {
    await Future.wait([
      _storage.write(key: _keyBaseUrl, value: config.baseUrl),
      _storage.write(key: _keyApiKey, value: config.apiKey),
      _storage.write(key: _keyChatModel, value: config.chatModel),
      _storage.write(key: _keyEmbeddingModel, value: config.embeddingModel),
    ]);
  }

  /// Returns `true` if onboarding has been completed.
  Future<bool> isOnboardingDone() async {
    final value = await _storage.read(key: _keyOnboardingDone);
    return value == 'true';
  }

  /// Marks onboarding as completed.
  Future<void> markOnboardingDone() async {
    await _storage.write(key: _keyOnboardingDone, value: 'true');
  }
}
