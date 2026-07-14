/// Abstract interface for LLM clients.
///
/// ArkLores uses an OpenAI-compatible API (user brings their own key).
/// Implementations must support Chat Completion and Embedding.
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
  final MessageRole role;
  final String content;
  final String? toolCallId;
  final List<Map<String, dynamic>>? toolCalls;

  const Message({
    required this.role,
    required this.content,
    this.toolCallId,
    this.toolCalls,
  });

  Map<String, dynamic> toJson() => {
        'role': role.jsonValue,
        'content': content,
        if (toolCallId != null) 'tool_call_id': toolCallId,
        if (toolCalls != null) 'tool_calls': toolCalls,
      };

  factory Message.system(String content) =>
      Message(role: MessageRole.system, content: content);

  factory Message.user(String content) =>
      Message(role: MessageRole.user, content: content);

  factory Message.assistant(String content) =>
      Message(role: MessageRole.assistant, content: content);
}

/// Configuration for LLM API connections.
///
/// Chat and Embedding can use different providers (e.g. DeepSeek for
/// chat + OpenAI for embeddings). When [embedApiKey] is empty, the
/// embedding layer falls back to the chat config at runtime.
class LLMConfig {
  // ── Chat API ─────────────────────────────────────────────
  final String chatBaseUrl;
  final String chatApiKey;
  final String chatModel;

  // ── Embedding API ────────────────────────────────────────
  final String embedBaseUrl;
  final String embedApiKey;
  final String embedModel;

  const LLMConfig({
    this.chatBaseUrl = 'https://api.deepseek.com/v1',
    this.chatApiKey = '',
    this.chatModel = 'deepseek-v4-flash',
    this.embedBaseUrl = 'https://api.openai.com/v1',
    this.embedApiKey = '',
    this.embedModel = 'text-embedding-3-small',
  });

  LLMConfig copyWith({
    String? chatBaseUrl,
    String? chatApiKey,
    String? chatModel,
    String? embedBaseUrl,
    String? embedApiKey,
    String? embedModel,
  }) =>
      LLMConfig(
        chatBaseUrl: chatBaseUrl ?? this.chatBaseUrl,
        chatApiKey: chatApiKey ?? this.chatApiKey,
        chatModel: chatModel ?? this.chatModel,
        embedBaseUrl: embedBaseUrl ?? this.embedBaseUrl,
        embedApiKey: embedApiKey ?? this.embedApiKey,
        embedModel: embedModel ?? this.embedModel,
      );

  /// Returns `true` if a chat API key is configured (embedding optional).
  bool get isValid => chatApiKey.isNotEmpty;

  /// Returns the full URL for chat completions endpoint.
  String get chatEndpoint => '$chatBaseUrl/chat/completions';

  /// Returns the full URL for embeddings endpoint.
  String get embeddingEndpoint => '$embedBaseUrl/embeddings';
}

/// Exception thrown by LLM operations.
class LLMException implements Exception {
  final String message;
  final int? statusCode;
  final String? body;

  const LLMException(this.message, {this.statusCode, this.body});

  @override
  String toString() =>
      'LLMException: $message${statusCode != null ? ' ($statusCode)' : ''}';
}

/// Metadata returned by a chat completion.
class ChatCompletionResult {
  final String content;
  final String? finishReason;

  const ChatCompletionResult({
    required this.content,
    this.finishReason,
  });

  bool get wasTruncated => finishReason == 'length';
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

  /// Sends a chat completion request and streams the response tokens
  /// via the [onToken] callback. Returns the full assembled response.
  Future<String> chatStream(
    List<Message> messages, {
    void Function(String token)? onToken,
    double temperature = 0.7,
    int maxTokens = 2048,
    List<String>? stop,
  });

  /// Embeds a single text string into a vector.
  Future<List<double>> embed(String text);

  /// Embeds a batch of text strings into vectors.
  Future<List<List<double>>> embedBatch(List<String> texts);
}
