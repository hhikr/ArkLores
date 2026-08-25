import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'llm_client.dart';

/// OpenAI-compatible implementation of [LLMClient].
///
/// Supports custom Base URL for chat-completion providers.
class OpenAICompatibleClient implements LLMClient {

  OpenAICompatibleClient({
    required this.config,
    http.Client? httpClient,
    Duration? timeout,
  })  : _httpClient = httpClient ?? http.Client(),
        _timeout = timeout ?? defaultRequestTimeout;

  /// Default per-request timeout. Generous on purpose: ReAct agents may carry
  /// large accumulated contexts (long investigations) whose single completion
  /// exceeds a short HTTP timeout; a 30s default caused sessions to die with
  /// "Request timed out" mid-investigation. 180s pairs with the 8192-token
  /// step budget (R7-4): a full step can take minutes on slower providers.
  static const Duration defaultRequestTimeout = Duration(seconds: 180);
  final LLMConfig config;
  final http.Client _httpClient;
  final Duration _timeout;

  @override
  Future<String> chat(
    List<Message> messages, {
    List<Map<String, dynamic>>? tools,
    double temperature = 0.7,
    int maxTokens = 2048,
    List<String>? stop,
  }) async {
    final result = await chatCompletion(
      messages,
      tools: tools,
      temperature: temperature,
      maxTokens: maxTokens,
      stop: stop,
    );
    return result.content;
  }

  @override
  Future<ChatCompletionResult> chatCompletion(
    List<Message> messages, {
    List<Map<String, dynamic>>? tools,
    double temperature = 0.7,
    int maxTokens = 2048,
    List<String>? stop,
  }) async {
    _requireChatConfig();

    final body = <String, dynamic>{
      'model': config.chatModel,
      'messages': messages.map((m) => m.toJson()).toList(),
      'temperature': temperature,
      'max_tokens': maxTokens,
      if (stop != null) 'stop': stop,
    };

    if (tools != null && tools.isNotEmpty) {
      body['tools'] = tools;
    }

    try {
      // R8 M-E: transient network errors (backgrounding closes the socket)
      // are retried once before surfacing.
      http.Response? response;
      Object? lastError;
      for (var attempt = 0; attempt < 2; attempt++) {
        try {
          response = await _httpClient
              .post(
                Uri.parse(config.chatEndpoint),
                headers: _headers(config.chatApiKey, label: 'Chat API Key'),
                body: jsonEncode(body),
              )
              .timeout(_timeout);
          break;
        } on SocketException catch (e) {
          lastError = e;
        } on http.ClientException catch (e) {
          lastError = e;
        } on TimeoutException catch (e) {
          lastError = e;
        }
      }
      if (response == null) {
        if (lastError is TimeoutException) {
          throw const LLMException('Request timed out');
        }
        throw LLMException('Network error: $lastError');
      }

      if (response.statusCode != 200) {
        throw LLMException(
          chatFailureMessage(response.body,
              fallback: 'Chat completion failed',),
          statusCode: response.statusCode,
          body: response.body,
        );
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final choices = data['choices'] as List<dynamic>;
      if (choices.isEmpty) {
        throw const LLMException('Empty response from chat completion');
      }

      final firstChoice = choices[0] as Map<String, dynamic>;
      final message = firstChoice['message'] as Map<String, dynamic>;
      return ChatCompletionResult(
        content: (message['content'] as String?) ?? '',
        finishReason: firstChoice['finish_reason'] as String?,
      );
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
    List<String>? stop,
  }) async {
    _requireChatConfig();

    final body = <String, dynamic>{
      'model': config.chatModel,
      'messages': messages.map((m) => m.toJson()).toList(),
      'temperature': temperature,
      'max_tokens': maxTokens,
      'stream': true,
      if (stop != null) 'stop': stop,
    };

    try {
      final request = http.Request('POST', Uri.parse(config.chatEndpoint))
        ..headers.addAll(_headers(config.chatApiKey, label: 'Chat API Key'))
        ..body = jsonEncode(body);

      final streamedResponse =
          await _httpClient.send(request).timeout(_timeout);

      if (streamedResponse.statusCode != 200) {
        final body = await streamedResponse.stream.bytesToString();
        throw LLMException(
          'Chat stream failed',
          statusCode: streamedResponse.statusCode,
          body: body,
        );
      }

      final buffer = StringBuffer();
      await for (final chunk
          in streamedResponse.stream.transform(utf8.decoder)) {
        final lines = chunk.split('\n');
        for (final line in lines) {
          if (!line.startsWith('data: ')) continue;
          final data = line.substring(6);
          if (data == '[DONE]') continue;

          try {
            final json = jsonDecode(data) as Map<String, dynamic>;
            final choices = json['choices'] as List<dynamic>?;
            if (choices == null || choices.isEmpty) continue;

            final firstChoice = choices[0] as Map<String, dynamic>;
            final delta = firstChoice['delta'] as Map<String, dynamic>?;
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

  Map<String, String> _headers(String apiKey, {String label = 'API Key'}) {
    final error = LLMConfig.apiKeyFormatError(apiKey, label: label);
    if (error != null) {
      throw LLMException(error);
    }
    return {
      'Authorization': 'Bearer $apiKey',
      'Content-Type': 'application/json',
    };
  }

  void _requireChatConfig() {
    if (config.chatApiKey.isEmpty) {
      throw const LLMException(
        'Chat API Key not configured. Please set up your Chat API in Settings.',
      );
    }
    final error =
        LLMConfig.apiKeyFormatError(config.chatApiKey, label: 'Chat API Key');
    if (error != null) {
      throw LLMException(error);
    }
  }

  /// Releases the underlying HTTP client resources.
  void dispose() {
    _httpClient.close();
  }
}

/// Renders a user-friendly error message for a non-200 chat response.
String chatFailureMessage(String body, {required String fallback}) {
  final message = _responseErrorMessage(body, fallback: fallback);
  if (message.contains('Insufficient Balance') ||
      message.contains('insufficient_quota') ||
      message.contains('402')) {
    return 'Chat API 余额不足，请充值后重试。';
  }
  return message;
}

String _responseErrorMessage(String body, {required String fallback}) {
  try {
    final decoded = jsonDecode(body) as Map<String, dynamic>;
    final error = decoded['error'];
    if (error is Map<String, dynamic>) {
      final message = error['message'];
      if (message is String && message.trim().isNotEmpty) {
        return '$fallback: ${message.trim()}';
      }
    }
    final message = decoded['message'];
    if (message is String && message.trim().isNotEmpty) {
      return '$fallback: ${message.trim()}';
    }
  } catch (_) {
    // Keep the stable fallback for non-JSON provider responses.
  }
  return fallback;
}
