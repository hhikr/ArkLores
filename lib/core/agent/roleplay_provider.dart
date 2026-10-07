/// The role-play tab's state: the character, the conversation, the saved
/// session (one file, picked up again on the next start).
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../background/background_work.dart';
import '../gamedata/gamedata_knowledge_store.dart';
import '../llm/llm_client.dart';
import '../llm/llm_provider.dart';
import 'chat_message.dart';
import 'chat_notifier_base.dart';
import 'react_loop.dart';
import 'roleplay_agent.dart';
import 'roleplay_session_store.dart';

class RoleplayState {

  const RoleplayState({
    this.character,
    this.candidates = const [],
    this.scene = '',
    this.messages = const [],
    this.isResolving = false,
    this.hasSavedSession = false,
    this.resolutionStatus,
  });
  final GameDataEntityCandidate? character;
  final List<GameDataEntityCandidate> candidates;
  final String scene;
  final List<ChatMessage> messages;
  final bool isResolving;
  final bool hasSavedSession;
  final CharacterResolutionStatus? resolutionStatus;

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
  return RoleplayAgent(
    llmClient: ref.watch(llmClientProvider(ReasoningLevel.off)),
  );
});

class RoleplayNotifier extends StateNotifier<RoleplayState> {

  RoleplayNotifier(this._agent, this._sessionStore)
      : super(const RoleplayState()) {
    _checkSavedSession();
  }
  final RoleplayAgent _agent;
  final RoleplaySessionStore _sessionStore;
  final Uuid _uuid = Uuid();
  int _requestGeneration = 0;

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
    try {
      final result = await _agent.resolveCharacter(cleanQuery);
      state = state.copyWith(
        character: result.character,
        candidates: result.candidates,
        scene: scene.trim(),
        isResolving: false,
        resolutionStatus: result.status,
      );
    } catch (_) {
      // Do not stay "resolving" forever when the lookup fails.
      state = state.copyWith(isResolving: false);
    }
  }

  void selectCandidate(GameDataEntityCandidate candidate, {String? scene}) {
    state = state.copyWith(
      character: candidate,
      candidates: const [],
      scene: scene?.trim(),
      resolutionStatus: CharacterResolutionStatus.resolved,
    );
  }

  Future<void> sendMessage(String text) => BackgroundWork.instance.run(
        BackgroundWork.text('正在生成回复', 'Generating a reply'),
        () => _sendMessage(text),
      );

  Future<void> _sendMessage(String text) async {
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
    ],);
    final steps = <ReActStep>[];
    var answer = '';
    final coalescer = StreamCoalescer(() {
      if (generation == _requestGeneration && mounted) {
        _updateMessage(assistantId, content: answer);
      }
    });
    try {
      await for (final event in _agent.reply(
        character: character,
        userMessage: message,
        scene: state.scene,
        history: history,
        isFirstTurn: firstTurn,
      )) {
        if (generation != _requestGeneration) {
          coalescer.cancel();
          return;
        }
        switch (event.type) {
          case ReActEventType.thought:
          case ReActEventType.toolObservation:
          case ReActEventType.error:
            steps.add(ReActStep(
                type: event.type,
                content: event.content,
                toolName: event.toolName,),);
            _updateMessage(assistantId,
                steps: List.of(steps),
                isError: event.type == ReActEventType.error,);
            break;
          case ReActEventType.toolCall:
            steps.add(ReActStep(
              type: event.type,
              content: event.content,
              toolName: event.toolName,
              toolArgs: event.toolArgs,
            ),);
            _updateMessage(assistantId, steps: List.of(steps));
            break;
          case ReActEventType.finalAnswerToken:
            // R16: tokens append (the old handler replaced the text with
            // each 120-char chunk, so long replies showed only their tail).
            answer = applyAnswerEvent(answer, event);
            coalescer.schedule();
            break;
          case ReActEventType.finalAnswerReset:
          case ReActEventType.finalAnswerReplace:
            answer = applyAnswerEvent(answer, event);
            coalescer.flushNow();
            break;
          case ReActEventType.reasoningToken:
          case ReActEventType.status:
            break;
          case ReActEventType.complete:
            coalescer.flushNow();
            _updateMessage(assistantId, isStreaming: false);
            await _persist();
            break;
        }
      }
    } catch (_) {
      coalescer.cancel();
      if (generation == _requestGeneration) {
        _updateMessage(assistantId,
            content: '[ROLEPLAY_ERROR]', isError: true, isStreaming: false,);
      }
    }
  }

  void cancel() {
    _requestGeneration++;
    state = state.copyWith(messages: [
      for (final message in state.messages)
        if (message.isStreaming)
          message.copyWith(
              content: '[ROLEPLAY_CANCELED]', isStreaming: false, isError: true,)
        else
          message,
    ],);
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
      bool? isError,}) {
    state = state.copyWith(messages: [
      for (final message in state.messages)
        if (message.id == id)
          message.copyWith(
              content: content,
              steps: steps,
              isStreaming: isStreaming,
              isError: isError,)
        else
          message,
    ],);
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
