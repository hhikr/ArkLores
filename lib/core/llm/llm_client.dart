/// Abstract interface for LLM clients.
///
/// ArkLores uses an OpenAI-compatible API (user brings their own key).
/// Implementations must support Chat Completion.
library;

/// Role of a message in a conversation.
enum MessageRole {
  system,
  user,
  assistant,
  tool;

  String get jsonValue => name;

  static MessageRole fromJson(String value) {
    return MessageRole.values.firstWhere(
      (r) => r.name == value,
      orElse: () => MessageRole.user,
    );
  }
}

/// A single message in a conversation.
class Message {

  const Message({
    required this.role,
    required this.content,
    this.toolCallId,
    this.toolCalls,
    this.reasoningContent,
  });

  factory Message.system(String content) =>
      Message(role: MessageRole.system, content: content);

  factory Message.user(String content) =>
      Message(role: MessageRole.user, content: content);

  factory Message.assistant(String content) =>
      Message(role: MessageRole.assistant, content: content);

  /// R17: an assistant turn that called [calls].
  factory Message.assistantToolCalls(
    String content,
    List<ToolCall> calls, {
    String? reasoningContent,
  }) =>
      Message(
        role: MessageRole.assistant,
        content: content,
        toolCalls: [for (final call in calls) call.toJson()],
        reasoningContent: reasoningContent,
      );

  /// R17: the result of the tool call [callId].
  factory Message.toolResult(String callId, String content) =>
      Message(role: MessageRole.tool, content: content, toolCallId: callId);

  final MessageRole role;
  final String content;
  final String? toolCallId;
  final List<Map<String, dynamic>>? toolCalls;

  /// R17: hidden reasoning of an assistant tool-call turn. Thinking-mode
  /// providers (deepseek) require it back within the same question; the
  /// client sends it only to providers that accept it.
  final String? reasoningContent;

  Map<String, dynamic> toJson() => {
        'role': role.jsonValue,
        'content': content,
        if (toolCallId != null) 'tool_call_id': toolCallId,
        if (toolCalls != null) 'tool_calls': toolCalls,
      };
}

/// R17: one function call requested by the model.
class ToolCall {
  const ToolCall({
    required this.id,
    required this.name,
    required this.arguments,
  });

  final String id;
  final String name;

  /// Raw JSON arguments as the model wrote them (may be malformed).
  final String arguments;

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': 'function',
        'function': {'name': name, 'arguments': arguments},
      };
}

/// Configuration for LLM API connections.
class LLMConfig {

  const LLMConfig({
    this.chatBaseUrl = 'https://api.z.ai/api/paas/v4',
    this.chatApiKey = '',
    this.chatModel = 'glm-5.3-flash',
  });
  // ── Chat API ─────────────────────────────────────────────
  final String chatBaseUrl;
  final String chatApiKey;
  final String chatModel;

  LLMConfig copyWith({
    String? chatBaseUrl,
    String? chatApiKey,
    String? chatModel,
  }) =>
      LLMConfig(
        chatBaseUrl: chatBaseUrl ?? this.chatBaseUrl,
        chatApiKey: chatApiKey ?? this.chatApiKey,
        chatModel: chatModel ?? this.chatModel,
      );

  /// Returns `true` if a chat API key is configured.
  bool get isValid => chatApiKey.isNotEmpty;

  static String? apiKeyFormatError(String apiKey, {String label = 'API Key'}) {
    final trimmed = apiKey.trim();
    if (trimmed.isEmpty) return null;
    if (trimmed != apiKey) {
      return '$label format is invalid. Please paste only the API key, without leading or trailing spaces.';
    }
    if (trimmed.length > 512 ||
        trimmed.contains(RegExp(r'\s')) ||
        trimmed.codeUnits.any((unit) => unit < 0x21 || unit > 0x7e)) {
      return '$label format is invalid. Please paste only the API key, not an error message or other text.';
    }
    return null;
  }

  /// Returns the full URL for chat completions endpoint.
  String get chatEndpoint => '$chatBaseUrl/chat/completions';
}

/// Exception thrown by LLM operations.
class LLMException implements Exception {

  const LLMException(this.message, {this.statusCode, this.body});
  final String message;
  final int? statusCode;
  final String? body;

  @override
  String toString() =>
      'LLMException: $message${statusCode != null ? ' ($statusCode)' : ''}';
}

/// Metadata returned by a chat completion.
class ChatCompletionResult {

  const ChatCompletionResult({
    required this.content,
    this.finishReason,
    this.promptTokens,
    this.completionTokens,
    this.cachedPromptTokens,
    this.toolCalls = const [],
    this.reasoningContent = '',
  });
  final String content;
  final String? finishReason;

  /// R17: function calls of this turn (empty for a plain answer).
  final List<ToolCall> toolCalls;

