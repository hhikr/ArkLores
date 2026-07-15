import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/llm/llm_client.dart';

/// Persistent storage for API configuration via flutter_secure_storage.
///
/// Keys are stored encrypted at the OS level (Keychain on iOS,
/// EncryptedSharedPreferences on Android).
///
class SettingsService {
  // ── Chat keys ────────────────────────────────────────────
  static const _keyChatBaseUrl = 'chat_base_url';
  static const _keyChatApiKey = 'chat_api_key';
  static const _keyChatModel = 'chat_model';

  // ── App state keys ───────────────────────────────────────
  static const _keyOnboardingDone = 'onboarding_done';

  final FlutterSecureStorage _storage;

  SettingsService({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(
                encryptedSharedPreferences: true,
              ),
            );

  /// Loads the saved API configuration.
  Future<LLMConfig> loadApiConfig() async {
    final chatBaseUrl = await _storage.read(key: _keyChatBaseUrl);
    final chatApiKey = await _storage.read(key: _keyChatApiKey);
    final chatModel = await _storage.read(key: _keyChatModel);

    return LLMConfig(
      chatBaseUrl: chatBaseUrl ?? 'https://api.deepseek.com/v1',
      chatApiKey: chatApiKey ?? '',
      chatModel: chatModel ?? 'deepseek-v4-flash',
    );
  }

  /// Saves the API configuration.
  Future<void> saveApiConfig(LLMConfig config) async {
    await Future.wait([
      _storage.write(key: _keyChatBaseUrl, value: config.chatBaseUrl),
      _storage.write(key: _keyChatApiKey, value: config.chatApiKey),
      _storage.write(key: _keyChatModel, value: config.chatModel),
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
