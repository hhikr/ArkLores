import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../shared/providers/settings_provider.dart';
import '../background/background_work.dart';
import '../gamedata/gamedata_knowledge_store.dart';
import '../llm/llm_client.dart';
import '../llm/llm_provider.dart';
import '../llm/usage_meter.dart';
import 'agent_logger.dart';
import 'chat_message.dart';
import 'chat_notifier_base.dart';
import 'chat_session_models.dart';
import 'chat_session_store.dart';
import 'react_loop.dart';
import 'roleplay_agent.dart';
import 'roleplay_session_store.dart';
import 'story_answer.dart';
import 'story_qa_agent.dart';
import 'turn_stats.dart';

export 'chat_message.dart';

/// Shared GameData retrieval store injected into every agent (R11.2): agents
/// type their store as the `GameDataRetrieval` interface so the same tool
/// classes also run on the desktop CLI with an FFI-backed store. The mobile
/// provider supplies the concrete Sqlite store.
final sharedGameDataStoreProvider = Provider<GameDataKnowledgeStore>((ref) {
  return GameDataKnowledgeStore();
});

/// The story QA pipeline: one agent for every question. Story questions run
/// without hidden reasoning unless "深度思考" is on (R16/R17).
final storyQaAgentProvider = Provider<StoryQaAgent>((ref) {
  return StoryQaAgent(
    llmClient: ref.watch(llmClientProvider(ReasoningLevel.off)),
    gameDataStore: ref.watch(sharedGameDataStoreProvider),
    embeddingClient: ref.watch(embeddingClientProvider),
    usage: ref.watch(usageMeterProvider),
  );
});

/// Ask chat: one message list; every question runs the one story QA
/// pipeline ([StoryQaAgent] -> `LoreAgentLoop`). The ReAct event handling
/// below turns its events into the message list; a claim check's verdict is
/// parsed from the answer whenever its marker is present.
///
/// Session persistence (R5): when recording is enabled ([AgentLogger.isEnabled],
/// the "保存 AI 对话记录" setting), every turn — including the complete
/// ReAct chain (raw LLM responses, thoughts, tool calls, observations), the
/// final answer and what it cost — is appended to one per-conversation JSON
/// file in the user-visible `chat_sessions/` directory. Sessions can be
/// restored through [loadSession] (history list → continue conversation).
class AskChatNotifier extends ChatNotifierBase {
  AskChatNotifier({
    required StoryQaAgent agent,
    ChatSessionStore sessionStore = const ChatSessionStore(),
    required LLMConfig Function() configReader,
    LLMClient? Function()? clientReader,
    UsageMeter? usage,
  })  : _agent = agent,
        _sessionStore = sessionStore,
        _configReader = configReader,
        _clientReader = clientReader,
        _usage = usage,
        super([]);

  /// R16: the client for the next question (the thinking client when
  /// "深度思考" is on); null keeps the agent's own client.
  final LLMClient? Function()? _clientReader;

  /// Adds up the usage of every LLM call of the running question (all
  /// clients report into it); null in tests that do not look at it.
  final UsageMeter? _usage;

  /// R17: the tool agent's conversation after each answer (by assistant
  /// message id), so a follow-up continues with the text already read.
  /// In memory only; a restored session starts from the answer texts.
  final Map<String, LoreConversation> _conversations = {};
  final StoryQaAgent _agent;
  final ChatSessionStore _sessionStore;
  final LLMConfig Function() _configReader;
  ChatSessionFile? _currentSession;

  /// Whether session recording is active for the current conversation.
  static bool get recordingEnabled => AgentLogger.isEnabled;

  /// Title prefix length for the session list.
  static const int _titleMaxChars = 40;

  /// Starts a fresh conversation (clears the UI and ends the current session
  /// file; the next message begins a new session).
  void newSession() {
    cancel();
    _currentSession = null;
    _conversations.clear();
    state = const [];
  }

  /// Restores a persisted session into the UI. Subsequent messages continue
  /// the same session file.
  void loadSession(ChatSessionFile session) {
    _currentSession = session;
    _conversations.clear();
    state = chatSessionToMessages(session);
  }

  ChatSessionFile? get currentSession => _currentSession;

  @override
  void clearChat() {
    cancel();
    _currentSession = null;
    _conversations.clear();
    state = const [];
  }

  /// An answer takes minutes: it runs under the background service, so
  /// leaving the app does not cut it.
  Future<void> sendMessage(String text) => BackgroundWork.instance.run(
        BackgroundWork.text('正在回答问题', 'Answering a question'),
        () => _sendMessage(text),
      );

