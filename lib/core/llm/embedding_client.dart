/// OpenAI-compatible text embedding client (R12 vector recall). Pure Dart:
/// shared by the app (query embedding) and `tools/build_story_embeddings.dart`
/// (corpus embedding), so both sides call the same endpoint the same way.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'llm_client.dart' show LLMException;

/// Embedding endpoint configuration (e.g. Alibaba Cloud Bailian
/// `.../compatible-mode/v1` + `qwen3.7-text-embedding`).
class EmbeddingConfig {
  const EmbeddingConfig({
    this.baseUrl = '',
    this.apiKey = '',
    this.model = '',
    this.dimensions = 512,
  });
  final String baseUrl;
  final String apiKey;
  final String model;
  final int dimensions;

  bool get isValid =>
      baseUrl.trim().isNotEmpty && apiKey.trim().isNotEmpty && model.trim().isNotEmpty;

  String get endpoint {
    final base = baseUrl.trim();
    return base.endsWith('/') ? '${base}embeddings' : '$base/embeddings';
  }

  EmbeddingConfig copyWith({
    String? baseUrl,
    String? apiKey,
    String? model,
    int? dimensions,
  }) =>
      EmbeddingConfig(
        baseUrl: baseUrl ?? this.baseUrl,
        apiKey: apiKey ?? this.apiKey,
        model: model ?? this.model,
        dimensions: dimensions ?? this.dimensions,
      );
}

/// App defaults: Bailian's public OpenAI-compatible endpoint and the model the
/// release vectors are built with. Dims must match the DB manifest.
const EmbeddingConfig defaultEmbeddingConfig = EmbeddingConfig(
  baseUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1',
  model: 'qwen3.7-text-embedding',
);

/// Embeds texts into vectors.
abstract class EmbeddingClient {
  /// The model name vectors come from (checked against the DB manifest).
  String get model;

  /// Requested vector size.
  int get dimensions;

  /// One vector per text, in input order.
  Future<List<List<double>>> embed(List<String> texts);

  /// Tokens the provider has billed this client so far (0 when the provider
  /// reports no usage). Used to show the real cost after a vector update.
  int get tokensUsed => 0;
}

/// `POST {baseUrl}/embeddings` with `{model, input, dimensions}`.
class OpenAICompatibleEmbeddingClient implements EmbeddingClient {
  OpenAICompatibleEmbeddingClient({
    required this.config,
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 60),
    this.maxRetries = 4,
  }) : _http = httpClient ?? http.Client();

  final EmbeddingConfig config;
  final Duration timeout;
  final int maxRetries;
  final http.Client _http;

  /// Small cache for repeated query strings within a session.
  final Map<String, List<double>> _cache = {};
  static const int _cacheSize = 64;

  /// Largest batch the Bailian endpoint accepted in testing (32 failed).
  static const int maxBatch = 20;

  @override
  String get model => config.model;

  @override
  int get dimensions => config.dimensions;

  int _tokensUsed = 0;

  @override
  int get tokensUsed => _tokensUsed;

  @override
  Future<List<List<double>>> embed(List<String> texts) async {
    if (texts.isEmpty) return const [];
    if (texts.length == 1 && _cache.containsKey(texts.single)) {
      return [_cache[texts.single]!];
    }
    final out = <List<double>>[];
    for (var i = 0; i < texts.length; i += maxBatch) {
      final end = i + maxBatch < texts.length ? i + maxBatch : texts.length;
      out.addAll(await _embedBatch(texts.sublist(i, end)));
    }
    if (texts.length == 1) {
      if (_cache.length >= _cacheSize) _cache.remove(_cache.keys.first);
      _cache[texts.single] = out.single;
    }
    return out;
  }

  Future<List<List<double>>> _embedBatch(List<String> batch) async {
    Object? lastError;
    for (var attempt = 0; attempt <= maxRetries; attempt++) {
      if (attempt > 0) {
        await Future<void>.delayed(Duration(milliseconds: 500 * (1 << attempt)));
      }
      try {
        final response = await _http
            .post(
              Uri.parse(config.endpoint),
              headers: {
                'Authorization': 'Bearer ${config.apiKey}',
                'Content-Type': 'application/json; charset=utf-8',
              },
              body: jsonEncode({
                'model': config.model,
                'input': batch,
                'dimensions': config.dimensions,
                'encoding_format': 'float',
              }),
            )
            .timeout(timeout);
        if (response.statusCode == 429 || response.statusCode >= 500) {
          lastError = LLMException(
            'Embedding request failed (${response.statusCode})',
            statusCode: response.statusCode,
            body: utf8.decode(response.bodyBytes),
          );
          continue; // retryable
        }
        if (response.statusCode != 200) {
          throw LLMException(
            'Embedding request failed (${response.statusCode}): '
            '${utf8.decode(response.bodyBytes)}',
            statusCode: response.statusCode,
          );
        }
        final json = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
        final data = (json['data'] as List).cast<Map<String, dynamic>>()
          ..sort((a, b) => (a['index'] as num).compareTo(b['index'] as num));
        if (data.length != batch.length) {
          throw LLMException(
            'Embedding response has ${data.length} vectors for ${batch.length} inputs',
          );
        }
        final usage = json['usage'];
        if (usage is Map) {
          _tokensUsed += ((usage['total_tokens'] ?? usage['prompt_tokens'])
                      as num?)
                  ?.toInt() ??
              0;
        }
        return [
          for (final item in data)
            [for (final v in item['embedding'] as List) (v as num).toDouble()],
        ];
      } on TimeoutException catch (e) {
        lastError = e;
      } on SocketException catch (e) {
        lastError = e;
      } on http.ClientException catch (e) {
        lastError = e;
      }
    }
    throw LLMException('Embedding request failed after retries: $lastError');
  }

  void dispose() => _http.close();
}
