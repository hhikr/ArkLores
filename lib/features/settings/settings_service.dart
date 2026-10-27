import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/agent/answer_options.dart';
import '../../core/llm/embedding_client.dart';
import '../../core/llm/llm_client.dart';
import '../../core/llm/token_prices.dart';
import '../../shared/l10n/locale_provider.dart';
import '../../shared/providers/theme_provider.dart';

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

/// The context warning when none was saved; Ask compacts at 80% of it.
/// Long-context models compact poorly, so the default is the largest
/// option and a conversation compacts only when it gets very long.
const defaultContextWarnTokens = 1000000;

/// The share of the context warning, in percent, at which Ask compacts.
const defaultCompactPercent = 80;

/// Persistent storage for API configuration via flutter_secure_storage.
///
/// Keys are stored encrypted at the OS level (Keychain on iOS,
/// EncryptedSharedPreferences on Android).
///
class SettingsService {

  SettingsService({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(
                encryptedSharedPreferences: true,
              ),
            );
  // ── Chat keys ────────────────────────────────────────────
  static const _keyChatBaseUrl = 'chat_base_url';
  static const _keyChatApiKey = 'chat_api_key';
  static const _keyChatModel = 'chat_model';

  // ── Embedding keys (R12 vector recall) ───────────────────
  static const _keyEmbeddingBaseUrl = 'embedding_base_url';
  static const _keyEmbeddingApiKey = 'embedding_api_key';
  static const _keyEmbeddingModel = 'embedding_model';
  static const _keyEmbeddingDims = 'embedding_dims';

  // ── GitHub keys ──────────────────────────────────────────
  static const _keyGithubToken = 'github_token';

  // ── Agent session log keys ──────────────────────────────
  static const _keySessionLogsEnabled = 'session_logs_enabled';
  static const _keyAnswerOptions = 'ask_answer_options';
  static const _keyProfileSectionsOpen = 'library_profile_sections_open';
  static const _keySkipOperatorNames = 'ask_skip_operator_names';
  static const _keyNameLinks = 'ask_name_links';
  static const _keyBlockedNames = 'ask_blocked_names';
  static const _keySkipUnreadOpens = 'library_skip_unread_opens';
  static const _keyReadingFont = 'reading_font';
  static const _keyContextWarnTokens = 'ask_context_warn_tokens';
  static const _keyCompactPercent = 'ask_compact_percent';
  static const _keyTokenPrices = 'ask_token_prices';

  // ── Profile keys ─────────────────────────────────────────
  static const _keyNickname = 'profile_nickname';

  // ── App state keys ───────────────────────────────────────
  static const _keyOnboardingDone = 'onboarding_done';
  static const _keyBackgroundExplained = 'background_explained';
  static const _keyMainTabIndex = 'main_tab_index';
  static const _keyWikiTabIndex = 'wiki_tab_index';
  static const _keyWikiUrlPrefix = 'wiki_url_';
  static const _keyWikiAppliedUrlPrefix = 'wiki_applied_url_';
  static const _keyWikiSources = 'wiki_sources';
  static const _keyWikiDarkMode = 'wiki_dark_mode';
  static const _keyAutoUpdateCheck = 'auto_update_check';
  static const _keyLastUpdateCheck = 'last_update_check';

  // ── Appearance keys ──────────────────────────────────────
  static const _keyTheme = 'theme';
  static const _keyLocale = 'locale';

  static const defaultWikiSites = [
    WikiSiteConfig(
      id: 'prts',
      label: 'PRTS Wiki',
      url: 'https://prts.wiki',
      iconUrl: 'https://prts.wiki/favicon.ico',
      builtIn: true,
    ),
    WikiSiteConfig(
      id: 'endfield',
      label: 'Endfield Wiki',
      url: 'https://warfarin.wiki/cn',
      iconUrl: 'https://warfarin.wiki/icon.png',
      builtIn: true,
    ),
  ];

  final FlutterSecureStorage _storage;

  /// Loads the saved API configuration.
  Future<LLMConfig> loadApiConfig() async {
    final (chatBaseUrl, chatApiKey, chatModel) = await (
      _storage.read(key: _keyChatBaseUrl),
      _storage.read(key: _keyChatApiKey),
      _storage.read(key: _keyChatModel),
    ).wait;

    return LLMConfig(
      chatBaseUrl: chatBaseUrl ?? 'https://api.z.ai/api/paas/v4',
      chatApiKey: chatApiKey ?? '',
      chatModel: chatModel ?? 'glm-5.3-flash',
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

  /// Loads the optional embedding endpoint (R12). Unset key -> vector recall
  /// stays off and `FIND` uses keyword search only.
  Future<EmbeddingConfig> loadEmbeddingConfig() async {
    final (baseUrl, apiKey, model, dims) = await (
      _storage.read(key: _keyEmbeddingBaseUrl),
      _storage.read(key: _keyEmbeddingApiKey),
      _storage.read(key: _keyEmbeddingModel),
      _storage.read(key: _keyEmbeddingDims),
    ).wait;
    return EmbeddingConfig(
      baseUrl: baseUrl ?? defaultEmbeddingConfig.baseUrl,
      apiKey: apiKey ?? '',
      model: model ?? defaultEmbeddingConfig.model,
      dimensions: int.tryParse(dims ?? '') ?? defaultEmbeddingConfig.dimensions,
    );
  }

  /// Saves the embedding endpoint configuration.
  Future<void> saveEmbeddingConfig(EmbeddingConfig config) async {
    await Future.wait([
      _storage.write(key: _keyEmbeddingBaseUrl, value: config.baseUrl.trim()),
      _storage.write(key: _keyEmbeddingApiKey, value: config.apiKey.trim()),
      _storage.write(key: _keyEmbeddingModel, value: config.model.trim()),
      _storage.write(key: _keyEmbeddingDims, value: '${config.dimensions}'),
    ]);
  }

  /// Loads the optional GitHub Personal Access Token (empty when unset).
  ///
  /// Used by the in-app GameData builder to authenticate GitHub API calls
  /// (raises the quota from 60 to 5000 requests/hour per account).
  Future<String> loadGithubToken() async {
    return (await _storage.read(key: _keyGithubToken)) ?? '';
  }

  /// Saves (or clears, when [token] is blank) the GitHub token.
  Future<void> saveGithubToken(String token) async {
    final trimmed = token.trim();
    if (trimmed.isEmpty) {
      await _storage.delete(key: _keyGithubToken);
    } else {
      await _storage.write(key: _keyGithubToken, value: trimmed);
    }
  }

  /// How the stories address the reader (empty: the default).
  Future<String> loadNickname() async =>
      (await _storage.read(key: _keyNickname)) ?? '';

  Future<void> saveNickname(String nickname) =>
      _storage.write(key: _keyNickname, value: nickname.trim());

  /// Whether Ask conversations are saved (default on; a saved "off" stays).
  Future<bool> loadSessionLogsEnabled() async {
    return await _storage.read(key: _keySessionLogsEnabled) != 'false';
  }

  /// Persists the per-session AI log toggle.
  Future<void> saveSessionLogsEnabled(bool enabled) async {
    await _storage.write(key: _keySessionLogsEnabled, value: '$enabled');
  }

  /// Whether the parts of an operator's file in the library open unfolded
  /// (default) or all folded.
  Future<bool> loadProfileSectionsOpen() async =>
      await _storage.read(key: _keyProfileSectionsOpen) != 'false';

  Future<void> saveProfileSectionsOpen(bool open) =>
      _storage.write(key: _keyProfileSectionsOpen, value: '$open');

  /// Whether a story opened and left where it opened stays out of the
  /// reading history (default on).
  Future<bool> loadSkipUnreadOpens() async =>
      await _storage.read(key: _keySkipUnreadOpens) != 'false';

  Future<void> saveSkipUnreadOpens(bool skip) =>
      _storage.write(key: _keySkipUnreadOpens, value: '$skip');

  /// Whether an answer leaves operators' names plain (default: off, every
  /// highlighted name is linked to its portrait card).
  Future<bool> loadSkipOperatorNames() async =>
      await _storage.read(key: _keySkipOperatorNames) == 'true';

  Future<void> saveSkipOperatorNames(bool skip) =>
      _storage.write(key: _keySkipOperatorNames, value: '$skip');

  /// Whether names in answers are underlined at all (default on).
  Future<bool> loadNameLinks() async =>
      await _storage.read(key: _keyNameLinks) != 'false';

  Future<void> saveNameLinks(bool on) =>
      _storage.write(key: _keyNameLinks, value: '$on');

  /// Names the reader chose never to underline, in the order added.
  Future<List<String>> loadBlockedNames() async {
    final raw = await _storage.read(key: _keyBlockedNames);
    if (raw == null) return const [];
    try {
      return [for (final name in jsonDecode(raw) as List) '$name'];
    } catch (_) {
      return const [];
    }
  }

  Future<void> saveBlockedNames(List<String> names) =>
      _storage.write(key: _keyBlockedNames, value: jsonEncode(names));

  Future<int> loadContextWarnTokens() async {
    final value =
        int.tryParse(await _storage.read(key: _keyContextWarnTokens) ?? '');
    return value != null && value > 0 ? value : defaultContextWarnTokens;
  }

  Future<void> saveContextWarnTokens(int value) =>
      _storage.write(key: _keyContextWarnTokens, value: '$value');

  Future<int> loadCompactPercent() async {
    final value =
        int.tryParse(await _storage.read(key: _keyCompactPercent) ?? '');
    return value != null && value > 0 && value <= 100
        ? value
        : defaultCompactPercent;
  }

  Future<void> saveCompactPercent(int value) =>
      _storage.write(key: _keyCompactPercent, value: '$value');

  /// The model service's prices for the cost under each answer (none set
  /// by default).
  Future<TokenPrices> loadTokenPrices() async {
    final raw = await _storage.read(key: _keyTokenPrices);
    if (raw == null) return const TokenPrices();
    try {
      return TokenPrices.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw) as Map),
      );
    } catch (_) {
      return const TokenPrices();
    }
  }

