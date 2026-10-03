import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../llm/llm_client.dart';
import 'chat_message.dart';
import 'fact_check_agent.dart';
import 'react_loop.dart';
import 'story_answer.dart';
import 'tools/observation_data.dart';

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

/// R14: compact history for the story QA pipeline. Each earlier turn is the
/// user question plus the final answer (envelope stripped) and the chapters
/// that turn actually READ, so a follow-up question knows the context and
/// can re-read those chapters directly. Tool observations are NOT replayed
/// (they bloated every planner request and duplicated what the answer and
/// the read list already say). Only the last [maxTurns] turns are kept.
List<Message> buildStoryQaHistory(
  List<ChatMessage> messages, {
  int maxTurns = 3,
}) {
  final history = <Message>[];
  for (final m in messages) {
    if (m.isStreaming || m.isError) continue;
    if (m.role == MessageRole.user) {
      history.add(Message.user(m.content));
      continue;
    }
    if (m.role != MessageRole.assistant) continue;
    final reads = <String, List<(int, int)>>{};
    for (final step in m.steps) {
      if (step.type != ReActEventType.toolObservation) continue;
      for (final block in parseDataBlocks(step.content)) {
        if (block['type'] != 'read_story_lines') continue;
        final storyId = '${block['story_id'] ?? ''}';
        final first = (block['first_line'] as num?)?.toInt();
        final last = (block['last_line'] as num?)?.toInt();
        if (storyId.isEmpty || first == null || last == null) continue;
        reads.putIfAbsent(storyId, () => []).add((first, last));
      }
    }
    final buffer = StringBuffer(
      m.content.replaceAll(storyAnswerEnvelopePattern, '').trim(),
    );
    if (reads.isNotEmpty) {
      final list = reads.entries
          .map((e) =>
              '${e.key}:${e.value.map((r) => '${r.$1}-${r.$2}').join(',')}',)
          .join('；');
      buffer.write('\n\n（这一轮已读原文: $list）');
    }
    history.add(Message.assistant(buffer.toString().trim()));
  }
  // Keep whole turns: drop from the front until at most maxTurns user turns.
  var users = history.where((m) => m.role == MessageRole.user).length;
  while (users > maxTurns && history.isNotEmpty) {
    final removed = history.removeAt(0);
    if (removed.role == MessageRole.user) users--;
    while (history.isNotEmpty && history.first.role != MessageRole.user) {
      history.removeAt(0);
    }
  }
  return history;
}

/// R16: coalesces streamed-text updates so the message list (and its
/// Markdown) is rebuilt at most once per [interval], not once per token.
class StreamCoalescer {
  StreamCoalescer(
    this._flush, {
    this.interval = const Duration(milliseconds: 60),
  });

  final void Function() _flush;
  final Duration interval;
  Timer? _timer;

  /// Flushes once [interval] after the first pending change.
  void schedule() {
    _timer ??= Timer(interval, () {
      _timer = null;
      _flush();
    });
  }

  /// Flushes now (end of stream, a replace, an error).
  void flushNow() {
    cancel();
    _flush();
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
  }
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
    String? reasoning,
    String? liveStatus,
  }) {
    if (!mounted) return;
    state = [
      for (final message in state)
        if (message.id == id)
          message.copyWith(
            content: content,
            steps: steps,
            isStreaming: isStreaming,
            isError: isError,
            factCheckVerdict: factCheckVerdict,
            reasoning: reasoning,
            liveStatus: liveStatus,
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
