import '../llm/llm_client.dart';
import 'react_event.dart';
import 'story_answer.dart';
import 'turn_stats.dart';

/// One step in the ReAct loop process.
class ReActStep {
  const ReActStep({
    required this.type,
    required this.content,
    this.toolName,
    this.toolArgs,
    this.subtask,
  });

  final ReActEventType type;
  final String content;
  final String? toolName;
  final Map<String, dynamic>? toolArgs;

  /// 0.14: the sub-agent this step belongs to (see [ReActEvent.subtask]).
  final int? subtask;
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
    this.stats,
  });

  final String id;

  /// What the question cost (tokens, calls, time); null for sessions saved
  /// before v0.10.7 and for messages that are not answers.
  final TurnStats? stats;
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
    TurnStats? stats,
  }) {
    return ChatMessage(
      stats: stats ?? this.stats,
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