  Future<void> saveTokenPrices(TokenPrices prices) => _storage.write(
        key: _keyTokenPrices,
        value: jsonEncode(prices.toJson()),
      );

  /// The font of long reading text (default: the interface's Chinese sans).
  Future<ReadingFont> loadReadingFont() async {
    final value = await _storage.read(key: _keyReadingFont);
    return ReadingFont.values.firstWhere(
      (font) => font.name == value,
      orElse: () => ReadingFont.sans,
    );
  }

  Future<void> saveReadingFont(ReadingFont font) =>
      _storage.write(key: _keyReadingFont, value: font.name);

  /// The Ask answer options (default: the wikis on, sub-agents off).
  Future<AnswerOptions> loadAnswerOptions() async =>
      AnswerOptions.decode(await _storage.read(key: _keyAnswerOptions));

  Future<void> saveAnswerOptions(AnswerOptions options) =>
      _storage.write(key: _keyAnswerOptions, value: options.encode());

  /// Returns `true` if onboarding has been completed.
  Future<bool> isOnboardingDone() async {
    final value = await _storage.read(key: _keyOnboardingDone);
    return value == 'true';
  }

  /// Marks onboarding as completed.
  Future<void> markOnboardingDone() async {
    await _storage.write(key: _keyOnboardingDone, value: 'true');
  }