  Future<void> _sendMessage(String text) async {
    final query = text.trim();
    if (query.isEmpty || state.any((message) => message.isStreaming)) return;
    final generation = nextGeneration();
    final history = buildHistory(state);

    // R17: continue the last answer's conversation when it is the last
    // message (an error or a cancel in between starts from the texts).
    final lastMessage = state.isEmpty ? null : state.last;
    final prior = lastMessage == null || lastMessage.role != MessageRole.assistant
        ? null
        : _conversations[lastMessage.id];

    final assistantId = newId();
    state = [
      ...state,
      ChatMessage(
        id: newId(),
        role: MessageRole.user,
        content: query,
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

    // Session recording state for this turn.
    final recording = recordingEnabled;
    final turnStart = DateTime.now();
    // What the question costs, shown live under the answer (every LLM call
    // of every client reports into the meter).
    final usage = _usage;
    TurnStats currentStats() =>
        TurnStats.of(usage!, DateTime.now().difference(turnStart));
    if (usage != null) {
      usage.reset();
      usage.onChanged = () {
        if (isCurrentGeneration(generation)) {
          updateMessage(assistantId, stats: currentStats());
        }
      };
    }
    final config = _configReader();
    final iterations = <int, ReActIterationRecord>{};
    var currentIteration = 0;
    var turnStatus = ChatTurnStatus.completed;
    String? turnError;
    var canceled = false;
    if (recording) {
      _currentSession ??= ChatSessionFile(
        sessionId: newId(),
        createdAt: turnStart,
        updatedAt: turnStart,
        title: _truncateTitle(query),
      );
    }
    final session = _currentSession;

    // Receives the full raw LLM response of every iteration (untruncated)
    // before the corresponding thought/tool events arrive, so event handling
    // below fills the same record.
    void Function(int iteration, String rawResponse)? onRaw;

    if (recording) {
      onRaw = (iteration, raw) {
        currentIteration = iteration;
        iterations[iteration] = ReActIterationRecord(
          iteration: iteration,
          rawResponse: raw,
        );
      };
    }


    void onConversation(LoreConversation conversation) =>
        _conversations[assistantId] = conversation;
    final client = _clientReader?.call();
    final stream = _agent.run(
      query: query,
      history: history,
      client: client,
      onRawLlmResponse: onRaw,
      prior: prior,
      onConversation: onConversation,
    );

    final steps = <ReActStep>[];
    // R16: streamed answer text and live reasoning, pushed to the UI at most
    // once per coalescer interval.
    var answer = '';
    final reasoning = StringBuffer();
    final coalescer = StreamCoalescer(() {
      if (!isCurrentGeneration(generation)) return;
      updateMessage(
        assistantId,
        content: answer,
        reasoning: reasoning.toString(),
        factCheckVerdict: parseFactCheckVerdict(answer),
      );
    });

    try {
      await for (final event in stream) {
        if (!isCurrentGeneration(generation)) {
          canceled = true;
          break;
        }
        switch (event.type) {
          case ReActEventType.thought:
            steps.add(ReActStep(
              type: event.type,
              content: event.content,
            ),);
            updateMessage(assistantId, steps: List.of(steps));
            if (recording) {
              iterations.putIfAbsent(
                currentIteration,
                () => ReActIterationRecord(
                  iteration: currentIteration,
                  rawResponse: '',
                ),
              ).thought = event.content;
            }
            break;
          case ReActEventType.toolCall:
            steps.add(ReActStep(
              type: event.type,
              content: event.content,
              toolName: event.toolName,
              toolArgs: event.toolArgs,
            ),);
            updateMessage(assistantId, steps: List.of(steps));
            if (recording) {
              final record = iterations.putIfAbsent(
                currentIteration,
                () => ReActIterationRecord(
                  iteration: currentIteration,
                  rawResponse: '',
                ),
              );
              record
                ..tool = event.toolName
                ..toolArgs = event.toolArgs
                ..action = event.toolName ?? ''
                ..actionInput = event.toolArgs == null
                    ? ''
                    : const JsonEncoder().convert(event.toolArgs!);
            }
            break;
          case ReActEventType.toolObservation:
            steps.add(ReActStep(
              type: event.type,
              content: event.content,
              toolName: event.toolName,
            ),);
            updateMessage(assistantId, steps: List.of(steps));
            if (recording) {
              iterations.putIfAbsent(
                currentIteration,
                () => ReActIterationRecord(
                  iteration: currentIteration,
                  rawResponse: '',
                ),
              ).observation = event.content;
            }
            break;
          case ReActEventType.finalAnswerToken:
            // Only the fact-check workflow produces a verdict banner; other
            // modes may still contain a marker in text, which chat_bubble
            // strips from the markdown body.
            answer = applyAnswerEvent(answer, event);
            coalescer.schedule();
            break;
          case ReActEventType.finalAnswerReset:
            answer = '';
            steps.add(ReActStep(type: event.type, content: event.content));
            updateMessage(assistantId, steps: List.of(steps));
            coalescer.flushNow();
            break;
          case ReActEventType.finalAnswerReplace:
            answer = event.content;
            coalescer.flushNow();
            break;
          case ReActEventType.reasoningToken:
            reasoning.write(event.content);
            coalescer.schedule();
            break;
          case ReActEventType.status:
            updateMessage(assistantId, liveStatus: event.content);
            break;
          case ReActEventType.error:
            coalescer.cancel();
            steps.add(ReActStep(type: event.type, content: event.content));
            turnError = event.content;
            turnStatus = ChatTurnStatus.error;
            updateMessage(
              assistantId,
              content: '[ASK_ERROR]',
              isError: true,
              steps: List.of(steps),
            );
            break;
          case ReActEventType.complete:
            coalescer.flushNow();
            updateMessage(
              assistantId,
              isStreaming: false,
              steps: List.of(steps),
              // The thinking stays (in memory only) so the panel above
              // the answer does not vanish and shift the text being read.
              liveStatus: '',
            );
            break;
        }
      }
    } catch (e) {
      coalescer.cancel();
      if (isCurrentGeneration(generation)) {
        updateMessage(
          assistantId,
          content: '[ASK_ERROR]',
          isError: true,
          isStreaming: false,
        );
        turnStatus = ChatTurnStatus.error;
        turnError = '$e';
      }
    } finally {
      coalescer.cancel();
      TurnStats? stats;
      if (usage != null) {
        usage.onChanged = null;
        stats = currentStats();
        // The final totals stay under the answer (also when it failed or
        // was canceled: that run still cost something).
        updateMessage(assistantId, stats: stats);
      }
      if (recording && session != null) {
        await _finalizeTurn(
          session: session,
          query: query,
          stats: stats,
          config: config,
          turnStart: turnStart,
          iterations: iterations,
          answer: answer,
          status: canceled ? ChatTurnStatus.canceled : turnStatus,
          error: canceled ? '[ASK_CANCELED]' : turnError,
        );
      }
    }
  }

  Future<void> _finalizeTurn({
    required ChatSessionFile session,
    required String query,
    required TurnStats? stats,
    required LLMConfig config,
    required DateTime turnStart,
    required Map<int, ReActIterationRecord> iterations,
    required String answer,
    required ChatTurnStatus status,
    required String? error,
    String? memory,
  }) async {
    final sorted = iterations.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final now = DateTime.now();
    final turn = ChatSessionTurn(
      turn: session.turns.length + 1,
      timestamp: turnStart,
      query: query,
      model: config.chatModel,
      baseUrl: config.chatBaseUrl,
      iterations: [for (final entry in sorted) entry.value],
      answer: answer,
      verdict: parseFactCheckVerdict(answer),
      usage: stats,
      timeline: _usage?.timeline(turnStart),
      status: status,
      error: error,
      durationMs: now.difference(turnStart).inMilliseconds,
      memory: memory,
    );
    final updated = ChatSessionFile(
      sessionId: session.sessionId,
      createdAt: session.createdAt,
      updatedAt: now,
      title: session.title,
      turns: [...session.turns, turn],
    );
    _currentSession = updated;
    await _sessionStore.save(updated);
  }

  static String _truncateTitle(String query) => query.length <= _titleMaxChars
      ? query
      : '${query.substring(0, _titleMaxChars)}…';

  @override
  String get canceledMarker => '[ASK_CANCELED]';

  @override
  Future<void> resendLast(String query) => sendMessage(query);

  @override
  List<Message> buildHistory(List<ChatMessage> messages) =>
      buildStoryQaHistory(messages);
}

/// Provider for the chat session store (persistence + history list).
final chatSessionStoreProvider =
    Provider<ChatSessionStore>((ref) => const ChatSessionStore());

/// Session summaries for the Chat History list (newest first).
final chatHistoryListProvider =
    FutureProvider<List<ChatSessionSummary>>((ref) async {
  return ref.watch(chatSessionStoreProvider).list();
});

/// Provider for the unified Ask chat state.
final askChatProvider =
    StateNotifierProvider<AskChatNotifier, List<ChatMessage>>((ref) {
  return AskChatNotifier(
    agent: ref.watch(storyQaAgentProvider),
    usage: ref.watch(usageMeterProvider),
    sessionStore: ref.watch(chatSessionStoreProvider),
    configReader: () => ref.read(apiConfigProvider),
    // R16: read per question, so the switch never rebuilds the notifier
    // (which would drop the conversation).
    clientReader: () => ref.read(deepThinkingProvider)
        ? ref.read(llmClientProvider(ReasoningLevel.low))
        : null,
  );
});

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
