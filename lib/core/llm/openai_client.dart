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

  /// Set when a request with tool-call turns whose text is empty was
  /// rejected: such turns are then sent with content: null (as OpenAI
  /// documents it; Gemini's endpoint rejects an empty text part).
  bool _nullToolCallContent = false;

  static bool _hasEmptyToolCallContent(Map<String, dynamic> body) {
    final messages = body['messages'];
    return messages is List &&
        messages.any((m) => m is Map && m['tool_calls'] != null && m['content'] == '');
  }

  Map<String, dynamic> _withNullToolCallContent(Map<String, dynamic> body) {
    _nullToolCallContent = true;
    return Map.of(body)
      ..['messages'] = [
        for (final m in body['messages'] as List)
          m is Map && m['tool_calls'] != null && m['content'] == ''
              ? (Map<String, dynamic>.of(m.cast<String, dynamic>())..['content'] = null)
              : m,
      ];
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
    if (endpoint.contains('generativelanguage.googleapis.com') ||
        model.contains('gemini')) {
      // Gemini's OpenAI-compatible API: thinking counts against
      // max_tokens and cannot be switched off on every model; low
      // keeps it short. A relay that rejects the field gets the request
      // again without it.
      return switch (level) {
        ReasoningLevel.off => {'reasoning_effort': 'low'},
        ReasoningLevel.low => {'reasoning_effort': 'medium'},
        ReasoningLevel.high => {'reasoning_effort': 'high'},
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
    if (_nullToolCallContent &&
        message.toolCalls != null &&
        message.content.isEmpty) {
      json['content'] = null;
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

  Future<ChatCompletionResult> _complete(Map<String, dynamic> body) async {
    final startedAt = DateTime.now();
    var rateSleep = Duration.zero;
    var rateRetries = 0;
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
          final wait = _rateLimitDelay(response.headers, rateRetry);
          rateRetries++;
          rateSleep += wait;
          await Future<void>.delayed(wait);
          continue;
        }
        break;
      }
      final headersAt = DateTime.now();

      // R16: always UTF-8 (as the embedding client does): without a
      // `charset` in the content type, `response.body` decodes as latin1.
      final responseBody =
          utf8.decode(response.bodyBytes, allowMalformed: true);
      if ((response.statusCode == 400 || response.statusCode == 422) &&
          _rejectsReasoningFields(body, responseBody)) {
        return await _complete(_withoutReasoningFields(body));
      }
      if ((response.statusCode == 400 || response.statusCode == 422) &&
          !_nullToolCallContent &&
          _hasEmptyToolCallContent(body)) {
        return await _complete(_withNullToolCallContent(body));
      }
      if (response.statusCode != 200) {
        throw LLMException(
          chatFailureMessage(responseBody,
              fallback: 'Chat completion failed',),
          statusCode: response.statusCode,
          body: responseBody,
        );
      }

      final answer = _answerOfBody(responseBody, response.statusCode);
      final result = ChatCompletionResult(
        content: answer.content.toString(),
        finishReason: answer.finishReason,
        promptTokens: answer.usage.prompt,
        completionTokens: answer.usage.completion,
        cachedPromptTokens: answer.usage.cached,
        toolCalls: answer.toolCalls,
        reasoningContent: answer.reasoning.toString(),
        timing: CallTiming(
          startedAt: startedAt,
          endedAt: DateTime.now(),
          headersAt: headersAt,
          rateLimitRetries: rateRetries,
          rateLimitSleep: rateSleep,
        ),
      );
      onCompletion?.call(result);
      return result;
    } on SocketException catch (e) {
      throw LLMException('Network error: ${e.message}');
    } on TimeoutException {
      throw const LLMException('Request timed out');
    }
  }

  /// The answer in a response [body]: a completion, or a stream (some
  /// relays stream although not asked to, or do not although asked).
  /// Throws an [LLMException] for an error body or one with no answer.
  static _StreamAccumulator _answerOfBody(String body, int status) {
    final events = sseEvents(body);
    if (events != null) {
      final answer = _StreamAccumulator();
      events.forEach(answer.add);
      return answer;
    }
    final Object? data;
    try {
      data = jsonDecode(body);
    } on FormatException {
      throw LLMException(
        'Chat completion failed: the response is not JSON',
        statusCode: status,
        body: body,
      );
    }
    final choices = data is Map ? data['choices'] : null;
    if (choices is! List || choices.isEmpty || choices.first is! Map) {
      throw LLMException(
        data is Map && data['error'] != null
            ? chatFailureMessage(body, fallback: 'Chat completion failed')
            : 'Empty response from chat completion',
        statusCode: status,
        body: body,
      );
    }
    final choice = choices.first as Map;
    // Read as a stream of one event holding the whole message.
    return _StreamAccumulator()
      ..add({
        'choices': [
          {
            'finish_reason': choice['finish_reason'],
            'message': choice['message'] ?? choice['delta'] ?? const <String, dynamic>{},
          },
        ],
        if ((data as Map)['usage'] != null) 'usage': data['usage'],
      });
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
    final startedAt = DateTime.now();
    var rateSleep = Duration.zero;
    var rateRetries = 0;
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
        final wait = _rateLimitDelay(response.headers, rateRetry);
        rateRetries++;
        rateSleep += wait;
        await Future<void>.delayed(wait);
        continue;
      }
      break;
    }
    final headersAt = DateTime.now();
    DateTime? firstDataAt;
    DateTime? firstTokenAt;

    if (response.statusCode != 200) {
      final errorBody = await response.stream.bytesToString();
      final badRequest =
          response.statusCode == 400 || response.statusCode == 422;
      if (badRequest && _rejectsReasoningFields(body, errorBody)) {
        yield* _stream(_withoutReasoningFields(body));
        return;
      }
      if (badRequest &&
          !_nullToolCallContent &&
          _hasEmptyToolCallContent(body)) {
        yield* _stream(_withNullToolCallContent(body));
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

    final answer = _StreamAccumulator();
    // Lines that are not events: a relay that answered a stream request
    // with a plain JSON body (or an error) instead of a stream.
    final other = StringBuffer();
    try {
      final lines = response.stream
          .timeout(_streamIdleTimeout)
          .transform(utf8.decoder)
          .transform(const LineSplitter());
      await for (final line in lines) {
        if (!line.startsWith('data:')) {
          if (firstDataAt == null && other.length < 4 << 20) {
            other.writeln(line);
          }
          continue;
        }
        final data = line.substring(5).trim();
        if (data.isEmpty || data == '[DONE]') continue;
        Map<String, dynamic> json;
        try {
          json = jsonDecode(data) as Map<String, dynamic>;
        } catch (_) {
          continue; // a malformed event never ends the answer
        }
        firstDataAt ??= DateTime.now();
        final added = answer.add(json);
        if (added.text.isEmpty && added.reasoning.isEmpty) continue;
        firstTokenAt ??= DateTime.now();
        yield CompletionDelta(
          content: added.text,
          reasoningContent: added.reasoning,
        );
      }
    } on TimeoutException {
      throw const LLMException('Request timed out');
    } on SocketException catch (e) {
      throw LLMException('Network error: ${e.message}');
    } on http.ClientException catch (e) {
      throw LLMException('Network error: ${e.message}');
    }

    var whole = answer;
    if (firstDataAt == null && other.toString().trim().isNotEmpty) {
      whole = _answerOfBody(other.toString(), response.statusCode);
      if (whole.content.isNotEmpty || whole.reasoning.isNotEmpty) {
        yield CompletionDelta(
          content: whole.content.toString(),
          reasoningContent: whole.reasoning.toString(),
        );
      }
    }
    final toolCalls = whole.toolCalls;
    onCompletion?.call(
      ChatCompletionResult(
        content: whole.content.toString(),
        finishReason: whole.finishReason,
        promptTokens: whole.usage.prompt,
        completionTokens: whole.usage.completion,
        cachedPromptTokens: whole.usage.cached,
        toolCalls: toolCalls,
        reasoningContent: whole.reasoning.toString(),
        timing: CallTiming(
          startedAt: startedAt,
          endedAt: DateTime.now(),
          headersAt: headersAt,
          firstDataAt: firstDataAt,
          firstTokenAt: firstTokenAt,
          rateLimitRetries: rateRetries,
          rateLimitSleep: rateSleep,
          streamed: true,
        ),
      ),
    );
    yield CompletionDelta(
      done: true,
      finishReason: whole.finishReason,
      promptTokens: whole.usage.prompt,
      completionTokens: whole.usage.completion,
      cachedPromptTokens: whole.usage.cached,
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

/// Text of a message's `content`: a string, or a list of parts (some relays
/// and multimodal providers) whose text parts are joined; thinking parts are
/// left out.
String completionText(Object? content) {
  if (content is String) return content;
  if (content is! List) return '';
  final out = StringBuffer();
  for (final part in content) {
    if (part is String) {
      out.write(part);
    } else if (part is Map && part['text'] is String) {
      final type = part['type'];
      if (type == null || type == 'text' || type == 'output_text') {
        out.write(part['text']);
      }
    }
  }
  return out.toString();
}

/// Hidden reasoning of a message or delta, under the names providers use
/// (`reasoning_content`: deepseek, GLM; `reasoning`: OpenRouter and some
/// relays; `thinking`).
String completionReasoning(Map<dynamic, dynamic> message) {
  for (final key in const ['reasoning_content', 'reasoning', 'thinking']) {
    final value = message[key];
    if (value is String && value.isNotEmpty) return value;
  }
  return '';
}

/// Collects one streamed answer from its server-sent events (also used for
/// a stream that came back to a request that did not ask for one).
class _StreamAccumulator {
  final StringBuffer content = StringBuffer();
  final StringBuffer reasoning = StringBuffer();
  final Map<int, ({StringBuffer id, StringBuffer name, StringBuffer args})>
      _calls = {};
  String? finishReason;
  ({int? prompt, int? completion, int? cached}) usage =
      (prompt: null, completion: null, cached: null);

  /// Adds one event; returns its new text and reasoning. Throws an
  /// [LLMException] for an error event (some relays answer 200 and put the
  /// error in the stream).
  ({String text, String reasoning}) add(Map<String, dynamic> json) {
    const none = (text: '', reasoning: '');
    if (json['error'] != null && json['choices'] == null) {
      throw LLMException(
        chatFailureMessage(jsonEncode(json), fallback: 'Chat completion failed'),
        body: jsonEncode(json),
      );
    }
    if (json['usage'] is Map) {
      usage = OpenAICompatibleClient._usageOf(json['usage']);
    }
    final choices = json['choices'];
    if (choices is! List || choices.isEmpty || choices.first is! Map) {
      return none;
    }
    final choice = choices.first as Map;
    finishReason = (choice['finish_reason'] as String?) ?? finishReason;
    // A whole `message` instead of a `delta` (some relays, or a final
    // event repeating the answer): taken only while nothing came as deltas.
    final delta = choice['delta'] is Map
        ? choice['delta'] as Map
        : (choice['message'] is Map &&
                content.isEmpty &&
                reasoning.isEmpty &&
                _calls.isEmpty
            ? choice['message'] as Map
            : null);
    if (delta == null) return none;
    // A whole message lists its calls in order (often without index).
    final whole = choice['delta'] is! Map;
    final toolDeltas = delta['tool_calls'];
    if (toolDeltas is List) {
      for (final (i, raw) in toolDeltas.indexed) {
        if (raw is! Map) continue;
        final call = _calls.putIfAbsent(
          whole ? i : _indexOf(raw, i),
          () => (id: StringBuffer(), name: StringBuffer(), args: StringBuffer()),
        );
        final id = raw['id'];
        if (id is String && id.isNotEmpty && call.id.isEmpty) call.id.write(id);
        final function = raw['function'];
        if (function is Map) {
          // Names are not split; a provider may repeat it per chunk.
          final name = function['name'];
          if (name is String && call.name.isEmpty) call.name.write(name);
          final args = function['arguments'];
          if (args is String) {
            call.args.write(args);
          } else if (args is Map) {
            call.args.write(jsonEncode(args));
          }
        }
      }
    }
    final text = completionText(delta['content']);
    final thought = completionReasoning(delta);
    content.write(text);
    reasoning.write(thought);
    return (text: text, reasoning: thought);
  }

  /// The call a fragment belongs to: its `index`; without one (some
  /// providers send each call whole, unnumbered) a new call when it brings
  /// an id not seen yet, else the latest call.
  int _indexOf(Map<dynamic, dynamic> raw, int position) {
    final index = raw['index'];
    if (index is num) return index.toInt();
    if (_calls.isEmpty) return position;
    final id = raw['id'];
    if (id is String && id.isNotEmpty) {
      for (final e in _calls.entries) {
        if (e.value.id.toString() == id) return e.key;
      }
      return _calls.keys.reduce((a, b) => a > b ? a : b) + 1;
    }
    return _calls.keys.reduce((a, b) => a > b ? a : b);
  }

  List<ToolCall> get toolCalls {
    final indexes = _calls.keys.toList()..sort();
    return [
      for (final index in indexes)
        if (_calls[index]!.name.isNotEmpty)
          ToolCall(
            id: _calls[index]!.id.isEmpty
                ? 'call_$index'
                : _calls[index]!.id.toString(),
            name: _calls[index]!.name.toString(),
            arguments: _calls[index]!.args.toString(),
          ),
    ];
  }
}

/// The events of a server-sent-events [body] (lines `data: {...}`), or null
/// when it is not one.
List<Map<String, dynamic>>? sseEvents(String body) {
  if (!body.trimLeft().startsWith('data:') &&
      !body.contains('\ndata:')) {
    return null;
  }
  final events = <Map<String, dynamic>>[];
  for (final line in const LineSplitter().convert(body)) {
    if (!line.startsWith('data:')) continue;
    final data = line.substring(5).trim();
    if (data.isEmpty || data == '[DONE]') continue;
    try {
      final json = jsonDecode(data);
      if (json is Map<String, dynamic>) events.add(json);
    } catch (_) {}
  }
  return events;
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