  /// Whether the reader was told why the app asks to run in the
  /// background (asked once, from Ask or from the onboarding).
  Future<bool> isBackgroundExplained() async =>
      await _storage.read(key: _keyBackgroundExplained) == 'true';

  Future<void> markBackgroundExplained() =>
      _storage.write(key: _keyBackgroundExplained, value: 'true');

  /// Whether the app looks for a new version on start (default off).
  Future<bool> loadAutoUpdateCheck() async =>
      await _storage.read(key: _keyAutoUpdateCheck) == 'true';

  Future<void> saveAutoUpdateCheck(bool enabled) =>
      _storage.write(key: _keyAutoUpdateCheck, value: '$enabled');

  /// When the app last read its releases (by hand or on start).
  Future<DateTime?> loadLastUpdateCheck() async =>
      DateTime.tryParse(await _storage.read(key: _keyLastUpdateCheck) ?? '');

  Future<void> saveLastUpdateCheck(DateTime at) => _storage.write(
        key: _keyLastUpdateCheck,
        value: at.toUtc().toIso8601String(),
      );

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

  Future<String?> loadWikiAppliedUrl(int index) async {
    final value = await _storage.read(key: '$_keyWikiAppliedUrlPrefix$index');
    final uri = value == null ? null : Uri.tryParse(value);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) return null;
    return value;
  }

  Future<void> saveWikiAppliedUrl(int index, String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) return;
    await _storage.write(
      key: '$_keyWikiAppliedUrlPrefix$index',
      value: url,
    );
  }

  Future<List<WikiSiteConfig>> loadWikiSites() async {
    final raw = await _storage.read(key: _keyWikiSources);
    if (raw != null && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          final rawSites = decoded
              .map(WikiSiteConfig.fromJson)
              .whereType<WikiSiteConfig>()
              .map(_migrateWikiSite)
              .toList();
          final sites = <WikiSiteConfig>[];
          var hasEndfield = false;
          for (final site in rawSites) {
            if (site.builtIn && site.id == 'endfield') {
              if (hasEndfield) continue;
              hasEndfield = true;
            }
            sites.add(site);
          }
          if (sites.isNotEmpty) {
            if (!hasEndfield) sites.add(defaultWikiSites[1]);
            await _storage.write(
              key: _keyWikiSources,
              value: jsonEncode(sites.map((site) => site.toJson()).toList()),
            );
            return sites;
          }
        }
      } catch (_) {
        // Fall through to defaults.
      }
    }

    // Never saved: the built-in sites at their own addresses. (The tabs'
    // last-visited pages are browsing state, not the sites' addresses.)
    return [
      for (final site in defaultWikiSites)
        WikiSiteConfig(
          id: site.id,
          label: site.label,
          url: site.url,
          iconUrl: site.iconUrl,
          builtIn: true,
        ),
    ];
  }

  static WikiSiteConfig _migrateWikiSite(WikiSiteConfig site) {
    if (site.builtIn &&
        (site.id == 'endfield' ||
            site.id == 'endfield-warfarin' ||
            site.id == 'endfield-fz')) {
      final isFz = site.url.contains('fz.wiki');
      return WikiSiteConfig(
        id: 'endfield',
        label: 'Endfield Wiki',
        url: site.url,
        iconUrl: site.iconUrl ??
            (isFz
                ? 'https://fz.wiki/icon.svg'
                : 'https://warfarin.wiki/icon.png'),
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
      for (var i = 0; i < 20; i++) ...[
        _storage.delete(key: '$_keyWikiUrlPrefix$i'),
        _storage.delete(key: '$_keyWikiAppliedUrlPrefix$i'),
      ],
    ]);
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

  /// Forgets the Wiki page's own appearance: it follows the app's theme.
  Future<void> clearWikiDarkMode() async {
    await _storage.delete(key: _keyWikiDarkMode);
  }

  Future<AppTheme> loadTheme() async {
    final value = await _storage.read(key: _keyTheme);
    return AppTheme.values.firstWhere(
      (theme) => theme.name == value,
      // Nothing saved yet (a new install): follow the system.
      orElse: () => AppTheme.system,
    );
  }

  Future<void> saveTheme(AppTheme theme) async {
    await _storage.write(key: _keyTheme, value: theme.name);
  }

  Future<SupportedLocale> loadLocale() async {
    final value = await _storage.read(key: _keyLocale);
    return SupportedLocale.values.firstWhere(
      (locale) => locale.name == value,
      orElse: () => SupportedLocale.zh,
    );
  }

  Future<void> saveLocale(SupportedLocale locale) async {
    await _storage.write(key: _keyLocale, value: locale.name);
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
