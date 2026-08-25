import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../shared/providers/settings_provider.dart';
import '../gamedata/gamedata_knowledge_store.dart';
import '../llm/llm_client.dart';
import '../llm/llm_provider.dart';
import 'agent_logger.dart';
import 'chat_message.dart';
import 'chat_notifier_base.dart';
import 'chat_session_models.dart';
import 'chat_session_store.dart';
import 'fact_check_agent.dart';
import 'investigation_agent.dart';
import 'question_router.dart';
import 'react_loop.dart';
import 'roleplay_agent.dart';
import 'roleplay_session_store.dart';
import 'summary_agent.dart';

export 'chat_message.dart';

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
class SummaryChatNotifier extends ChatNotifierBase {

  SummaryChatNotifier(this._agent) : super([]);
  final SummaryAgent _agent;

  /// Sends a message and triggers the Summary Agent ReAct stream.
  Future<void> sendMessage(String text) async {
    if (text.trim().isEmpty || state.any((message) => message.isStreaming)) {
      return;
    }
    final generation = nextGeneration();

    final userMsgId = newId();
    final assistantMsgId = newId();
    final now = DateTime.now();

    final userMsg = ChatMessage(
      id: userMsgId,
      role: MessageRole.user,
      content: text,
      timestamp: now,
    );

    // Build history for the LLM before adding the new user message to the state
    final history = buildHistory(state);

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
      final finalAnswerBuffer = StringBuffer();

      await for (final event in stream) {
        if (!isCurrentGeneration(generation)) return;
        switch (event.type) {
          case ReActEventType.thought:
            steps.add(ReActStep(type: event.type, content: event.content));
            updateMessage(assistantMsgId, steps: List.from(steps));
            break;
          case ReActEventType.toolCall:
            steps.add(ReActStep(
              type: event.type,
              content: event.content,
              toolName: event.toolName,
              toolArgs: event.toolArgs,
            ),);
            updateMessage(assistantMsgId, steps: List.from(steps));
            break;
          case ReActEventType.toolObservation:
            steps.add(ReActStep(
              type: event.type,
              content: event.content,
              toolName: event.toolName,
            ),);
            updateMessage(assistantMsgId, steps: List.from(steps));
            break;
          case ReActEventType.finalAnswerToken:
            finalAnswerBuffer.write(event.content);
            updateMessage(
              assistantMsgId,
              content: finalAnswerBuffer.toString(),
              steps: List.from(steps),
            );
            break;
          case ReActEventType.error:
            steps.add(ReActStep(type: event.type, content: event.content));
            updateMessage(
              assistantMsgId,
              isError: true,
              steps: List.from(steps),
            );
            break;
          case ReActEventType.complete:
            updateMessage(
              assistantMsgId,
              isStreaming: false,
              steps: List.from(steps),
            );
            break;
        }
      }
    } catch (e) {
      if (isCurrentGeneration(generation)) {
        updateMessage(
          assistantMsgId,
          content: '[SUMMARY_ERROR]',
          isError: true,
          isStreaming: false,
        );
      }
    }
  }

  @override
  String get canceledMarker => '[SUMMARY_CANCELED]';

  @override
  Future<void> resendLast(String query) => sendMessage(query);

  @override
  List<Message> buildHistory(List<ChatMessage> messages) =>
      buildReactHistory(messages);
}

/// Provider for the Summary Chat state.
final summaryChatProvider =
    StateNotifierProvider<SummaryChatNotifier, List<ChatMessage>>((ref) {
  final agent = ref.watch(summaryAgentProvider);
  return SummaryChatNotifier(agent);
});

class FactCheckChatNotifier extends ChatNotifierBase {

  FactCheckChatNotifier(this._agent) : super([]);
  final FactCheckAgent _agent;

