import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'llm_client.dart';

/// OpenAI-compatible implementation of [LLMClient].
///
/// Supports custom Base URL for chat-completion providers.
class OpenAICompatibleClient extends LLMClient {
  OpenAICompatibleClient({
    required this.config,
    http.Client? httpClient,
    Duration? timeout,
    this.onCompletion,
    this.reasoning = ReasoningLevel.off,
    Duration? streamIdleTimeout,
    this.rateLimitBackoff = defaultRateLimitBackoff,
  })  : _httpClient = httpClient ?? http.Client(),
        _timeout = timeout ?? defaultRequestTimeout,
        _streamIdleTimeout = streamIdleTimeout ?? defaultStreamIdleTimeout;

  /// Waits before each retry of a rate-limited (429) request; its length is
  /// the number of retries. Parallel sub-agents can exceed a provider's
  /// concurrency limit (e.g. free / flash tiers).
  final List<Duration> rateLimitBackoff;

  static const List<Duration> defaultRateLimitBackoff = [
    Duration(seconds: 2),
    Duration(seconds: 5),
    Duration(seconds: 10),
  ];

  /// Zhipu GLM (open.bigmodel.cn / api.z.ai), or a GLM model elsewhere.
  static bool isZhipu(LLMConfig config) {
    final host = Uri.tryParse(config.chatBaseUrl)?.host.toLowerCase() ?? '';
    return host.endsWith('bigmodel.cn') ||
        host == 'z.ai' ||
        host.endsWith('.z.ai') ||
        config.chatModel.toLowerCase().startsWith('glm');
  }

  /// Zhipu only accepts `tool_choice: auto`; elsewhere `none` is sent on
  /// the last agent turn.
  static bool acceptsToolChoice(LLMConfig config) => !isZhipu(config);

  /// Set when the provider rejected the [reasoningFields] (some models
  /// cannot switch thinking off, e.g. GLM-5.3-Flash): later requests of
  /// this client leave them out and the model thinks at its default.
  bool _reasoningFieldsRejected = false;

  /// Set when the provider rejected `stream_options`: later streams are
  /// sent without it (usage may then be missing).
  bool _streamOptionsRejected = false;

  /// Whether a 4xx [errorText] for [body] is about the reasoning fields.
  bool _rejectsReasoningFields(Map<String, dynamic> body, String errorText) {
    final fields = reasoningFields.keys;
    if (fields.isEmpty || !fields.any(body.containsKey)) return false;
    final text = errorText.toLowerCase();
    // Zhipu answers some rejections only with "Invalid API parameter"
    // ("参数有误"); a retry without the fields costs one request at most.
    return text.contains('thinking') ||
        text.contains('reasoning') ||
        text.contains('parameter') ||
        text.contains('参数');
  }

  Map<String, dynamic> _withoutReasoningFields(Map<String, dynamic> body) {
    _reasoningFieldsRejected = true;
    return Map.of(body)..removeWhere((k, _) => reasoningFields.containsKey(k));
  }

  /// Optional observer of every successful completion (e.g. a token meter in
  /// the live test harness). Never alters the result.
  final void Function(ChatCompletionResult result)? onCompletion;

  /// R12/R16: hidden-reasoning level. Hybrid reasoning models default to
  /// thinking on at a high effort (deepseek); [ReasoningLevel.off] measured
  /// 298 -> 9 output tokens for a one-line intent on deepseek flash.
  final ReasoningLevel reasoning;

  /// Provider-specific body fields for [reasoning]; empty for providers
  /// without a known switch, so the request can never be rejected for them.
  Map<String, dynamic> get reasoningFields =>
      reasoningFieldsFor(config, reasoning);

