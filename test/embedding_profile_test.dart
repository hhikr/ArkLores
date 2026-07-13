import 'package:arklores/core/llm/embedding_profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('API key is not part of embedding profile identity', () {
    final first = EmbeddingProfile.api(
      baseUrl: 'https://api.openai.com/v1',
      apiKey: 'sk-first',
      model: 'text-embedding-3-small',
      dimension: 1536,
      now: 100,
    );
    final second = EmbeddingProfile.api(
      baseUrl: 'https://api.openai.com/v1',
      apiKey: 'sk-second',
      model: 'text-embedding-3-small',
      dimension: 1536,
      now: 200,
    );

    expect(first.id, second.id);
    expect(first.matchKey, second.matchKey);
  });

  test('different embedding model creates a different profile', () {
    final first = EmbeddingProfile.api(
      baseUrl: 'https://api.openai.com/v1',
      apiKey: 'sk-same',
      model: 'text-embedding-3-small',
      dimension: 1536,
      now: 100,
    );
    final second = EmbeddingProfile.api(
      baseUrl: 'https://api.openai.com/v1',
      apiKey: 'sk-same',
      model: 'text-embedding-3-large',
      dimension: 3072,
      now: 200,
    );

    expect(first.id, isNot(second.id));
    expect(first.matchKey, isNot(second.matchKey));
  });

  test('canEmbed reflects active profile backend and API key state', () {
    final apiWithoutKey = EmbeddingProfile.api(
      baseUrl: 'https://api.openai.com/v1',
      apiKey: '',
      model: 'text-embedding-3-small',
      dimension: 0,
      now: 100,
    );
    final builtin = EmbeddingProfile.builtin(
      model: 'multilingual-e5-small-tflite',
      dimension: 384,
      now: 100,
    );

    expect(
      EmbeddingSettingsState(
        profiles: [apiWithoutKey, builtin],
        activeProfileId: apiWithoutKey.id,
      ).canEmbed,
      isFalse,
    );
    expect(
      EmbeddingSettingsState(
        profiles: [apiWithoutKey, builtin],
        activeProfileId: builtin.id,
      ).canEmbed,
      isTrue,
    );
  });
}
