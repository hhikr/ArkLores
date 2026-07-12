import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'llm_client.dart';

/// OpenAI-compatible implementation of [LLMClient].
///
/// Supports custom Base URL (for domestic/transit APIs),
/// configurable chat and embedding models.
class OpenAICompatibleClient implements LLMClient {
  final LLMConfig config;
  final http.Client _httpClient;
  final Duration _timeout;

  OpenAICompatibleClient({
    required this.config,
    http.Client? httpClient,
    Duration? timeout,
  })  : _httpClient = httpClient ?? http.Client(),
        _timeout = timeout ?? const Duration(seconds: 30);

  @override
  Future<String> chat(
    List<Message> messages, {
    List<Map<String, dynamic>>? tools,
    double temperature = 0.7,
    int maxTokens = 2048,
  }) async {
    _requireValidConfig();

    final body = <String, dynamic>{
      'model': config.chatModel,
      'messages': messages.map((m) => m.toJson()).toList(),
      'temperature': temperature,
      'max_tokens': maxTokens,
    };

    if (tools != null && tools.isNotEmpty) {
      body['tools'] = tools;
    }

    try {
      final response = await _httpClient
          .post(
            Uri.parse(config.chatEndpoint),
            headers: _headers(),
            body: jsonEncode(body),
          )
          .timeout(_timeout);

      if (response.statusCode != 200) {
        throw LLMException(
          'Chat completion failed',
          statusCode: response.statusCode,
          body: response.body,
        );
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final choices = data['choices'] as List<dynamic>;
      if (choices.isEmpty) {
        throw const LLMException('Empty response from chat completion');
      }

      final message = choices[0]['message'] as Map<String, dynamic>;
      return (message['content'] as String?) ?? '';
    } on SocketException catch (e) {
      throw LLMException('Network error: ${e.message}');
    } on TimeoutException {
      throw const LLMException('Request timed out');
    }
  }

  @override
  Future<String> chatStream(
    List<Message> messages, {
    void Function(String token)? onToken,
    double temperature = 0.7,
    int maxTokens = 2048,
  }) async {
    _requireValidConfig();

    final body = <String, dynamic>{
      'model': config.chatModel,
      'messages': messages.map((m) => m.toJson()).toList(),
      'temperature': temperature,
      'max_tokens': maxTokens,
      'stream': true,
    };

    try {
      final request = http.Request('POST', Uri.parse(config.chatEndpoint))
        ..headers.addAll(_headers())
        ..body = jsonEncode(body);

      final streamedResponse = await _httpClient
          .send(request)
          .timeout(_timeout);

      if (streamedResponse.statusCode != 200) {
        final body = await streamedResponse.stream.bytesToString();
        throw LLMException(
          'Chat stream failed',
          statusCode: streamedResponse.statusCode,
          body: body,
        );
      }

      final buffer = StringBuffer();
      await for (final chunk in streamedResponse.stream.transform(utf8.decoder)) {
        final lines = chunk.split('\n');
        for (final line in lines) {
          if (!line.startsWith('data: ')) continue;
          final data = line.substring(6);
          if (data == '[DONE]') continue;

          try {
            final json = jsonDecode(data) as Map<String, dynamic>;
            final choices = json['choices'] as List<dynamic>?;
            if (choices == null || choices.isEmpty) continue;

            final delta = choices[0]['delta'] as Map<String, dynamic>?;
            final content = delta?['content'] as String?;
            if (content != null && content.isNotEmpty) {
              buffer.write(content);
              onToken?.call(content);
            }
          } catch (_) {
            // Skip malformed JSON lines in the stream.
          }
        }
      }

      return buffer.toString();
    } on SocketException catch (e) {
      throw LLMException('Network error: ${e.message}');
    } on TimeoutException {
      throw const LLMException('Request timed out');
    }
  }

  @override
  Future<List<double>> embed(String text) async {
    _requireValidConfig();

    try {
      final response = await _httpClient
          .post(
            Uri.parse(config.embeddingEndpoint),
            headers: _headers(),
            body: jsonEncode({
              'model': config.embeddingModel,
              'input': text,
            }),
          )
          .timeout(_timeout);

      if (response.statusCode != 200) {
        throw LLMException(
          'Embedding failed',
          statusCode: response.statusCode,
          body: response.body,
        );
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final dataList = data['data'] as List<dynamic>;
      if (dataList.isEmpty) {
        throw const LLMException('Empty response from embedding');
      }

      final embedding = dataList[0]['embedding'] as List<dynamic>;
      return embedding.cast<double>();
    } on SocketException catch (e) {
      throw LLMException('Network error: ${e.message}');
    } on TimeoutException {
      throw const LLMException('Request timed out');
    }
  }

  @override
  Future<List<List<double>>> embedBatch(List<String> texts) async {
    _requireValidConfig();

    if (texts.isEmpty) return [];

    final results = <List<double>>[];

    try {
      // Split into batches of 100 to avoid request size limits.
      const batchSize = 100;
      for (var offset = 0; offset < texts.length; offset += batchSize) {
        final batch = texts.sublist(
          offset,
          offset + batchSize > texts.length
              ? texts.length
              : offset + batchSize,
        );

        final response = await _httpClient
            .post(
              Uri.parse(config.embeddingEndpoint),
              headers: _headers(),
              body: jsonEncode({
                'model': config.embeddingModel,
                'input': batch,
              }),
            )
            .timeout(Duration(
              seconds: _timeout.inSeconds + (batch.length ~/ 10),
            ));

        if (response.statusCode != 200) {
          throw LLMException(
            'Batch embedding failed',
            statusCode: response.statusCode,
            body: response.body,
          );
        }

        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final dataList = data['data'] as List<dynamic>;
        // Sort by index to preserve order.
        dataList.sort((a, b) =>
            (a['index'] as int).compareTo(b['index'] as int));

        for (final item in dataList) {
          results.add((item['embedding'] as List<dynamic>).cast<double>());
        }
      }

      return results;
    } on SocketException catch (e) {
      throw LLMException('Network error: ${e.message}');
    } on TimeoutException {
      throw const LLMException('Batch embedding timed out');
    }
  }

  Map<String, String> _headers() => {
        'Authorization': 'Bearer ${config.apiKey}',
        'Content-Type': 'application/json',
      };

  void _requireValidConfig() {
    if (!config.isValid) {
      throw const LLMException(
        'API Key not configured. Please set up your API Key in Settings.',
      );
    }
  }

  /// Releases the underlying HTTP client resources.
  void dispose() {
    _httpClient.close();
  }
}
