import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../llm/llm_client.dart';
import 'chat_message.dart';
import 'fact_check_agent.dart';
import 'react_loop.dart';

/// Rebuilds ReAct step text history from UI messages (shared by the Summary
/// and Investigation chat notifiers): user messages pass through; assistant
/// messages are reconstructed as Thought/Action/Action Input/Observation text
/// plus the final answer.
List<Message> buildReactHistory(List<ChatMessage> messages) {
  final history = <Message>[];
  for (final m in messages) {
    if (m.isStreaming || m.isError) continue;
    if (m.role == MessageRole.user) {
      history.add(Message.user(m.content));
    } else if (m.role == MessageRole.assistant) {
      final buffer = StringBuffer();
      for (final step in m.steps) {
        if (step.type == ReActEventType.thought) {
          buffer.writeln('Thought: ${step.content}');
        } else if (step.type == ReActEventType.toolCall) {
          buffer.writeln('Action: ${step.toolName}');
          // Content matches 'Executing tool "..." with arguments: {...}'
          final argsPart = step.content.contains('arguments: ')
              ? step.content.split('arguments: ').last
              : '{}';
          buffer.writeln('Action Input: $argsPart');
        } else if (step.type == ReActEventType.toolObservation) {
          buffer.writeln('Observation: ${step.content}');
        }
      }
      if (m.content.isNotEmpty) {
        buffer.writeln('Thought: I have enough information to answer.');
        buffer.writeln('Final Answer: ${m.content}');
      }
      history.add(Message.assistant(buffer.toString().trim()));
    }
  }
  return history;
}

/// Shared state-machine logic for the Summary / Fact-check / Role-play chat
/// notifiers: request generations for cancellation, message list updates,
/// cancel/retry/clear behaviors, and LLM history reconstruction.
///
/// Workflow-specific behavior stays in the concrete notifiers; this base only
/// owns the mechanics every chat surface needs.
abstract class ChatNotifierBase extends StateNotifier<List<ChatMessage>> {
  ChatNotifierBase(super.initial);

  final Uuid _uuid = Uuid();
  int _requestGeneration = 0;

  /// True while any assistant message is still streaming.
  bool get isStreaming => state.any((message) => message.isStreaming);

  /// Rebuilds the LLM-visible history from UI messages.
  ///
  /// Subclasses override when they need to reconstruct ReAct step text
  /// (Summary) or keep verdict markers (Fact-check).
  List<Message> buildHistory(List<ChatMessage> messages) => [
        for (final message in messages)
          if (!message.isStreaming && !message.isError)
            message.role == MessageRole.user
                ? Message.user(message.content)
                : Message.assistant(message.content),
      ];

  /// Generates a fresh id for a new message.
  String newId() => _uuid.v4();

  /// Bumps the request generation so late responses can be ignored.
  void invalidatePending() => _requestGeneration++;

  /// Advances and returns the request generation for a new request.
  int nextGeneration() => ++_requestGeneration;

  /// True when [generation] is still the active one.
  bool isCurrentGeneration(int generation) =>
      generation == _requestGeneration;

  /// Updates one message in the list by id.
  void updateMessage(
    String id, {
    String? content,
    List<ReActStep>? steps,
    bool? isStreaming,
    bool? isError,
    FactCheckVerdict? factCheckVerdict,
  }) {
    state = [
      for (final message in state)
        if (message.id == id)
          message.copyWith(
            content: content,
            steps: steps,
            isStreaming: isStreaming,
            isError: isError,
            factCheckVerdict: factCheckVerdict,
          )
        else
          message,
    ];
  }

  /// Marker text used when canceling an in-flight stream; subclasses override
  /// to expose workflow-specific markers (e.g. `[FACT_CHECK_CANCELED]`).
  String get canceledMarker => '[CANCELED]';

  /// Cancels the in-flight request and marks streaming messages as canceled.
  void cancel() {
    invalidatePending();
    state = [
      for (final message in state)
        if (message.isStreaming)
          message.copyWith(
            content: canceledMarker,
            isStreaming: false,
            isError: true,
          )
        else
          message,
    ];
  }

  /// Re-sends the last user message after removing the failed assistant turn.
  Future<void> retryLast() async {
    final users = state.where((message) => message.role == MessageRole.user);
    if (users.isEmpty || isStreaming) return;
    final query = users.last.content;
    if (state.isNotEmpty && state.last.role == MessageRole.assistant) {
      state = state.sublist(0, state.length - 1);
    }
    if (state.isNotEmpty && state.last.role == MessageRole.user) {
      state = state.sublist(0, state.length - 1);
    }
    await resendLast(query);
  }

  /// Sends (or re-sends) a user message. Implemented by each workflow.
  Future<void> resendLast(String query);

  /// Clears the chat history.
  void clearChat() {
    cancel();
    state = [];
  }
}