  /// R17: hidden reasoning of this turn, when the provider returns it.
  final String reasoningContent;

  /// Provider-reported usage (null when the provider omits it). Hidden
  /// reasoning tokens are included in [completionTokens].
  final int? promptTokens;
  final int? completionTokens;
  final int? cachedPromptTokens;

  bool get wasTruncated => finishReason == 'length';
}

/// R16: how much hidden reasoning a call may use. Mapped to each provider's
/// own switch; for providers without a known switch nothing is sent.
enum ReasoningLevel { off, low, high }

/// One increment of a streamed completion (R16). The last delta of a stream
/// has [done] set and carries [finishReason] and usage when the provider
/// reports them.
class CompletionDelta {
  const CompletionDelta({
    this.content = '',
    this.reasoningContent = '',
    this.done = false,
    this.finishReason,
    this.promptTokens,
    this.completionTokens,
    this.cachedPromptTokens,
    this.toolCalls = const [],
  });

  /// R17: the completed function calls of the turn, set on the `done` delta.
  final List<ToolCall> toolCalls;

  /// Visible answer text of this increment.
  final String content;

  /// Hidden-reasoning text of this increment (shown live, never persisted).
  final String reasoningContent;
  final bool done;
  final String? finishReason;
  final int? promptTokens;
  final int? completionTokens;
  final int? cachedPromptTokens;
}

/// Collects a delta stream into the completed result, forwarding each delta
/// to [onDelta] as it arrives.
Future<ChatCompletionResult> collectCompletion(
  Stream<CompletionDelta> deltas, {
  void Function(CompletionDelta delta)? onDelta,
}) async {
  final content = StringBuffer();
  final reasoning = StringBuffer();
  CompletionDelta? last;
  await for (final delta in deltas) {
    content.write(delta.content);
    reasoning.write(delta.reasoningContent);
    onDelta?.call(delta);
    if (delta.done) last = delta;
  }
  return ChatCompletionResult(
    content: content.toString(),
    finishReason: last?.finishReason,
    promptTokens: last?.promptTokens,
    completionTokens: last?.completionTokens,
    cachedPromptTokens: last?.cachedPromptTokens,
    toolCalls: last?.toolCalls ?? const [],
    reasoningContent: reasoning.toString(),
  );
}

/// Abstract LLM client interface.
///
/// Implementations connect to OpenAI-compatible APIs.
abstract class LLMClient {
  /// Sends a chat completion request and returns the response text.
  Future<String> chat(
    List<Message> messages, {
    List<Map<String, dynamic>>? tools,
    double temperature = 0.7,
    int maxTokens = 2048,
    List<String>? stop,
  });

  /// Sends a chat completion request and returns response metadata.
  ///
  /// Existing clients can keep implementing [chat]; this default adapter
  /// preserves compatibility while newer clients expose provider finish
  /// reasons such as `length`.
  Future<ChatCompletionResult> chatCompletion(
    List<Message> messages, {
    List<Map<String, dynamic>>? tools,
    double temperature = 0.7,
    int maxTokens = 2048,
    List<String>? stop,
  }) async {
    final content = await chat(
      messages,
      tools: tools,
      temperature: temperature,
      maxTokens: maxTokens,
      stop: stop,
    );
    return ChatCompletionResult(content: content);
  }

  /// R16: streams a chat completion as [CompletionDelta]s; the last one has
  /// `done` set. This default yields the whole [chatCompletion] result at
  /// once, so clients without streaming (and test fakes) still work.
  Stream<CompletionDelta> streamCompletion(
    List<Message> messages, {
    double temperature = 0.7,
    int maxTokens = 2048,
    List<String>? stop,
  }) async* {
    final result = await chatCompletion(
      messages,
      temperature: temperature,
      maxTokens: maxTokens,
      stop: stop,
    );
    yield CompletionDelta(content: result.content);
    yield CompletionDelta(
      done: true,
      finishReason: result.finishReason,
      promptTokens: result.promptTokens,
      completionTokens: result.completionTokens,
      cachedPromptTokens: result.cachedPromptTokens,
    );
  }

  /// R17: one streamed agent turn with function calling. [tools] are
  /// OpenAI-style function definitions; [toolChoice] `none` forbids calls
  /// (the final answer after the turn limit). The `done` delta carries the
  /// turn's [CompletionDelta.toolCalls]. This default runs [chatCompletion]
  /// once, so clients and fakes without streaming still work.
  Stream<CompletionDelta> streamTurn(
    List<Message> messages, {
    List<Map<String, dynamic>>? tools,
    String? toolChoice,
    double temperature = 0.7,
    int maxTokens = 2048,
  }) async* {
    final result = await chatCompletion(
      messages,
      tools: tools,
      temperature: temperature,
      maxTokens: maxTokens,
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
  }
}