  /// Body fields that set [level] on the provider of [config] (R16).
  static Map<String, dynamic> reasoningFieldsFor(
    LLMConfig config,
    ReasoningLevel level,
  ) {
    final endpoint = config.chatEndpoint.toLowerCase();
    final model = config.chatModel.toLowerCase();
    if (endpoint.contains('dashscope') || endpoint.contains('aliyuncs.com')) {
      return switch (level) {
        ReasoningLevel.off => {'enable_thinking': false},
        ReasoningLevel.low => {
            'enable_thinking': true,
            'thinking_budget': 2048,
          },
        ReasoningLevel.high => {'enable_thinking': true},
      };
    }
    if (endpoint.contains('deepseek.com') || model.contains('deepseek')) {
      return switch (level) {
        ReasoningLevel.off => {
            'thinking': {'type': 'disabled'},
          },
        ReasoningLevel.low => {
            'thinking': {'type': 'enabled'},
            'reasoning_effort': 'low',
          },
        ReasoningLevel.high => {
            'thinking': {'type': 'enabled'},
            'reasoning_effort': 'high',
          },
      };
    }
    if (isZhipu(config)) {
      // Measured 2026-10 (glm-5.3-flash, api.z.ai): thinking cannot be
      // disabled ("please use low, high, or max"); `reasoning_effort: low`
      // cut an 80-word answer from ~1100 reasoning chunks / 20 s to none /
      // 4 s. No field = the model's own (heavy) default.
      return switch (level) {
        ReasoningLevel.off => {'reasoning_effort': 'low'},
        ReasoningLevel.low => {'reasoning_effort': 'high'},
        ReasoningLevel.high => {'reasoning_effort': 'max'},
      };
    }
    return const {};
  }

  /// Default per-request timeout. Generous on purpose: ReAct agents may carry
  /// large accumulated contexts (long investigations) whose single completion
  /// exceeds a short HTTP timeout; a 30s default caused sessions to die with
  /// "Request timed out" mid-investigation. 180s pairs with the 8192-token
  /// step budget (R7-4): a full step can take minutes on slower providers.
  static const Duration defaultRequestTimeout = Duration(seconds: 180);

