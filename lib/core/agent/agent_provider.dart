import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../gamedata/gamedata_knowledge_store.dart';
import '../llm/llm_client.dart';
import '../llm/llm_provider.dart';
import 'react_loop.dart';
import 'fact_check_agent.dart';
import 'roleplay_agent.dart';
import 'roleplay_session_store.dart';
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
  final FactCheckVerdict? factCheckVerdict;
  final DateTime timestamp;

  const ChatMessage({
    required this.id,
    required this.role,
    required this.content,
    this.steps = const [],
    this.isStreaming = false,
    this.isError = false,
    this.factCheckVerdict,
    required this.timestamp,
  });

  ChatMessage copyWith({
    String? id,
    MessageRole? role,
    String? content,
    List<ReActStep>? steps,
    bool? isStreaming,
    bool? isError,
    FactCheckVerdict? factCheckVerdict,
    DateTime? timestamp,
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
    );
  }
}

/// Provider for the [SummaryAgent] instance.
final summaryAgentProvider = Provider<SummaryAgent>((ref) {
  final llm = ref.watch(llmClientProvider);

  return SummaryAgent(
    llmClient: llm,
  );
});

final factCheckAgentProvider = Provider<FactCheckAgent>((ref) {
  return FactCheckAgent(llmClient: ref.watch(llmClientProvider));
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

class FactCheckChatNotifier extends StateNotifier<List<ChatMessage>> {
  final FactCheckAgent _agent;
  int _requestGeneration = 0;

  FactCheckChatNotifier(this._agent) : super([]);

  Future<void> sendMessage(String text) async {
    final claim = text.trim();
    if (claim.isEmpty || state.any((message) => message.isStreaming)) return;
    final generation = ++_requestGeneration;
    final history = _buildHistory(state);
    final assistantId = _uuid.v4();
    state = [
      ...state,
      ChatMessage(
        id: _uuid.v4(),
        role: MessageRole.user,
        content: claim,
        timestamp: DateTime.now(),
      ),
      ChatMessage(
        id: assistantId,
        role: MessageRole.assistant,
        content: '',
        isStreaming: true,
        timestamp: DateTime.now(),
      ),
    ];

    final steps = <ReActStep>[];
    try {
      await for (final event
          in _agent.checkClaim(claim: claim, history: history)) {
        if (generation != _requestGeneration) return;
        switch (event.type) {
          case ReActEventType.thought:
          case ReActEventType.toolObservation:
          case ReActEventType.error:
            steps.add(ReActStep(
              type: event.type,
              content: event.content,
              toolName: event.toolName,
            ));
            _update(
              assistantId,
              content: event.type == ReActEventType.error
                  ? '[FACT_CHECK_ERROR]'
                  : null,
              steps: List.of(steps),
              isError: event.type == ReActEventType.error,
            );
            break;
          case ReActEventType.toolCall:
            steps.add(ReActStep(
              type: event.type,
              content: event.content,
              toolName: event.toolName,
              toolArgs: event.toolArgs,
            ));
            _update(assistantId, steps: List.of(steps));
            break;
          case ReActEventType.finalAnswerToken:
            _update(
              assistantId,
              content: event.content,
              factCheckVerdict: parseFactCheckVerdict(event.content),
            );
            break;
          case ReActEventType.complete:
            _update(assistantId, isStreaming: false);
            break;
        }
      }
    } catch (_) {
      if (generation == _requestGeneration) {
        _update(assistantId,
            content: '[FACT_CHECK_ERROR]', isError: true, isStreaming: false);
      }
    }
  }

  void cancel() {
    _requestGeneration++;
    state = [
      for (final message in state)
        if (message.isStreaming)
          message.copyWith(
            content: '[FACT_CHECK_CANCELED]',
            isStreaming: false,
            isError: true,
          )
        else
          message,
    ];
  }

  Future<void> retryLast() async {
    final users = state.where((message) => message.role == MessageRole.user);
    if (users.isEmpty || state.any((message) => message.isStreaming)) return;
    final claim = users.last.content;
    if (state.isNotEmpty && state.last.role == MessageRole.assistant) {
      state = state.sublist(0, state.length - 1);
    }
    if (state.isNotEmpty && state.last.role == MessageRole.user) {
      state = state.sublist(0, state.length - 1);
    }
    await sendMessage(claim);
  }

  void clearChat() {
    cancel();
    state = [];
  }

  List<Message> _buildHistory(List<ChatMessage> messages) => [
        for (final message in messages)
          if (!message.isStreaming && !message.isError)
            message.role == MessageRole.user
                ? Message.user(message.content)
                : Message.assistant(message.content),
      ];

  void _update(
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
}

final factCheckChatProvider =
    StateNotifierProvider<FactCheckChatNotifier, List<ChatMessage>>((ref) {
  return FactCheckChatNotifier(ref.watch(factCheckAgentProvider));
});

class RoleplayState {
  final GameDataEntityCandidate? character;
  final List<GameDataEntityCandidate> candidates;
  final String scene;
  final List<ChatMessage> messages;
  final bool isResolving;
  final bool hasSavedSession;
  final CharacterResolutionStatus? resolutionStatus;

  const RoleplayState({
    this.character,
    this.candidates = const [],
    this.scene = '',
    this.messages = const [],
    this.isResolving = false,
    this.hasSavedSession = false,
    this.resolutionStatus,
  });

  bool get isSending => messages.any((message) => message.isStreaming);

  RoleplayState copyWith({
    GameDataEntityCandidate? character,
    bool clearCharacter = false,
    List<GameDataEntityCandidate>? candidates,
    String? scene,
    List<ChatMessage>? messages,
    bool? isResolving,
    bool? hasSavedSession,
    CharacterResolutionStatus? resolutionStatus,
    bool clearResolutionStatus = false,
  }) =>
      RoleplayState(
        character: clearCharacter ? null : character ?? this.character,
        candidates: candidates ?? this.candidates,
        scene: scene ?? this.scene,
        messages: messages ?? this.messages,
        isResolving: isResolving ?? this.isResolving,
        hasSavedSession: hasSavedSession ?? this.hasSavedSession,
        resolutionStatus: clearResolutionStatus
            ? null
            : resolutionStatus ?? this.resolutionStatus,
      );
}

final roleplaySessionStoreProvider =
    Provider<RoleplaySessionStore>((ref) => const RoleplaySessionStore());

final roleplayAgentProvider = Provider<RoleplayAgent>((ref) {
  return RoleplayAgent(llmClient: ref.watch(llmClientProvider));
});

class RoleplayNotifier extends StateNotifier<RoleplayState> {
  final RoleplayAgent _agent;
  final RoleplaySessionStore _sessionStore;
  int _requestGeneration = 0;

  RoleplayNotifier(this._agent, this._sessionStore)
      : super(const RoleplayState()) {
    _checkSavedSession();
  }

  Future<void> _checkSavedSession() async {
    final saved = await _sessionStore.load();
    if (saved != null && state.character == null) {
      state = state.copyWith(hasSavedSession: true);
    }
  }

  Future<void> resolveCharacter(String query, {String scene = ''}) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty || state.isResolving) return;
    state = state.copyWith(
      isResolving: true,
      candidates: const [],
      clearResolutionStatus: true,
    );
    final result = await _agent.resolveCharacter(cleanQuery);
    state = state.copyWith(
      character: result.character,
      candidates: result.candidates,
      scene: scene.trim(),
      isResolving: false,
      resolutionStatus: result.status,
    );
  }

  void selectCandidate(GameDataEntityCandidate candidate, {String? scene}) {
    state = state.copyWith(
      character: candidate,
      candidates: const [],
      scene: scene?.trim(),
      resolutionStatus: CharacterResolutionStatus.resolved,
    );
  }

  Future<void> sendMessage(String text) async {
    final message = text.trim();
    final character = state.character;
    if (message.isEmpty || character == null || state.isSending) return;
    final generation = ++_requestGeneration;
    final history = _history(state.messages);
    final assistantId = _uuid.v4();
    final firstTurn = state.messages.isEmpty;
    state = state.copyWith(messages: [
      ...state.messages,
      ChatMessage(
        id: _uuid.v4(),
        role: MessageRole.user,
        content: message,
        timestamp: DateTime.now(),
      ),
      ChatMessage(
        id: assistantId,
        role: MessageRole.assistant,
        content: '',
        isStreaming: true,
        timestamp: DateTime.now(),
      ),
    ]);
    final steps = <ReActStep>[];
    try {
      await for (final event in _agent.reply(
        character: character,
        userMessage: message,
        scene: state.scene,
        history: history,
        isFirstTurn: firstTurn,
      )) {
        if (generation != _requestGeneration) return;
        switch (event.type) {
          case ReActEventType.thought:
          case ReActEventType.toolObservation:
          case ReActEventType.error:
            steps.add(ReActStep(
                type: event.type,
                content: event.content,
                toolName: event.toolName));
            _updateMessage(assistantId,
                steps: List.of(steps),
                isError: event.type == ReActEventType.error);
            break;
          case ReActEventType.toolCall:
            steps.add(ReActStep(
              type: event.type,
              content: event.content,
              toolName: event.toolName,
              toolArgs: event.toolArgs,
            ));
            _updateMessage(assistantId, steps: List.of(steps));
            break;
          case ReActEventType.finalAnswerToken:
            _updateMessage(assistantId, content: event.content);
            break;
          case ReActEventType.complete:
            _updateMessage(assistantId, isStreaming: false);
            await _persist();
            break;
        }
      }
    } catch (_) {
      if (generation == _requestGeneration) {
        _updateMessage(assistantId,
            content: '[ROLEPLAY_ERROR]', isError: true, isStreaming: false);
      }
    }
  }

  void cancel() {
    _requestGeneration++;
    state = state.copyWith(messages: [
      for (final message in state.messages)
        if (message.isStreaming)
          message.copyWith(
              content: '[ROLEPLAY_CANCELED]', isStreaming: false, isError: true)
        else
          message,
    ]);
  }

  Future<void> retryLast() async {
    final users = state.messages.where((m) => m.role == MessageRole.user);
    if (users.isEmpty || state.isSending) return;
    final text = users.last.content;
    final messages = List<ChatMessage>.of(state.messages);
    if (messages.isNotEmpty && messages.last.role == MessageRole.assistant) {
      messages.removeLast();
    }
    if (messages.isNotEmpty && messages.last.role == MessageRole.user) {
      messages.removeLast();
    }
    state = state.copyWith(messages: messages);
    await sendMessage(text);
  }

  Future<void> continueSavedSession() async {
    final saved = await _sessionStore.load();
    if (saved == null) return;
    try {
      final characterMap = saved['character'] as Map<String, dynamic>;
      final messages = (saved['messages'] as List<dynamic>)
          .map((item) => _messageFromJson(item as Map<String, dynamic>))
          .toList(growable: false);
      state = RoleplayState(
        character: _candidateFromJson(characterMap),
        scene: saved['scene'] as String? ?? '',
        messages: messages,
        hasSavedSession: true,
        resolutionStatus: CharacterResolutionStatus.resolved,
      );
    } catch (_) {
      await _sessionStore.clear();
      state = const RoleplayState();
    }
  }

  Future<void> restart() async {
    cancel();
    await _sessionStore.clear();
    state = const RoleplayState();
  }

  List<Message> _history(List<ChatMessage> messages) => [
        for (final message in messages)
          if (!message.isStreaming && !message.isError)
            message.role == MessageRole.user
                ? Message.user(message.content)
                : Message.assistant(message.content),
      ];

  void _updateMessage(String id,
      {String? content,
      List<ReActStep>? steps,
      bool? isStreaming,
      bool? isError}) {
    state = state.copyWith(messages: [
      for (final message in state.messages)
        if (message.id == id)
          message.copyWith(
              content: content,
              steps: steps,
              isStreaming: isStreaming,
              isError: isError)
        else
          message,
    ]);
  }

  Future<void> _persist() async {
    final character = state.character;
    if (character == null) return;
    await _sessionStore.save({
      'version': 1,
      'character': _candidateToJson(character),
      'scene': state.scene,
      'messages': state.messages
          .where((message) => !message.isStreaming)
          .map(_messageToJson)
          .toList(),
    });
    state = state.copyWith(hasSavedSession: true);
  }
}

final roleplayProvider =
    StateNotifierProvider<RoleplayNotifier, RoleplayState>((ref) {
  return RoleplayNotifier(
    ref.watch(roleplayAgentProvider),
    ref.watch(roleplaySessionStoreProvider),
  );
});

Map<String, dynamic> _candidateToJson(GameDataEntityCandidate value) => {
      'entityId': value.entityId,
      'name': value.name,
      'entityType': value.entityType,
      'sourceType': value.sourceType,
      'sourcePath': value.sourcePath,
      'matchedAlias': value.matchedAlias,
      'matchType': value.matchType,
      'confidence': value.confidence,
    };

GameDataEntityCandidate _candidateFromJson(Map<String, dynamic> value) =>
    GameDataEntityCandidate(
      entityId: value['entityId'] as String,
      name: value['name'] as String,
      entityType: value['entityType'] as String,
      sourceType: value['sourceType'] as String,
      sourcePath: value['sourcePath'] as String?,
      matchedAlias: value['matchedAlias'] as String,
      matchType: value['matchType'] as String,
      confidence: (value['confidence'] as num).toDouble(),
    );

Map<String, dynamic> _messageToJson(ChatMessage value) => {
      'id': value.id,
      'role': value.role.name,
      'content': value.content,
      'isError': value.isError,
      'timestamp': value.timestamp.toIso8601String(),
    };

ChatMessage _messageFromJson(Map<String, dynamic> value) => ChatMessage(
      id: value['id'] as String,
      role: value['role'] == MessageRole.user.name
          ? MessageRole.user
          : MessageRole.assistant,
      content: value['content'] as String,
      isError: value['isError'] as bool? ?? false,
      timestamp: DateTime.parse(value['timestamp'] as String),
    );