  Future<void> sendMessage(String text) async {
    final claim = text.trim();
    if (claim.isEmpty || state.any((message) => message.isStreaming)) return;
    final generation = nextGeneration();
    final history = buildHistory(state);
    final assistantId = newId();
    state = [
      ...state,
      ChatMessage(
        id: newId(),
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
        if (!isCurrentGeneration(generation)) return;
        switch (event.type) {
          case ReActEventType.thought:
          case ReActEventType.toolObservation:
          case ReActEventType.error:
            steps.add(ReActStep(
              type: event.type,
              content: event.content,
              toolName: event.toolName,
            ),);
            updateMessage(
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
            ),);
            updateMessage(assistantId, steps: List.of(steps));
            break;
          case ReActEventType.finalAnswerToken:
            updateMessage(
              assistantId,
              content: event.content,
              factCheckVerdict: parseFactCheckVerdict(event.content),
            );
            break;
          case ReActEventType.complete:
            updateMessage(assistantId, isStreaming: false);
            break;
        }
      }
    } catch (_) {
      if (isCurrentGeneration(generation)) {
        updateMessage(assistantId,
            content: '[FACT_CHECK_ERROR]', isError: true, isStreaming: false,);
      }
    }
  }

  @override
  String get canceledMarker => '[FACT_CHECK_CANCELED]';

  @override
  Future<void> resendLast(String query) => sendMessage(query);
}

final factCheckChatProvider =
    StateNotifierProvider<FactCheckChatNotifier, List<ChatMessage>>((ref) {
  return FactCheckChatNotifier(ref.watch(factCheckAgentProvider));
});

/// Selected mode of the AI Ask tab (auto routes via [QuestionRouter]).
final aiModeProvider = StateProvider<AiMode>((ref) => AiMode.auto);

