import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../llm/llm_client.dart';
import '../llm/llm_provider.dart';
import '../rag/embedder_provider.dart';
import '../rag/vector_store_provider.dart';
import '../../shared/providers/settings_provider.dart';
import 'react_loop.dart';
import 'summary_agent.dart';

const _uuid = Uuid();

/// One step in the ReAct loop process.
class ReActStep {
  final ReActEventType type;
  final String content;
  final String? toolName;
  final Map<String, dynamic>? toolArgs;

  const ReActStep({
    required this.type,
    required this.content,
    this.toolName,
    this.toolArgs,
  });
}

/// Message model for AI chats.
class ChatMessage {
  final String id;
  final MessageRole role;
  final String content;
  final List<ReActStep> steps;
  final bool isStreaming;
  final bool isError;
  final DateTime timestamp;

  const ChatMessage({
    required this.id,
    required this.role,
    required this.content,
    this.steps = const [],
    this.isStreaming = false,
    this.isError = false,
    required this.timestamp,
  });

  ChatMessage copyWith({
    String? id,
    MessageRole? role,
    String? content,
    List<ReActStep>? steps,
    bool? isStreaming,
    bool? isError,
    DateTime? timestamp,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      role: role ?? this.role,
      content: content ?? this.content,
      steps: steps ?? this.steps,
      isStreaming: isStreaming ?? this.isStreaming,
      isError: isError ?? this.isError,
      timestamp: timestamp ?? this.timestamp,
    );
  }
}

/// Provider for the [SummaryAgent] instance.
final summaryAgentProvider = Provider<SummaryAgent>((ref) {
  final llm = ref.watch(llmClientProvider);
  final embedder = ref.watch(embedderProvider);
  final vectorStore = ref.watch(vectorStoreProvider);
  final activeProfile = ref.watch(embeddingSettingsProvider).activeProfile;

  return SummaryAgent(
    llmClient: llm,
    embedder: embedder,
    vectorStore: vectorStore,
    profileId: activeProfile?.id,
  );
});

/// State notifier for Summary Chat history and processing.
class SummaryChatNotifier extends StateNotifier<List<ChatMessage>> {
  final SummaryAgent _agent;

  SummaryChatNotifier(this._agent) : super([]);

  /// Sends a message and triggers the Summary Agent ReAct stream.
  Future<void> sendMessage(String text) async {
    if (text.trim().isEmpty) return;

    final userMsgId = _uuid.v4();
    final assistantMsgId = _uuid.v4();
    final now = DateTime.now();

    final userMsg = ChatMessage(
      id: userMsgId,
      role: MessageRole.user,
      content: text,
      timestamp: now,
    );

    // Build history for the LLM before adding the new user message to the state
    final history = <Message>[];
    for (final m in state) {
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

    state = [...state, userMsg];

    final placeholderAssistant = ChatMessage(
      id: assistantMsgId,
      role: MessageRole.assistant,
      content: '',
      isStreaming: true,
      timestamp: DateTime.now(),
    );

    state = [...state, placeholderAssistant];

    try {
      final stream = _agent.generateSummary(query: text, history: history);
      final steps = <ReActStep>[];
      var finalAnswerBuffer = StringBuffer();

      await for (final event in stream) {
        switch (event.type) {
          case ReActEventType.thought:
            steps.add(ReActStep(type: event.type, content: event.content));
            _updateAssistantMessage(assistantMsgId, steps: List.from(steps));
            break;
          case ReActEventType.toolCall:
            steps.add(ReActStep(
              type: event.type,
              content: event.content,
              toolName: event.toolName,
              toolArgs: event.toolArgs,
            ));
            _updateAssistantMessage(assistantMsgId, steps: List.from(steps));
            break;
          case ReActEventType.toolObservation:
            steps.add(ReActStep(
              type: event.type,
              content: event.content,
              toolName: event.toolName,
            ));
            _updateAssistantMessage(assistantMsgId, steps: List.from(steps));
            break;
          case ReActEventType.finalAnswerToken:
            finalAnswerBuffer.write(event.content);
            _updateAssistantMessage(
              assistantMsgId,
              content: finalAnswerBuffer.toString(),
              steps: List.from(steps),
            );
            break;
          case ReActEventType.error:
            steps.add(ReActStep(type: event.type, content: event.content));
            _updateAssistantMessage(
              assistantMsgId,
              isError: true,
              steps: List.from(steps),
            );
            break;
          case ReActEventType.complete:
            _updateAssistantMessage(
              assistantMsgId,
              isStreaming: false,
              steps: List.from(steps),
            );
            break;
        }
      }
    } catch (e) {
      _updateAssistantMessage(
        assistantMsgId,
        content: 'An unexpected error occurred: $e',
        isError: true,
        isStreaming: false,
      );
    }
  }

  /// Clears the chat history.
  void clearChat() {
    state = [];
  }

  void _updateAssistantMessage(
    String id, {
    String? content,
    List<ReActStep>? steps,
    bool? isStreaming,
    bool? isError,
  }) {
    state = [
      for (final m in state)
        if (m.id == id)
          m.copyWith(
            content: content ?? m.content,
            steps: steps ?? m.steps,
            isStreaming: isStreaming ?? m.isStreaming,
            isError: isError ?? m.isError,
          )
        else
          m
    ];
  }
}

/// Provider for the Summary Chat state.
final summaryChatProvider =
    StateNotifierProvider<SummaryChatNotifier, List<ChatMessage>>((ref) {
  final agent = ref.watch(summaryAgentProvider);
  return SummaryChatNotifier(agent);
});
