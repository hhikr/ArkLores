import 'dart:convert';

import 'llm_client.dart';

enum EmbeddingBackend {
  api,
  builtin,
}

class EmbeddingProfile {
  final String id;
  final EmbeddingBackend backend;
  final String baseUrl;
  final String apiKey;
  final String model;
  final int dimension;
  final int createdAt;
  final int updatedAt;

  const EmbeddingProfile({
    required this.id,
    required this.backend,
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    required this.dimension,
    required this.createdAt,
    required this.updatedAt,
  });

  factory EmbeddingProfile.create({
    required EmbeddingBackend backend,
    required String baseUrl,
    required String apiKey,
    required String model,
    required int dimension,
    required int now,
    String? id,
  }) {
    return EmbeddingProfile(
      id: id ?? _encodeId(_matchKey(backend, baseUrl, model)),
      backend: backend,
      baseUrl: baseUrl,
      apiKey: apiKey,
      model: model,
      dimension: dimension,
      createdAt: now,
      updatedAt: now,
    );
  }

  factory EmbeddingProfile.builtin({
    required String model,
    required int dimension,
    required int now,
    String? id,
  }) {
    return EmbeddingProfile.create(
      backend: EmbeddingBackend.builtin,
      baseUrl: '',
      apiKey: '',
      model: model,
      dimension: dimension,
      now: now,
      id: id ?? 'builtin:$model',
    );
  }

  factory EmbeddingProfile.api({
    required String baseUrl,
    required String apiKey,
    required String model,
    required int dimension,
    required int now,
    String? id,
  }) {
    return EmbeddingProfile.create(
      backend: EmbeddingBackend.api,
      baseUrl: baseUrl,
      apiKey: apiKey,
      model: model,
      dimension: dimension,
      now: now,
      id: id,
    );
  }

  factory EmbeddingProfile.fromJson(Map<String, dynamic> json) {
    return EmbeddingProfile(
      id: json['id'] as String,
      backend: EmbeddingBackend.values.firstWhere(
        (value) => value.name == (json['backend'] as String? ?? 'api'),
        orElse: () => EmbeddingBackend.api,
      ),
      baseUrl: (json['baseUrl'] as String?) ?? '',
      apiKey: (json['apiKey'] as String?) ?? '',
      model: (json['model'] as String?) ?? '',
      dimension: (json['dimension'] as int?) ?? 0,
      createdAt: (json['createdAt'] as int?) ?? 0,
      updatedAt: (json['updatedAt'] as int?) ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'backend': backend.name,
        'baseUrl': baseUrl,
        'apiKey': apiKey,
        'model': model,
        'dimension': dimension,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
      };

  EmbeddingProfile copyWith({
    String? id,
    EmbeddingBackend? backend,
    String? baseUrl,
    String? apiKey,
    String? model,
    int? dimension,
    int? createdAt,
    int? updatedAt,
  }) {
    return EmbeddingProfile(
      id: id ?? this.id,
      backend: backend ?? this.backend,
      baseUrl: baseUrl ?? this.baseUrl,
      apiKey: apiKey ?? this.apiKey,
      model: model ?? this.model,
      dimension: dimension ?? this.dimension,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  String get identityKey => _identityKey(backend, baseUrl, model, dimension);

  String get matchKey => _matchKey(backend, baseUrl, model);

  String get displayName {
    switch (backend) {
      case EmbeddingBackend.builtin:
        return 'Built-in · $model';
      case EmbeddingBackend.api:
        final host = Uri.tryParse(baseUrl)?.host;
        final provider = (host == null || host.isEmpty) ? baseUrl : host;
        return '$provider · $model';
    }
  }

  bool get isBuiltin => backend == EmbeddingBackend.builtin;

  bool get isApi => backend == EmbeddingBackend.api;

  LLMConfig toEmbeddingConfig() {
    return LLMConfig(
      chatBaseUrl: baseUrl.isEmpty ? 'https://api.deepseek.com/v1' : baseUrl,
      chatApiKey: apiKey,
      chatModel: model,
      embedBaseUrl: baseUrl.isEmpty ? 'https://api.openai.com/v1' : baseUrl,
      embedApiKey: apiKey,
      embedModel: model,
    );
  }

  static String _identityKey(
    EmbeddingBackend backend,
    String baseUrl,
    String model,
    int dimension,
  ) {
    return '${backend.name}|${baseUrl.trim()}|${model.trim()}|$dimension';
  }

  static String _matchKey(
    EmbeddingBackend backend,
    String baseUrl,
    String model,
  ) {
    return '${backend.name}|${baseUrl.trim()}|${model.trim()}';
  }

  static String _encodeId(String value) {
    return base64Url.encode(utf8.encode(value));
  }
}

class EmbeddingSettingsState {
  final List<EmbeddingProfile> profiles;
  final String? activeProfileId;

  const EmbeddingSettingsState({
    this.profiles = const [],
    this.activeProfileId,
  });

  EmbeddingProfile? get activeProfile {
    for (final profile in profiles) {
      if (profile.id == activeProfileId) return profile;
    }
    return profiles.isNotEmpty ? profiles.first : null;
  }

  bool get canEmbed {
    final profile = activeProfile;
    if (profile == null) return false;
    return profile.isBuiltin || profile.apiKey.isNotEmpty;
  }

  EmbeddingSettingsState copyWith({
    List<EmbeddingProfile>? profiles,
    String? activeProfileId,
  }) {
    return EmbeddingSettingsState(
      profiles: profiles ?? this.profiles,
      activeProfileId: activeProfileId ?? this.activeProfileId,
    );
  }

  EmbeddingSettingsState withActiveProfileId(String? id) {
    return EmbeddingSettingsState(
      profiles: profiles,
      activeProfileId: id,
    );
  }
}
