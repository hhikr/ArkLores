import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/llm/llm_client.dart';

/// Persistent storage for API configuration via flutter_secure_storage.
///
/// Keys are stored encrypted at the OS level (Keychain on iOS,
/// EncryptedSharedPreferences on Android).
///
/// Chat and Embedding configs are stored separately so users can
/// mix providers (e.g. DeepSeek for chat, OpenAI for embeddings).
class SettingsService {
  // ── Chat keys ────────────────────────────────────────────
  static const _keyChatBaseUrl = 'chat_base_url';
  static const _keyChatApiKey = 'chat_api_key';
  static const _keyChatModel = 'chat_model';

  // ── Embedding keys ───────────────────────────────────────
  static const _keyEmbedBaseUrl = 'embed_base_url';
  static const _keyEmbedApiKey = 'embed_api_key';
  static const _keyEmbedModel = 'embed_model';

  // ── App state keys ───────────────────────────────────────
  static const _keyOnboardingDone = 'onboarding_done';

  final FlutterSecureStorage _storage;

  SettingsService({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  /// Loads the saved API configuration.
  Future<LLMConfig> loadApiConfig() async {
    final chatBaseUrl = await _storage.read(key: _keyChatBaseUrl);
    final chatApiKey = await _storage.read(key: _keyChatApiKey);
    final chatModel = await _storage.read(key: _keyChatModel);
    final embedBaseUrl = await _storage.read(key: _keyEmbedBaseUrl);
    final embedApiKey = await _storage.read(key: _keyEmbedApiKey);
    final embedModel = await _storage.read(key: _keyEmbedModel);

    return LLMConfig(
      chatBaseUrl: chatBaseUrl ?? 'https://api.deepseek.com/v1',
      chatApiKey: chatApiKey ?? '',
      chatModel: chatModel ?? 'deepseek-v4-flash',
      embedBaseUrl: embedBaseUrl ?? 'https://api.openai.com/v1',
      embedApiKey: embedApiKey ?? '',
      embedModel: embedModel ?? 'text-embedding-3-small',
    );
  }

  /// Saves the API configuration.
  Future<void> saveApiConfig(LLMConfig config) async {
    await Future.wait([
      _storage.write(key: _keyChatBaseUrl, value: config.chatBaseUrl),
      _storage.write(key: _keyChatApiKey, value: config.chatApiKey),
      _storage.write(key: _keyChatModel, value: config.chatModel),
      _storage.write(key: _keyEmbedBaseUrl, value: config.embedBaseUrl),
      _storage.write(key: _keyEmbedApiKey, value: config.embedApiKey),
      _storage.write(key: _keyEmbedModel, value: config.embedModel),
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
