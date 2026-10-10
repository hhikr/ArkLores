import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/providers/settings_provider.dart';
import '../background/background_work.dart';
import '../gamedata/game.dart';
import '../gamedata/gamedata_knowledge_store.dart';
import '../gamedata/multi_game_retrieval.dart';
import '../llm/llm_client.dart';
import '../llm/llm_provider.dart';
import '../llm/usage_meter.dart';
import '../wiki/wiki_provider.dart';
import 'agent_logger.dart';
import 'answer_options.dart';
import 'chat_message.dart';
import 'chat_notifier_base.dart';
import 'chat_session_models.dart';
import 'chat_session_store.dart';
import 'lore_answer_stages.dart' show loreDetailsMarker, loreDigestMinEntries;
import 'react_event.dart';
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

/// 0.12: the Endfield knowledge base (its own file, same schema).
final endfieldGameDataStoreProvider = Provider<GameDataKnowledgeStore>((ref) {
  return GameDataKnowledgeStore(game: Game.endfield);
});

/// The knowledge base of [game].
final gameStoreProvider = Provider.family<GameDataKnowledgeStore, Game>(
  (ref, game) => switch (game) {
    Game.arknights => ref.watch(sharedGameDataStoreProvider),
    Game.endfield => ref.watch(endfieldGameDataStoreProvider),
  },
);

/// The knowledge base an id belongs to (story, record, collection, entry or
/// user-data ref; see `game.dart`).
GameDataKnowledgeStore storeOfId(Ref ref, String id) =>
    ref.watch(gameStoreProvider(gameOfId(id)));

/// Every installed knowledge base as one retrieval surface (the agent's).
final loreRetrievalProvider = Provider<MultiGameRetrieval>((ref) {
  return MultiGameRetrieval({
    for (final game in Game.values) game: ref.watch(gameStoreProvider(game)),
  });
});

