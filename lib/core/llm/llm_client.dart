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

/// Configuration for an LLM client.
///
/// All fields are user-configurable via the Settings page.
class LLMConfig {
  final String baseUrl;
  final String apiKey;
  final String chatModel;
  final String embeddingModel;

  const LLMConfig({
    this.baseUrl = 'https://api.openai.com/v1',
    this.apiKey = '',
    this.chatModel = 'gpt-4o-mini',
    this.embeddingModel = 'text-embedding-3-small',
  });

  LLMConfig copyWith({
    String? baseUrl,
    String? apiKey,
    String? chatModel,
    String? embeddingModel,
  }) =>
      LLMConfig(
        baseUrl: baseUrl ?? this.baseUrl,
        apiKey: apiKey ?? this.apiKey,
        chatModel: chatModel ?? this.chatModel,
        embeddingModel: embeddingModel ?? this.embeddingModel,
      );

  /// Returns `true` if a valid API key is configured.
  bool get isValid => apiKey.isNotEmpty;

  /// Returns the URL suffix for chat completions endpoint.
  String get chatEndpoint => '$baseUrl/chat/completions';

  /// Returns the URL suffix for embeddings endpoint.
  String get embeddingEndpoint => '$baseUrl/embeddings';
}

/// Exception thrown by LLM operations.
class LLMException implements Exception {
  final String message;
  final int? statusCode;
  final String? body;

  const LLMException(this.message, {this.statusCode, this.body});

  @override
  String toString() => 'LLMException: $message${statusCode != null ? ' ($statusCode)' : ''}';
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
  });

  /// Sends a chat completion request and streams the response tokens
  /// via the [onToken] callback. Returns the full assembled response.
  Future<String> chatStream(
    List<Message> messages, {
    void Function(String token)? onToken,
    double temperature = 0.7,
    int maxTokens = 2048,
  });

  /// Embeds a single text string into a vector.
  Future<List<double>> embed(String text);

  /// Embeds a batch of text strings into vectors.
  Future<List<List<double>>> embedBatch(List<String> texts);
}
