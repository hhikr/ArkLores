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
  static const _keyMainTabIndex = 'main_tab_index';
  static const _keyWikiTabIndex = 'wiki_tab_index';
  static const _keyWikiUrlPrefix = 'wiki_url_';
  static const _keyWikiReaderMode = 'wiki_reader_mode';
  static const _keyWikiReaderFontScale = 'wiki_reader_font_scale';

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

  Future<int> loadMainTabIndex() async {
    return _loadBoundedInt(_keyMainTabIndex, min: 0, max: 3);
  }

  Future<void> saveMainTabIndex(int index) async {
    await _storage.write(key: _keyMainTabIndex, value: '$index');
  }

  Future<int> loadWikiTabIndex() async {
    return _loadBoundedInt(_keyWikiTabIndex, min: 0, max: 1);
  }

  Future<void> saveWikiTabIndex(int index) async {
    await _storage.write(key: _keyWikiTabIndex, value: '$index');
  }

  Future<String?> loadWikiUrl(int index) async {
    final value = await _storage.read(key: '$_keyWikiUrlPrefix$index');
    final uri = value == null ? null : Uri.tryParse(value);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) return null;
    return value;
  }

  Future<void> saveWikiUrl(int index, String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) return;
    await _storage.write(key: '$_keyWikiUrlPrefix$index', value: url);
  }

  Future<bool> loadWikiReaderMode() async {
    final value = await _storage.read(key: _keyWikiReaderMode);
    return value == 'true';
  }

  Future<void> saveWikiReaderMode(bool enabled) async {
    await _storage.write(key: _keyWikiReaderMode, value: '$enabled');
  }

  Future<double> loadWikiReaderFontScale() async {
    final raw = await _storage.read(key: _keyWikiReaderFontScale);
    final value = double.tryParse(raw ?? '');
    if (value == null || value < 0.62 || value > 1.38) return 1.0;
    return value;
  }

  Future<void> saveWikiReaderFontScale(double scale) async {
    final value = scale.clamp(0.62, 1.38).toStringAsFixed(2);
    await _storage.write(key: _keyWikiReaderFontScale, value: value);
  }

  Future<int> _loadBoundedInt(
    String key, {
    required int min,
    required int max,
  }) async {
    final value = int.tryParse(await _storage.read(key: key) ?? '');
    if (value == null || value < min || value > max) return min;
    return value;
  }
}