/// The story QA pipeline: one agent for every question. Story questions run
/// without hidden reasoning unless "深度思考" is on (R16/R17).
final storyQaAgentProvider = Provider<StoryQaAgent>((ref) {
  return StoryQaAgent(
    llmClient: ref.watch(llmClientProvider(ReasoningLevel.off)),
    gameDataStore: ref.watch(loreRetrievalProvider),
    embeddingClient: ref.watch(embeddingClientProvider),
    wiki: ref.watch(wikiLookupProvider),
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
    AnswerOptions Function()? optionsReader,
    UsageMeter? usage,
  })  : _agent = agent,
        _sessionStore = sessionStore,
        _configReader = configReader,
        _clientReader = clientReader,
        _optionsReader = optionsReader,
        _usage = usage,
        super([]);

  /// R16: the client for the next question (the thinking client when
  /// "深度思考" is on); null keeps the agent's own client.
  final LLMClient? Function()? _clientReader;

  /// The answer options for the next question (wikis, sub-agents).
  final AnswerOptions Function()? _optionsReader;

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

  /// The write that put a new conversation into the history when its first
  /// question was sent.
  Future<void>? _firstSave;

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

  /// Makes a persisted session the current conversation (the one before it
  /// is already in its own file). Subsequent messages continue the same
  /// session file.
  void loadSession(ChatSessionFile session) {
    if (isStreaming) cancel();
    _currentSession = session;
    _conversations.clear();
    state = chatSessionToMessages(session);
  }

  ChatSessionFile? get currentSession => _currentSession;

  /// The id of the conversation shown, once it has a file (from its first
  /// question on, while recording is on).
  String? get currentSessionId => _currentSession?.sessionId;

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

  /// "复核" under the answer [id]: a reader's review of it, as a turn of
  /// its own ([label] is what the turn shows as its question). The answer
  /// stays as it is; the reviewed one, or a line saying the reader had no
  /// question, follows.
  Future<void> reviewAnswer(String id, {required String label}) {
    final conversation = _conversations[id];
    final message = state.where((m) => m.id == id).firstOrNull;
    if (conversation == null || message == null || !message.canReview) {
      return Future.value();
    }
    // What the reader gets: the detailed answer, without the status line
    // and the verdict marker.
    final cut = message.content.indexOf(loreDetailsMarker);
    final answer = (cut < 0
            ? message.content
            : message.content.substring(cut + loreDetailsMarker.length))
        .replaceAll(storyAnswerEnvelopePattern, '')
        .replaceAll(RegExp(r'\[FACT_CHECK_VERDICT:[^\]]*\]\s*'), '')
        .trim();
    return BackgroundWork.instance.run(
      BackgroundWork.text('正在复核回答', 'Reviewing the answer'),
      () => _sendMessage(label, review: (id, conversation, answer)),
    );
  }

  /// "提要" under the answer [id]: its entries reorganised into a few
  /// paragraphs above the detailed answer (one more model call).
  Future<void> digestAnswer(String id) => BackgroundWork.instance.run(
        BackgroundWork.text('正在整理提要', 'Writing the digest'),
        () => _digest(id),
      );

  /// Puts the answer being digested back as it was (set while one runs).
  void Function()? _undoDigest;

  Future<void> _digest(String id) async {
    final conversation = _conversations[id];
    final message = state.where((m) => m.id == id).firstOrNull;
    if (conversation == null ||
        message == null ||
        !message.canDigest ||
        isStreaming) {
      return;
    }
    final generation = nextGeneration();
    final original = message.content;
    // The status line stays first; the paragraphs go between it and the
    // detailed answer.
    final envelope =
        storyAnswerEnvelopePattern.matchAsPrefix(original)?.group(0) ?? '';
    final detail = original.substring(envelope.length);
    void restore() => updateMessage(
          id,
          content: original,
          isStreaming: false,
          liveStatus: '',
          canDigest: true,
        );
    _undoDigest = restore;
    final stop = Completer<void>();
    _stopActive = () {
      if (!stop.isCompleted) stop.complete();
    };
    final start = DateTime.now();
    final usage = _usage?..reset();
    updateMessage(id, isStreaming: true, liveStatus: '整理答案', canDigest: false);
    var done = false;
    var raw = '';
    try {
      final events = _agent.digest(
        conversation: conversation,
        detail: detail,
        onRaw: (text) => raw = text,
      );
      await for (final event in _untilStopped(events, stop.future)) {
        if (!isCurrentGeneration(generation)) break;
        switch (event.type) {
          case ReActEventType.status:
            updateMessage(id, liveStatus: event.content);
          case ReActEventType.finalAnswerReplace:
            updateMessage(id, content: '$envelope${event.content}');
          case ReActEventType.complete:
            done = true;
          default:
            break;
        }
      }
    } catch (_) {
      // The answer is put back below.
    } finally {
      if (isCurrentGeneration(generation)) {
        _stopActive = null;
        _undoDigest = null;
        if (done) {
          final cost = usage == null
              ? null
              : TurnStats.of(usage, DateTime.now().difference(start));
          updateMessage(
            id,
            isStreaming: false,
            liveStatus: '',
            stats: cost == null ? null : (message.stats ?? const TurnStats()) + cost,
          );
          final digested = state.where((m) => m.id == id).firstOrNull?.content;
          if (digested != null) {
            await _recordDigest(original, digested, raw, cost);
          }
        } else {
          restore();
        }
      }
    }
  }

  /// The saved turn of the answer [original] gets its digested text, the
  /// digest's reply and its cost.
  Future<void> _recordDigest(
    String original,
    String digested,
    String raw,
    TurnStats? cost,
  ) async {
    final session = _currentSession;
    if (!recordingEnabled || session == null) return;
    final k = session.turns.lastIndexWhere((t) => t.answer == original);
    if (k < 0) return;
    final turn = session.turns[k];
    final updated = ChatSessionFile(
      sessionId: session.sessionId,
      createdAt: session.createdAt,
      updatedAt: DateTime.now(),
      title: session.title,
      turns: [
        for (final (i, t) in session.turns.indexed)
          if (i != k)
            t
          else
            ChatSessionTurn(
              turn: turn.turn,
              timestamp: turn.timestamp,
              query: turn.query,
              model: turn.model,
              baseUrl: turn.baseUrl,
              iterations: [
                ...turn.iterations,
                ReActIterationRecord(
                  iteration: turn.iterations.length + 1,
                  rawResponse: '（整理）$raw',
                ),
              ],
              answer: digested,
              verdict: turn.verdict,
              status: turn.status,
              error: turn.error,
              durationMs: turn.durationMs,
              memory: turn.memory,
              usage: cost == null || turn.usage == null
                  ? turn.usage
                  : turn.usage! + cost,
              timeline: turn.timeline,
            ),
      ],
    );
    _currentSession = updated;
    await _sessionStore.save(updated);
  }

  /// [review]: the turn is a reader's review of the answer with that id,
  /// conversation and text (see [reviewAnswer]).
  Future<void> _sendMessage(
    String text, {
    (String, LoreConversation, String)? review,
  }) async {
    final query = text.trim();
    if (query.isEmpty || state.any((message) => message.isStreaming)) return;
    final generation = nextGeneration();
    final history = buildHistory(state);

    // R17: continue the last answer's conversation when it is the last
    // message (an error or a cancel in between starts from the texts).
    final lastMessage = state.isEmpty ? null : state.last;
    final prior = review != null
        ? review.$2
        : lastMessage == null || lastMessage.role != MessageRole.assistant
            ? null
            : _conversations[lastMessage.id];
    // "复核" is offered under the last answer only.
    state = [
      for (final m in state) m.canReview ? m.copyWith(canReview: false) : m,
    ];

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
    // Recorded tool calls still waiting for their output: (record, tool).
    final pendingCalls = <(int, String?)>[];
    var turnStatus = ChatTurnStatus.completed;
    String? turnError;
    var canceled = false;
    if (recording && _currentSession == null) {
      // A conversation is in the history from its first question on, not
      // only once that question is answered.
      final created = ChatSessionFile(
        sessionId: newId(),
        createdAt: turnStart,
        updatedAt: turnStart,
        title: _truncateTitle(query),
      );
      _currentSession = created;
      // Not waited for: the question starts at once. The turn's own save
      // waits for this one ([_firstSave]).
      _firstSave = _sessionStore.save(created).catchError((Object _) {});
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
    final options = _optionsReader?.call() ?? const AnswerOptions();
    final stream = review != null
        ? _agent.review(
            prior: review.$2,
            answer: review.$3,
            client: client,
            options: options,
            onRawLlmResponse: onRaw,
            onConversation: onConversation,
          )
        : _agent.run(
            query: query,
            history: history,
            client: client,
            options: options,
            onRawLlmResponse: onRaw,
            prior: prior,
            onConversation: onConversation,
          );

    // 0.14: cancel stops the run at once (not at its next event, which may
    // be minutes away), so the turn is closed and its cost recorded then.
    final stop = Completer<void>();
    _stopActive = () {
      if (!stop.isCompleted) stop.complete();
    };

    final steps = <ReActStep>[];
    // R16: streamed answer text and live reasoning, pushed to the UI at most
    // once per coalescer interval.
    var answer = '';
    final reasoning = StringBuffer();
    // Where the thinking of the turn being answered starts (after the last
    // tool output): what a taken-back answer is cut to.
    var reasoningMark = 0;
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
      await for (final event in _untilStopped(stream, stop.future)) {
        if (!isCurrentGeneration(generation)) {
          canceled = true;
          break;
        }
        switch (event.type) {
          case ReActEventType.thought:
            steps.add(
              ReActStep(
                type: event.type,
                content: event.content,
              ),
            );
            updateMessage(assistantId, steps: List.of(steps));
            if (recording) {
              iterations
                  .putIfAbsent(
                    currentIteration,
                    () => ReActIterationRecord(
                      iteration: currentIteration,
                      rawResponse: '',
                    ),
                  )
                  .thought = event.content;
            }
            break;
          case ReActEventType.toolCall:
            steps.add(
              ReActStep(
                type: event.type,
                content: event.content,
                toolName: event.toolName,
                toolArgs: event.toolArgs,
                subtask: event.subtask,
              ),
            );
            updateMessage(assistantId, steps: List.of(steps));
            if (recording && event.subtask == null) {
              // 0.14: the calls of a turn are announced together and their
              // outputs follow; each output goes to its own call's record.
              pendingCalls.add((currentIteration, event.toolName));
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
            steps.add(
              ReActStep(
                type: event.type,
                content: event.content,
                toolName: event.toolName,
                subtask: event.subtask,
              ),
            );
            updateMessage(assistantId, steps: List.of(steps));
            if (event.subtask == null) reasoningMark = reasoning.length;
            // A sub-agent's step is shown, not recorded as the main
            // agent's iteration.
            if (recording && event.subtask == null) {
              final k = pendingCalls.indexWhere((p) => p.$2 == event.toolName);
              final iteration =
                  k < 0 ? currentIteration : pendingCalls.removeAt(k).$1;
              iterations
                  .putIfAbsent(
                    iteration,
                    () => ReActIterationRecord(
                      iteration: iteration,
                      rawResponse: '',
                    ),
                  )
                  .observation = event.content;
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
            // 0.14: not a step of the work shown. A rejected answer is
            // taken back whole: its thinking goes with it.
            answer = '';
            if (event.rollback) {
              final kept = reasoning.toString().substring(0, reasoningMark);
              reasoning
                ..clear()
                ..write(kept);
            }
            coalescer.flushNow();
            break;
          case ReActEventType.recordNote:
            if (recording) {
              final record = iterations.putIfAbsent(
                currentIteration,
                () => ReActIterationRecord(
                  iteration: currentIteration,
                  rawResponse: '',
                ),
              );
              record.thought = record.thought.isEmpty
                  ? event.content
                  : '${record.thought}\n${event.content}';
            }
            break;
          case ReActEventType.finalAnswerReplace:
            answer = event.content;
            coalescer.flushNow();
            break;
          case ReActEventType.reasoningToken:
            // A new turn's thinking starts on a line of its own (on the
            // phone two turns ran together: "…警告".Need more: …").
            if (reasoning.isNotEmpty &&
                reasoning.length == reasoningMark &&
                !reasoning.toString().endsWith('\n')) {
              reasoning.write('\n\n');
            }
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
            // What can be asked for under the answer: both need its
            // conversation; a review is not reviewed again.
            final conversation = _conversations[assistantId];
            final checked = conversation != null &&
                parseStoryAnswerEnvelope(answer) != null;
            updateMessage(
              assistantId,
              isStreaming: false,
              steps: List.of(steps),
              // The thinking stays (in memory only) so the panel above
              // the answer does not vanish and shift the text being read.
              liveStatus: '',
              canDigest: checked &&
                  conversation.entries.where((e) => e.isText).length >=
                      loreDigestMinEntries,
              canReview: checked && review == null,
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
      if (stop.isCompleted || !isCurrentGeneration(generation)) canceled = true;
      _stopActive = null;
      // A review that did not finish can be asked for again.
      if (review != null &&
          (canceled || turnStatus == ChatTurnStatus.error)) {
        updateMessage(review.$1, canReview: true);
      }
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
    // Another conversation may have been opened (or a new one started)
    // while this turn was stopping: its file is written, it is not made
    // the current one again.
    if (_currentSession?.sessionId == session.sessionId) {
      _currentSession = updated;
    }
    await _firstSave;
    await _sessionStore.save(updated);
  }

  static String _truncateTitle(String query) => query.length <= _titleMaxChars
      ? query
      : '${query.substring(0, _titleMaxChars)}…';

  /// Stops the running question (set while one runs).
  void Function()? _stopActive;

  @override
  void cancel() {
    _stopActive?.call();
    // A digest being written: the answer goes back as it was (not marked
    // as a canceled answer).
    final undo = _undoDigest;
    if (undo != null) {
      _undoDigest = null;
      _stopActive = null;
      invalidatePending();
      undo();
      return;
    }
    super.cancel();
  }

  /// [events] until [stop] completes; the run is then left (its pending
  /// work is dropped) instead of waited for.
  static Stream<ReActEvent> _untilStopped(
    Stream<ReActEvent> events,
    Future<void> stop,
  ) {
    late final StreamController<ReActEvent> out;
    StreamSubscription<ReActEvent>? sub;
    out = StreamController<ReActEvent>(
      onListen: () {
        sub = events.listen(
          out.add,
          onError: out.addError,
          onDone: () {
            if (!out.isClosed) out.close();
          },
        );
        stop.then((_) {
          if (out.isClosed) return;
          sub?.cancel();
          out.close();
        });
      },
      onCancel: () => sub?.cancel(),
    );
    return out.stream;
  }

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

/// How many conversations are saved. Invalidate after one is deleted.
final chatHistoryCountProvider = FutureProvider.autoDispose<int>(
  (ref) => ref.watch(chatSessionStoreProvider).count(),
);

/// One page (0-based) of the saved conversations, last written first: only
/// that page's files are read.
final chatHistoryPageProvider = FutureProvider.autoDispose
    .family<List<ChatSessionSummary>, int>(
  (ref, page) =>
      ref.watch(chatSessionStoreProvider).page(page, ChatSessionStore.pageSize),
);

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
    clientReader: () => ref.read(deepThinkingProvider) &&
            ref.read(deepThinkingAvailableProvider)
        ? ref.read(llmClientProvider(ReasoningLevel.low))
        : null,
    optionsReader: () => ref.read(answerOptionsProvider),
  );
});