/// Unified Ask chat: one message list, three workflows, optional auto-routing.
///
/// The Ask tab merges the previous Summary / Fact-check / Investigation tabs.
/// In [AiMode.auto] the [QuestionRouter] classifies the question first; the
/// other modes pin the workflow directly. The ReAct event handling is shared
/// across workflows; a fact-check verdict is parsed from the stream whenever
/// present, other modes simply produce no verdict.
///
/// Session persistence (R5): when recording is enabled ([AgentLogger.isEnabled],
/// the "保存 AI 对话记录" setting), every turn — including the user-selected
/// mode, the auto-routing decision and raw classification output, the complete
/// ReAct chain (raw LLM responses, thoughts, tool calls, observations) and the
/// final answer — is appended to one per-conversation JSON file in the
/// user-visible `chat_sessions/` directory. Sessions can be restored through
/// [loadSession] (history list → continue conversation).
class AskChatNotifier extends ChatNotifierBase {
  AskChatNotifier({
    required SummaryAgent summaryAgent,
    required FactCheckAgent factCheckAgent,
    required InvestigationAgent investigationAgent,
    required QuestionRouter router,
    ChatSessionStore sessionStore = const ChatSessionStore(),
    required LLMConfig Function() configReader,
  })  : _summaryAgent = summaryAgent,
        _factCheckAgent = factCheckAgent,
        _investigationAgent = investigationAgent,
        _router = router,
        _sessionStore = sessionStore,
        _configReader = configReader,
        super([]);
  final SummaryAgent _summaryAgent;
  final FactCheckAgent _factCheckAgent;
  final InvestigationAgent _investigationAgent;
  final QuestionRouter _router;
  final ChatSessionStore _sessionStore;
  final LLMConfig Function() _configReader;
  AiMode _lastMode = AiMode.auto;
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
    state = const [];
  }

  /// Restores a persisted session into the UI. Subsequent messages continue
  /// the same session file.
  void loadSession(ChatSessionFile session) {
    _currentSession = session;
    if (session.turns.isNotEmpty) {
      _lastMode = session.turns.last.effectiveMode;
    }
    state = chatSessionToMessages(session);
  }

  ChatSessionFile? get currentSession => _currentSession;

  @override
  void clearChat() {
    cancel();
    _currentSession = null;
    state = const [];
  }

  Future<void> sendMessage(String text, {required AiMode mode}) async {
    final query = text.trim();
    if (query.isEmpty || state.any((message) => message.isStreaming)) return;
    _lastMode = mode;
    final generation = nextGeneration();
    final history = buildHistory(state);
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

    // Auto mode: classify the question first, keep the router's raw decision.
    RouteResult? routeResult;
    var effective = mode;
    if (effective == AiMode.auto) {
      routeResult = await _router.route(query);
      effective = routeResult.mode;
    }
    final effectiveMode = effective;

    // Session recording state for this turn.
    final recording = recordingEnabled;
    final turnStart = DateTime.now();
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
    String? turnMemory;
    if (recording) {
      onRaw = (iteration, raw) {
        currentIteration = iteration;
        iterations[iteration] = ReActIterationRecord(
          iteration: iteration,
          rawResponse: raw,
        );
      };
    }
    void onMemory(String memoryBlock) => turnMemory = memoryBlock;

    final stream = switch (effectiveMode) {
      AiMode.verify => _factCheckAgent.checkClaim(
          claim: query,
          history: history,
          onRawLlmResponse: onRaw,
          onMemoryChanged: recording ? onMemory : null,
        ),
      AiMode.investigate => _investigationAgent.investigate(
          query: query,
          history: history,
          onRawLlmResponse: onRaw,
          onMemoryChanged: recording ? onMemory : null,
        ),
      AiMode.summarize || AiMode.auto => _summaryAgent.generateSummary(
          query: query,
          history: history,
          onRawLlmResponse: onRaw,
          onMemoryChanged: recording ? onMemory : null,
        ),
    };

    final steps = <ReActStep>[];
    final finalAnswerBuffer = StringBuffer();

    // Auto routing failures are surfaced to the user instead of silently
    // degrading (M3): the step area shows why the pinned fallback mode was
    // used. The session record keeps the router error too.
    if (routeResult?.failed ?? false) {
      steps.add(ReActStep(
        type: ReActEventType.error,
        content: '自动模式分类失败，已回退到概括模式（原因: ${routeResult!.error}）',
      ),);
      updateMessage(assistantId, steps: List.of(steps));
    }

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
            finalAnswerBuffer.write(event.content);
            updateMessage(
              assistantId,
              content: finalAnswerBuffer.toString(),
              // Only the fact-check workflow produces a verdict banner; other
              // modes may still contain a marker in text, which chat_bubble
              // strips from the markdown body.
              factCheckVerdict: effectiveMode == AiMode.verify
                  ? parseFactCheckVerdict(finalAnswerBuffer.toString())
                  : null,
              steps: List.of(steps),
            );
            break;
          case ReActEventType.error:
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
            updateMessage(
              assistantId,
              isStreaming: false,
              steps: List.of(steps),
            );
            break;
        }
      }
    } catch (e) {
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
      if (recording && session != null) {
        await _finalizeTurn(
          session: session,
          query: query,
          userMode: mode,
          effectiveMode: effectiveMode,
          routeResult: routeResult,
          config: config,
          turnStart: turnStart,
          iterations: iterations,
          answer: finalAnswerBuffer.toString(),
          status: canceled ? ChatTurnStatus.canceled : turnStatus,
          error: canceled ? '[ASK_CANCELED]' : turnError,
          memory: turnMemory,
        );
      }
    }
  }

  Future<void> _finalizeTurn({
    required ChatSessionFile session,
    required String query,
    required AiMode userMode,
    required AiMode effectiveMode,
    required RouteResult? routeResult,
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
      userMode: userMode,
      effectiveMode: effectiveMode,
      router: userMode == AiMode.auto
          ? RouterRecord(
              rawResponse: routeResult?.rawResponse ?? '',
              error: routeResult?.error,
            )
          : null,
      model: config.chatModel,
      baseUrl: config.chatBaseUrl,
      iterations: [for (final entry in sorted) entry.value],
      answer: answer,
      verdict: effectiveMode == AiMode.verify
          ? parseFactCheckVerdict(answer)
          : null,
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
  Future<void> resendLast(String query) =>
      sendMessage(query, mode: _lastMode);

  @override
  List<Message> buildHistory(List<ChatMessage> messages) =>
      buildReactHistory(messages);
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
    summaryAgent: ref.watch(summaryAgentProvider),
    factCheckAgent: ref.watch(factCheckAgentProvider),
    investigationAgent: ref.watch(investigationAgentProvider),
    router: QuestionRouter(llmClient: ref.watch(llmClientProvider)),
    sessionStore: ref.watch(chatSessionStoreProvider),
    configReader: () => ref.read(apiConfigProvider),
  );
});

