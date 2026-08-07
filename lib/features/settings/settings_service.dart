import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/llm/llm_client.dart';

enum AppLauncherIcon {
  light('light'),
  dark('dark');

  const AppLauncherIcon(this.storageValue);

  final String storageValue;

  static AppLauncherIcon fromStorage(String? value) {
    return AppLauncherIcon.values.firstWhere(
      (icon) => icon.storageValue == value,
      orElse: () => AppLauncherIcon.light,
    );
  }
}

class WikiSiteConfig {
  const WikiSiteConfig({
    required this.id,
    required this.label,
    required this.url,
    this.iconUrl,
    this.builtIn = false,
  });

  final String id;
  final String label;
  final String url;
  final String? iconUrl;
  final bool builtIn;

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'url': url,
        'iconUrl': iconUrl,
        'builtIn': builtIn,
      };

  static WikiSiteConfig? fromJson(Object? value) {
    if (value is! Map<String, dynamic>) return null;
    final id = value['id']?.toString().trim() ?? '';
    final label = value['label']?.toString().trim() ?? '';
    final url = value['url']?.toString().trim() ?? '';
    final iconUrl = value['iconUrl']?.toString().trim();
    final uri = Uri.tryParse(url);
    if (id.isEmpty || label.isEmpty || uri == null || !uri.hasScheme) {
      return null;
    }
    if (uri.host.isEmpty) return null;
    return WikiSiteConfig(
      id: id,
      label: label,
      url: url,
      iconUrl: iconUrl == null || iconUrl.isEmpty ? null : iconUrl,
      builtIn: value['builtIn'] == true,
    );
  }
}

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
  static const _keyWikiSources = 'wiki_sources';
  static const _keyWikiReaderMode = 'wiki_reader_mode';
  static const _keyWikiReaderFontScale = 'wiki_reader_font_scale';
  static const _keyWikiDarkMode = 'wiki_dark_mode';
  static const _keyAppLauncherIcon = 'app_launcher_icon';

  static const defaultWikiSites = [
    WikiSiteConfig(
      id: 'prts',
      label: 'PRTS Wiki',
      url: 'https://prts.wiki',
      iconUrl: 'https://prts.wiki/favicon.ico',
      builtIn: true,
    ),
    WikiSiteConfig(
      id: 'endfield-warfarin',
      label: '终末地 Wiki · Warfarin',
      url: 'https://warfarin.wiki/cn',
      iconUrl: 'https://warfarin.wiki/icon.png',
      builtIn: true,
    ),
    WikiSiteConfig(
      id: 'endfield-fz',
      label: '终末地 Wiki · fz',
      url: 'https://fz.wiki',
      iconUrl: 'https://fz.wiki/icon.svg',
      builtIn: true,
    ),
  ];

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
    return _loadBoundedInt(_keyWikiTabIndex, min: 0, max: 999);
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

  Future<List<WikiSiteConfig>> loadWikiSites() async {
    final raw = await _storage.read(key: _keyWikiSources);
    if (raw != null && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          final sites = decoded
              .map(WikiSiteConfig.fromJson)
              .whereType<WikiSiteConfig>()
              .map(_migrateWikiSite)
              .toList();
          if (sites.isNotEmpty) {
            final hasFz = sites.any((site) => site.id == 'endfield-fz');
            if (!hasFz) {
              sites.add(defaultWikiSites.last);
              await _storage.write(
                key: _keyWikiSources,
                value: jsonEncode(
                  sites.map((site) => site.toJson()).toList(),
                ),
              );
            }
            return sites;
          }
        }
      } catch (_) {
        // Fall through to defaults.
      }
    }

    final migrated = <WikiSiteConfig>[];
    for (var i = 0; i < defaultWikiSites.length; i++) {
      final site = defaultWikiSites[i];
      migrated.add(
        WikiSiteConfig(
          id: site.id,
          label: site.label,
          url: await loadWikiUrl(i) ?? site.url,
          iconUrl: site.iconUrl,
          builtIn: true,
        ),
      );
    }
    return migrated;
  }

  static WikiSiteConfig _migrateWikiSite(WikiSiteConfig site) {
    if (site.builtIn &&
        site.id == 'endfield' &&
        site.url.contains('warfarin.wiki')) {
      return WikiSiteConfig(
        id: 'endfield-warfarin',
        label: '终末地 Wiki · Warfarin',
        url: site.url,
        iconUrl: site.iconUrl ?? 'https://warfarin.wiki/icon.png',
        builtIn: true,
      );
    }
    return site;
  }

  Future<void> saveWikiSites(List<WikiSiteConfig> sites) async {
    final previous = await loadWikiSites();
    final sanitized = sites
        .map((site) => WikiSiteConfig.fromJson(site.toJson()))
        .whereType<WikiSiteConfig>()
        .toList();
    if (sanitized.isEmpty) return;
    await _storage.write(
      key: _keyWikiSources,
      value: jsonEncode(sanitized.map((site) => site.toJson()).toList()),
    );
    await Future.wait([
      for (var i = 0; i < sanitized.length; i++)
        if (i >= previous.length || sanitized[i].url != previous[i].url)
          _storage.delete(key: '$_keyWikiUrlPrefix$i'),
    ]);
  }

  Future<void> resetWikiSites() async {
    await _storage.delete(key: _keyWikiSources);
    await Future.wait([
      for (var i = 0; i < 20; i++) _storage.delete(key: '$_keyWikiUrlPrefix$i'),
    ]);
  }

  Future<AppLauncherIcon> loadAppLauncherIcon() async {
    return AppLauncherIcon.fromStorage(
      await _storage.read(key: _keyAppLauncherIcon),
    );
  }

  Future<void> saveAppLauncherIcon(AppLauncherIcon icon) async {
    await _storage.write(
      key: _keyAppLauncherIcon,
      value: icon.storageValue,
    );
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

  Future<bool?> loadWikiDarkMode() async {
    final value = await _storage.read(key: _keyWikiDarkMode);
    if (value == null) return null;
    if (value == 'true') return true;
    if (value == 'false') return false;
    return null;
  }

  Future<void> saveWikiDarkMode(bool enabled) async {
    await _storage.write(key: _keyWikiDarkMode, value: '$enabled');
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