  /// R16: a stream fails when no data arrives for this long (the whole
  /// answer may take longer than [defaultRequestTimeout]).
  static const Duration defaultStreamIdleTimeout = Duration(seconds: 60);
  final LLMConfig config;
  final http.Client _httpClient;
  final Duration _timeout;
  final Duration _streamIdleTimeout;

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
    final body = _requestBody(
      messages,
      tools: tools,
      temperature: temperature,
      maxTokens: maxTokens,
      stop: stop,
    );
    return _complete(body);
  }

  /// R17: deepseek wants the reasoning of an earlier tool-call turn back in
  /// thinking mode; other providers may reject the unknown field.
  bool get _acceptsReasoningContent {
    final endpoint = config.chatEndpoint.toLowerCase();
    return endpoint.contains('deepseek.com') ||
        config.chatModel.toLowerCase().contains('deepseek');
  }

  Map<String, dynamic> _messageJson(Message message) {
    final json = message.toJson();
    final reasoning = message.reasoningContent;
    if (reasoning != null &&
        reasoning.isNotEmpty &&
        _acceptsReasoningContent &&
        this.reasoning != ReasoningLevel.off) {
      json['reasoning_content'] = reasoning;
    }
    return json;
  }

  Map<String, dynamic> _requestBody(
    List<Message> messages, {
    List<Map<String, dynamic>>? tools,
    String? toolChoice,
    required double temperature,
    required int maxTokens,
    List<String>? stop,
    bool stream = false,
  }) =>
      {
        'model': config.chatModel,
        'messages': [for (final m in messages) _messageJson(m)],
        'temperature': temperature,
        'max_tokens': maxTokens,
        if (stream) 'stream': true,
        if (stream && !_streamOptionsRejected)
          'stream_options': {'include_usage': true},
        // Zhipu streams tool calls only when asked (default: whole at the end).
        if (stream && tools != null && tools.isNotEmpty && isZhipu(config))
          'tool_stream': true,
        if (stop != null) 'stop': stop,
        if (tools != null && tools.isNotEmpty) 'tools': tools,
        if (tools != null &&
            tools.isNotEmpty &&
            toolChoice != null &&
            acceptsToolChoice(config))
          'tool_choice': toolChoice,
        if (!_reasoningFieldsRejected) ...reasoningFields,
      };

  /// R17: function calls of a non-streamed `message`.
  static List<ToolCall> _toolCallsOf(Object? raw) {
    if (raw is! List) return const [];
    return [
      for (final (i, call) in raw.indexed)
        if (call is Map && call['function'] is Map)
          ToolCall(
            id: '${call['id'] ?? 'call_$i'}',
            name: '${(call['function'] as Map)['name'] ?? ''}',
            arguments: '${(call['function'] as Map)['arguments'] ?? ''}',
          ),
    ];
  }

  Future<ChatCompletionResult> _complete(Map<String, dynamic> body) async {
    try {
      // R8 M-E: transient network errors (backgrounding closes the socket)
      // are retried once before surfacing.
      http.Response? response;
      for (var rateRetry = 0;; rateRetry++) {
        Object? lastError;
        response = null;
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
          } on HandshakeException catch (e) {
            // TLS handshake interrupted (flakey provider/network) — retry once.
            lastError = e;
          }
        }
        if (response == null) {
          if (lastError is TimeoutException) {
            throw const LLMException('Request timed out');
          }
          throw LLMException('Network error: $lastError');
        }
        if (response.statusCode == 429 &&
            rateRetry < rateLimitBackoff.length) {
          await Future<void>.delayed(
            _rateLimitDelay(response.headers, rateRetry),
          );
          continue;
        }
        break;
      }

      // R16: always UTF-8 (as the embedding client does): without a
      // `charset` in the content type, `response.body` decodes as latin1.
      final responseBody =
          utf8.decode(response.bodyBytes, allowMalformed: true);
      if ((response.statusCode == 400 || response.statusCode == 422) &&
          _rejectsReasoningFields(body, responseBody)) {
        return await _complete(_withoutReasoningFields(body));
      }
      if (response.statusCode != 200) {
        throw LLMException(
          chatFailureMessage(responseBody,
              fallback: 'Chat completion failed',),
          statusCode: response.statusCode,
          body: responseBody,
        );
      }

      final data = jsonDecode(responseBody) as Map<String, dynamic>;
      final choices = data['choices'] as List<dynamic>;
      if (choices.isEmpty) {
        throw const LLMException('Empty response from chat completion');
      }

      final firstChoice = choices[0] as Map<String, dynamic>;
      final message = firstChoice['message'] as Map<String, dynamic>;
      final usage = _usageOf(data['usage']);
      final result = ChatCompletionResult(
        content: (message['content'] as String?) ?? '',
        finishReason: firstChoice['finish_reason'] as String?,
        promptTokens: usage.prompt,
        completionTokens: usage.completion,
        cachedPromptTokens: usage.cached,
        toolCalls: _toolCallsOf(message['tool_calls']),
        reasoningContent: (message['reasoning_content'] as String?) ?? '',
      );
      onCompletion?.call(result);
      return result;
    } on SocketException catch (e) {
      throw LLMException('Network error: ${e.message}');
    } on TimeoutException {
      throw const LLMException('Request timed out');
    }
  }

  static ({int? prompt, int? completion, int? cached}) _usageOf(
    Object? usage,
  ) {
    int? usageInt(String key) =>
        usage is Map ? (usage[key] as num?)?.toInt() : null;
    final cached = usageInt('prompt_cache_hit_tokens') ??
        (usage is Map && usage['prompt_tokens_details'] is Map
            ? ((usage['prompt_tokens_details'] as Map)['cached_tokens'] as num?)
                ?.toInt()
            : null);
    return (
      prompt: usageInt('prompt_tokens'),
      completion: usageInt('completion_tokens'),
      cached: cached,
    );
  }

  /// Status codes after which the request is retried without streaming: a
  /// provider that rejects `stream` / `stream_options` still answers.
  static const Set<int> _streamRejectedCodes = {400, 404, 415, 422};

  /// R16: server-sent events. Lines are joined across network chunks; the
  /// idle timeout applies between chunks, not to the whole answer; network
  /// errors are retried only before the first byte.
  @override
  Stream<CompletionDelta> streamCompletion(
    List<Message> messages, {
    double temperature = 0.7,
    int maxTokens = 2048,
    List<String>? stop,
  }) {
    _requireChatConfig();
    return _stream(
      _requestBody(
        messages,
        temperature: temperature,
        maxTokens: maxTokens,
        stop: stop,
        stream: true,
      ),
    );
  }

  /// R17: a streamed agent turn; tool-call fragments are joined by their
  /// `index` and handed out complete on the `done` delta.
  @override
  Stream<CompletionDelta> streamTurn(
    List<Message> messages, {
    List<Map<String, dynamic>>? tools,
    String? toolChoice,
    double temperature = 0.7,
    int maxTokens = 2048,
  }) {
    _requireChatConfig();
    return _stream(
      _requestBody(
        messages,
        tools: tools,
        toolChoice: toolChoice,
        temperature: temperature,
        maxTokens: maxTokens,
        stream: true,
      ),
    );
  }

  /// The wait before rate-limit retry [retry]: the provider's numeric
  /// `Retry-After` (capped at 30 s) or [rateLimitBackoff].
  Duration _rateLimitDelay(Map<String, String> headers, int retry) {
    final seconds = int.tryParse(headers['retry-after'] ?? '');
    if (seconds != null && seconds >= 0) {
      return Duration(seconds: seconds > 30 ? 30 : seconds);
    }
    return rateLimitBackoff[retry];
  }

  Stream<CompletionDelta> _stream(Map<String, dynamic> body) async* {
    http.StreamedResponse? response;
    for (var rateRetry = 0;; rateRetry++) {
      Object? lastError;
      response = null;
      for (var attempt = 0; attempt < 2; attempt++) {
        try {
          final request = http.Request('POST', Uri.parse(config.chatEndpoint))
            ..headers.addAll(_headers(config.chatApiKey, label: 'Chat API Key'))
            ..body = jsonEncode(body);
          response = await _httpClient.send(request).timeout(_timeout);
          break;
        } on SocketException catch (e) {
          lastError = e;
        } on http.ClientException catch (e) {
          lastError = e;
        } on TimeoutException catch (e) {
          lastError = e;
        } on HandshakeException catch (e) {
          lastError = e;
        }
      }
      if (response == null) {
        if (lastError is TimeoutException) {
          throw const LLMException('Request timed out');
        }
        throw LLMException('Network error: $lastError');
      }
      if (response.statusCode == 429 && rateRetry < rateLimitBackoff.length) {
        await response.stream.drain<void>();
        await Future<void>.delayed(
          _rateLimitDelay(response.headers, rateRetry),
        );
        continue;
      }
      break;
    }

    if (response.statusCode != 200) {
      final errorBody = await response.stream.bytesToString();
      final badRequest =
          response.statusCode == 400 || response.statusCode == 422;
      if (badRequest && _rejectsReasoningFields(body, errorBody)) {
        yield* _stream(_withoutReasoningFields(body));
        return;
      }
      if (badRequest && body.containsKey('stream_options')) {
        // Some providers stream fine but reject `stream_options`.
        _streamOptionsRejected = true;
        yield* _stream(Map.of(body)..remove('stream_options'));
        return;
      }
      if (_streamRejectedCodes.contains(response.statusCode)) {
        // Retried without streaming; a provider that also rejects the rest
        // of the request (e.g. `tools`) fails there with its own status.
        final result = await _complete(
          Map.of(body)
            ..remove('stream')
            ..remove('stream_options'),
        );
        if (result.content.isNotEmpty || result.reasoningContent.isNotEmpty) {
          yield CompletionDelta(
            content: result.content,
            reasoningContent: result.reasoningContent,
          );
        }
        yield CompletionDelta(
          done: true,
          finishReason: result.finishReason,
          promptTokens: result.promptTokens,
          completionTokens: result.completionTokens,
          cachedPromptTokens: result.cachedPromptTokens,
          toolCalls: result.toolCalls,
        );
        return;
      }
      throw LLMException(
        chatFailureMessage(errorBody, fallback: 'Chat completion failed'),
        statusCode: response.statusCode,
        body: errorBody,
      );
    }

    final content = StringBuffer();
    final reasoningBuffer = StringBuffer();
    final calls = <int, ({StringBuffer id, StringBuffer name, StringBuffer args})>{};
    String? finishReason;
    ({int? prompt, int? completion, int? cached}) usage =
        (prompt: null, completion: null, cached: null);
    try {
      final lines = response.stream
          .timeout(_streamIdleTimeout)
          .transform(utf8.decoder)
          .transform(const LineSplitter());
      await for (final line in lines) {
        if (!line.startsWith('data:')) continue;
        final data = line.substring(5).trim();
        if (data.isEmpty || data == '[DONE]') continue;
        Map<String, dynamic> json;
        try {
          json = jsonDecode(data) as Map<String, dynamic>;
        } catch (_) {
          continue; // a malformed event never ends the answer
        }
        if (json['usage'] is Map) usage = _usageOf(json['usage']);
        final choices = json['choices'];
        if (choices is! List || choices.isEmpty) continue;
        final choice = choices.first as Map<String, dynamic>;
        finishReason = (choice['finish_reason'] as String?) ?? finishReason;
        final delta = choice['delta'];
        if (delta is! Map) continue;
        final toolDeltas = delta['tool_calls'];
        if (toolDeltas is List) {
          for (final (i, raw) in toolDeltas.indexed) {
            if (raw is! Map) continue;
            final index = (raw['index'] as num?)?.toInt() ?? i;
            final call = calls.putIfAbsent(
              index,
              () => (id: StringBuffer(), name: StringBuffer(), args: StringBuffer()),
            );
            final id = raw['id'];
            if (id is String && id.isNotEmpty && call.id.isEmpty) {
              call.id.write(id);
            }
            final function = raw['function'];
            if (function is Map) {
              // Names are not split; a provider may repeat it per chunk.
              final name = function['name'];
              if (name is String && call.name.isEmpty) call.name.write(name);
              final args = function['arguments'];
              if (args is String) call.args.write(args);
            }
          }
        }
        final text = delta['content'] as String? ?? '';
        final reasoningText = delta['reasoning_content'] as String? ?? '';
        if (text.isEmpty && reasoningText.isEmpty) continue;
        content.write(text);
        reasoningBuffer.write(reasoningText);
        yield CompletionDelta(content: text, reasoningContent: reasoningText);
      }
    } on TimeoutException {
      throw const LLMException('Request timed out');
    } on SocketException catch (e) {
      throw LLMException('Network error: ${e.message}');
    } on http.ClientException catch (e) {
      throw LLMException('Network error: ${e.message}');
    }

    final indexes = calls.keys.toList()..sort();
    final toolCalls = [
      for (final index in indexes)
        if (calls[index]!.name.isNotEmpty)
          ToolCall(
            id: calls[index]!.id.isEmpty
                ? 'call_$index'
                : calls[index]!.id.toString(),
            name: calls[index]!.name.toString(),
            arguments: calls[index]!.args.toString(),
          ),
    ];
    onCompletion?.call(
      ChatCompletionResult(
        content: content.toString(),
        finishReason: finishReason,
        promptTokens: usage.prompt,
        completionTokens: usage.completion,
        cachedPromptTokens: usage.cached,
        toolCalls: toolCalls,
        reasoningContent: reasoningBuffer.toString(),
      ),
    );
    yield CompletionDelta(
      done: true,
      finishReason: finishReason,
      promptTokens: usage.prompt,
      completionTokens: usage.completion,
      cachedPromptTokens: usage.cached,
      toolCalls: toolCalls,
    );
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