/// Provider for the [InvestigationAgent] instance.
final investigationAgentProvider = Provider<InvestigationAgent>((ref) {
  return InvestigationAgent(llmClient: ref.watch(llmClientProvider));
});

/// State notifier for the Investigation Chat (R3): cross-chapter mystery
/// questions running the S0–S8 protocol with code-level verdict gates.
class InvestigationChatNotifier extends ChatNotifierBase {
  InvestigationChatNotifier(this._agent) : super([]);
  final InvestigationAgent _agent;

  /// Sends a message and triggers the investigation ReAct stream.
  Future<void> sendMessage(String text) async {
    if (text.trim().isEmpty || state.any((message) => message.isStreaming)) {
      return;
    }
    final generation = nextGeneration();

    final userMsgId = newId();
    final assistantMsgId = newId();
    final userMsg = ChatMessage(
      id: userMsgId,
      role: MessageRole.user,
      content: text,
      timestamp: DateTime.now(),
    );
    final history = buildHistory(state);
    state = [
      ...state,
      userMsg,
      ChatMessage(
        id: assistantMsgId,
        role: MessageRole.assistant,
        content: '',
        isStreaming: true,
        timestamp: DateTime.now(),
      ),
    ];

    try {
      final stream = _agent.investigate(query: text, history: history);
      final steps = <ReActStep>[];
      final finalAnswerBuffer = StringBuffer();
      await for (final event in stream) {
        if (!isCurrentGeneration(generation)) return;
        switch (event.type) {
          case ReActEventType.thought:
          case ReActEventType.toolCall:
          case ReActEventType.toolObservation:
            steps.add(ReActStep(
              type: event.type,
              content: event.content,
              toolName: event.toolName,
              toolArgs: event.toolArgs,
            ),);
            updateMessage(assistantMsgId, steps: List.from(steps));
            break;
          case ReActEventType.finalAnswerToken:
            finalAnswerBuffer.write(event.content);
            updateMessage(
              assistantMsgId,
              content: finalAnswerBuffer.toString(),
              steps: List.from(steps),
            );
            break;
          case ReActEventType.error:
            steps.add(ReActStep(type: event.type, content: event.content));
            updateMessage(
              assistantMsgId,
              isError: true,
              steps: List.from(steps),
            );
            break;
          case ReActEventType.complete:
            updateMessage(
              assistantMsgId,
              isStreaming: false,
              steps: List.from(steps),
            );
            break;
        }
      }
    } catch (e) {
      if (isCurrentGeneration(generation)) {
        updateMessage(
          assistantMsgId,
          content: '[INVESTIGATION_ERROR]',
          isError: true,
          isStreaming: false,
        );
      }
    }
  }

  @override
  String get canceledMarker => '[INVESTIGATION_CANCELED]';

  @override
  Future<void> resendLast(String query) => sendMessage(query);

  @override
  List<Message> buildHistory(List<ChatMessage> messages) =>
      buildReactHistory(messages);
}

/// Provider for the Investigation Chat state.
final investigationChatProvider =
    StateNotifierProvider<InvestigationChatNotifier, List<ChatMessage>>(
  (ref) {
  return InvestigationChatNotifier(ref.watch(investigationAgentProvider));
},
);

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
  return RoleplayAgent(llmClient: ref.watch(llmClientProvider));
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
    ],);
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
