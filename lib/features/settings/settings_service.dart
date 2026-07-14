import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/llm/embedding_profile.dart';
import '../../core/llm/llm_client.dart';
import '../../core/rag/local_embedding/builtin_embedding_model.dart';

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

  // ── Embedding profile keys ─────────────────────────────────
  static const _keyEmbeddingProfiles = 'embedding_profiles';
  static const _keyActiveEmbeddingProfileId = 'active_embedding_profile_id';

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

  /// Loads embedding profiles, migrating the legacy embedding API config when
  /// the profile list does not exist yet.
  Future<EmbeddingSettingsState> loadEmbeddingSettings(
      {required LLMConfig legacyConfig}) async {
    final rawProfiles = await _storage.read(key: _keyEmbeddingProfiles);
    final activeId = await _storage.read(key: _keyActiveEmbeddingProfileId);

    if (rawProfiles != null && rawProfiles.isNotEmpty) {
      final decodedProfiles = _decodeProfiles(rawProfiles);
      final activeProfile = decodedProfiles
          .where((profile) => profile.id == activeId)
          .firstOrNull;
      final profiles = _normalizeBuiltinProfiles(decodedProfiles);
      final normalizedActiveId = activeProfile?.isBuiltin == true
          ? BuiltinEmbeddingModel.providerId
          : activeId;
      final resolvedActiveId = profiles.any((p) => p.id == normalizedActiveId)
          ? normalizedActiveId
          : profiles.any((p) => p.id == activeId)
              ? activeId
              : (profiles.isNotEmpty ? profiles.first.id : null);
      final state = EmbeddingSettingsState(
        profiles: profiles,
        activeProfileId: resolvedActiveId,
      );
      if (_profilesChanged(decodedProfiles, profiles) ||
          activeId != resolvedActiveId) {
        await saveEmbeddingSettings(state);
      }
      return state;
    }

    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final builtin = EmbeddingProfile.builtin(
      model: BuiltinEmbeddingModel.id,
      dimension: BuiltinEmbeddingModel.expectedDimension,
      now: now,
    );
    final migrated = EmbeddingProfile.api(
      baseUrl: legacyConfig.embedBaseUrl,
      apiKey: legacyConfig.embedApiKey,
      model: legacyConfig.embedModel,
      dimension: 0,
      now: now,
      id: 'legacy',
    );
    final state = EmbeddingSettingsState(
      profiles: [builtin, migrated],
      activeProfileId: builtin.id,
    );
    await saveEmbeddingSettings(state);
    return state;
  }

  Future<void> saveEmbeddingSettings(EmbeddingSettingsState state) async {
    await Future.wait([
      _storage.write(
        key: _keyEmbeddingProfiles,
        value: jsonEncode(state.profiles.map((p) => p.toJson()).toList()),
      ),
      if (state.activeProfileId != null)
        _storage.write(
          key: _keyActiveEmbeddingProfileId,
          value: state.activeProfileId,
        )
      else
        _storage.delete(key: _keyActiveEmbeddingProfileId),
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

  List<EmbeddingProfile> _decodeProfiles(String raw) {
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .map((item) => EmbeddingProfile.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  List<EmbeddingProfile> _normalizeBuiltinProfiles(
    List<EmbeddingProfile> profiles,
  ) {
    final normalized = <EmbeddingProfile>[];
    var hasBuiltin = false;

    for (final profile in profiles) {
      if (!profile.isBuiltin) {
        normalized.add(profile);
        continue;
      }

      final canonical = profile.copyWith(
        id: BuiltinEmbeddingModel.providerId,
        model: BuiltinEmbeddingModel.id,
        dimension: profile.dimension > 0
            ? profile.dimension
            : BuiltinEmbeddingModel.expectedDimension,
      );

      if (!hasBuiltin) {
        normalized.add(canonical);
        hasBuiltin = true;
      }
    }

    if (!hasBuiltin) {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      normalized.insert(
        0,
        EmbeddingProfile.builtin(
          model: BuiltinEmbeddingModel.id,
          dimension: BuiltinEmbeddingModel.expectedDimension,
          now: now,
        ),
      );
    }

    return normalized;
  }

  bool _profilesChanged(
    List<EmbeddingProfile> before,
    List<EmbeddingProfile> after,
  ) {
    if (before.length != after.length) return true;
    for (var i = 0; i < before.length; i++) {
      if (jsonEncode(before[i].toJson()) != jsonEncode(after[i].toJson())) {
        return true;
      }
    }
    return false;
  }
}
