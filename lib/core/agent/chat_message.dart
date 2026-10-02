import '../llm/llm_client.dart';
import 'fact_check_agent.dart';
import 'react_loop.dart';

/// One step in the ReAct loop process.
class ReActStep {
  const ReActStep({
    required this.type,
    required this.content,
    this.toolName,
    this.toolArgs,
  });

  final ReActEventType type;
  final String content;
  final String? toolName;
  final Map<String, dynamic>? toolArgs;
}

/// Message model for AI chats.
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.role,
    required this.content,
    this.steps = const [],
    this.isStreaming = false,
    this.isError = false,
    this.factCheckVerdict,
    required this.timestamp,
    this.reasoning = '',
    this.liveStatus = '',
  });

  final String id;
  final MessageRole role;
  final String content;
  final List<ReActStep> steps;
  final bool isStreaming;
  final bool isError;
  final FactCheckVerdict? factCheckVerdict;
  final DateTime timestamp;

  /// R16: hidden reasoning streamed while the answer is written; shown live,
  /// never persisted.
  final String reasoning;

  /// R16: what the run is doing right now, for the status line ('' = none).
  final String liveStatus;

  ChatMessage copyWith({
    String? id,
    MessageRole? role,
    String? content,
    List<ReActStep>? steps,
    bool? isStreaming,
    bool? isError,
    FactCheckVerdict? factCheckVerdict,
    DateTime? timestamp,
    String? reasoning,
    String? liveStatus,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      role: role ?? this.role,
      content: content ?? this.content,
      steps: steps ?? this.steps,
      isStreaming: isStreaming ?? this.isStreaming,
      isError: isError ?? this.isError,
      factCheckVerdict: factCheckVerdict ?? this.factCheckVerdict,
      timestamp: timestamp ?? this.timestamp,
      reasoning: reasoning ?? this.reasoning,
      liveStatus: liveStatus ?? this.liveStatus,
    );
  }
}
