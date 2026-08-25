import 'dart:convert';

import '../llm/llm_client.dart';
import 'chat_message.dart';
import 'fact_check_agent.dart';
import 'question_router.dart';
import 'react_loop.dart' show ReActEventType;

/// Serializable models for AI chat session persistence (Ask page).
///
/// A session file captures a full user-facing conversation: every turn
/// (question + answer) including the complete ReAct chain (raw LLM responses
/// per iteration, parsed keys, tool calls and full observations), the mode the
/// user picked, the mode actually executed (auto routing result and the
/// router's raw classification output), model/base_url per turn, verdict,
/// errors and cancellations.
///
/// The file is JSON in a user-visible directory (`chat_sessions/`); it is both
/// the debug record and the restore source for the in-app conversation history
/// feature.

/// Current session file format version.
const int chatSessionFormatVersion = 1;

/// Format marker written into every session file.
const String chatSessionFormat = 'arklores_chat_session';

/// Status of one conversation turn.
enum ChatTurnStatus {
  completed,
  error,
  canceled;

  String get jsonValue => name;

  static ChatTurnStatus fromJson(String? value) {
    if (value == null || value.isEmpty) return ChatTurnStatus.completed;
    return ChatTurnStatus.values.firstWhere(
      (s) => s.name == value,
      orElse: () => ChatTurnStatus.error,
    );
  }
}

/// One ReAct iteration inside a turn: the full LLM raw response plus the
/// parsed keys and the tool observation (all untruncated).
///
/// Mutable while a turn is being recorded (the notifier fills fields as ReAct
/// events arrive); serialized once the turn completes.
class ReActIterationRecord {

  factory ReActIterationRecord.fromJson(Map<String, dynamic> json) =>
      ReActIterationRecord(
        iteration: (json['iteration'] as num?)?.toInt() ?? 0,
        rawResponse: '${json['raw_response'] ?? ''}',
        thought: '${json['thought'] ?? ''}',
        action: '${json['action'] ?? ''}',
        actionInput: '${json['action_input'] ?? ''}',
        tool: json['tool'] as String?,
        toolArgs: json['tool_args'] is Map<String, dynamic>
            ? Map<String, dynamic>.from(json['tool_args'] as Map)
            : null,
        observation: '${json['observation'] ?? ''}',
      );
  ReActIterationRecord({
    required this.iteration,
    required this.rawResponse,
    this.thought = '',
    this.action = '',
    this.actionInput = '',
    this.tool,
    this.toolArgs,
    this.observation = '',
  });

  int iteration;
  String rawResponse;
  String thought;
  String action;
  String actionInput;
  String? tool;
  Map<String, dynamic>? toolArgs;
  String observation;

  Map<String, dynamic> toJson() => {
        'iteration': iteration,
        'raw_response': rawResponse,
        'thought': thought,
        'action': action,
        'action_input': actionInput,
        if (tool != null && tool!.isNotEmpty) 'tool': tool,
        if (toolArgs != null && toolArgs!.isNotEmpty) 'tool_args': toolArgs,
        'observation': observation,
      };
}

/// The auto-routing decision for one turn (present when user_mode == auto).
class RouterRecord {

  factory RouterRecord.fromJson(Map<String, dynamic> json) => RouterRecord(
        rawResponse: '${json['raw_response'] ?? ''}',
        error: json['error'] as String?,
      );
  const RouterRecord({this.rawResponse = '', this.error});

  /// The router LLM's raw classification output (untruncated).
  final String rawResponse;

  /// Set when the classification call failed (fallback to summarize).
  final String? error;

  Map<String, dynamic> toJson() => {
        'raw_response': rawResponse,
        if (error != null) 'error': error,
      };
}

/// One question-answer turn of a chat session.
class ChatSessionTurn {

  factory ChatSessionTurn.fromJson(Map<String, dynamic> json) {
    final userMode =
        AiMode.values.firstWhere((m) => m.name == json['user_mode'],
            orElse: () => AiMode.auto,);
    return ChatSessionTurn(
      turn: (json['turn'] as num?)?.toInt() ?? 0,
      timestamp: DateTime.tryParse('${json['timestamp'] ?? ''}') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      query: '${json['query'] ?? ''}',
      userMode: userMode,
      effectiveMode: AiMode.values
          .firstWhere((m) => m.name == json['effective_mode'],
              orElse: () => userMode,),
      router: json['router'] is Map<String, dynamic>
          ? RouterRecord.fromJson(
              Map<String, dynamic>.from(json['router'] as Map),)
          : null,
      model: '${json['model'] ?? ''}',
      baseUrl: '${json['base_url'] ?? ''}',
      iterations: [
        for (final item in (json['iterations'] as List<dynamic>? ?? const []))
          if (item is Map<String, dynamic>)
            ReActIterationRecord.fromJson(item),
      ],
      answer: '${json['answer'] ?? ''}',
      verdict: json['verdict'] is String
          ? FactCheckVerdict.values.firstWhere(
              (v) => v.name == json['verdict'],
              orElse: () => FactCheckVerdict.uncertain,)
          : null,
      status: ChatTurnStatus.fromJson('${json['status'] ?? ''}'),
      error: json['error'] as String?,
      durationMs: (json['duration_ms'] as num?)?.toInt(),
    );
  }
  const ChatSessionTurn({
    required this.turn,
    required this.timestamp,
    required this.query,
    required this.userMode,
    required this.effectiveMode,
    this.router,
    required this.model,
    required this.baseUrl,
    this.iterations = const [],
    this.answer = '',
    this.verdict,
    this.status = ChatTurnStatus.completed,
    this.error,
    this.durationMs,
  });

  final int turn;
  final DateTime timestamp;
  final String query;

  /// Mode the user selected for this turn (`auto` or a concrete mode).
  final AiMode userMode;

  /// Mode actually executed; equals [userMode] unless auto routing resolved it.
  final AiMode effectiveMode;

  /// Auto-routing decision (non-null when [userMode] == auto).
  final RouterRecord? router;

  final String model;
  final String baseUrl;
  final List<ReActIterationRecord> iterations;
  final String answer;
  final FactCheckVerdict? verdict;
  final ChatTurnStatus status;
  final String? error;
  final int? durationMs;

  Map<String, dynamic> toJson() => {
        'turn': turn,
        'timestamp': timestamp.toIso8601String(),
        'query': query,
        'user_mode': userMode.name,
        'effective_mode': effectiveMode.name,
        if (router != null) 'router': router!.toJson(),
        'model': model,
        'base_url': baseUrl,
        'iterations': iterations.map((i) => i.toJson()).toList(growable: false),
        'answer': answer,
        if (verdict != null) 'verdict': verdict!.name,
        'status': status.jsonValue,
        if (error != null) 'error': error,
        if (durationMs != null) 'duration_ms': durationMs,
      };
}

/// A persisted chat session file.
class ChatSessionFile {

  factory ChatSessionFile.fromJson(Map<String, dynamic> json) =>
      ChatSessionFile(
        sessionId: '${json['session_id'] ?? ''}',
        createdAt: DateTime.tryParse('${json['created_at'] ?? ''}') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        updatedAt: DateTime.tryParse('${json['updated_at'] ?? ''}') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        title: '${json['title'] ?? ''}',
        turns: [
          for (final item in (json['turns'] as List<dynamic>? ?? const []))
            if (item is Map<String, dynamic>) ChatSessionTurn.fromJson(item),
        ],
      );

  factory ChatSessionFile.decode(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('chat session root is not an object');
    }
    return ChatSessionFile.fromJson(decoded);
  }
  const ChatSessionFile({
    required this.sessionId,
    required this.createdAt,
    required this.updatedAt,
    required this.title,
    this.turns = const [],
  });

  final String sessionId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String title;
  final List<ChatSessionTurn> turns;

  /// Derived display summary for the history list.
  int get turnCount => turns.length;
  AiMode? get lastMode =>
      turns.isEmpty ? null : turns.last.effectiveMode;
  String get lastQuery =>
      turns.isEmpty ? '' : turns.last.query;

  Map<String, dynamic> toJson() => {
        'format': chatSessionFormat,
        'version': chatSessionFormatVersion,
        'session_id': sessionId,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
        'title': title,
        'turns': turns.map((t) => t.toJson()).toList(growable: false),
      };

  String encode() => const JsonEncoder.withIndent('  ')
      .convert(toJson())
      .replaceAll('\n', '\n');
}

/// Rebuilds the UI messages of one turn: a user message plus the assistant
/// message whose ReAct steps are reconstructed from the recorded iterations.
///
/// Used by session restore and by the read-only history viewer so the existing
/// [ChatBubble] rendering can be reused unchanged.
List<ChatMessage> chatTurnToMessages(ChatSessionTurn turn, String assistantId) {
  final steps = <ReActStep>[];
  for (final iteration in turn.iterations) {
    if (iteration.thought.isNotEmpty) {
      steps.add(ReActStep(
        type: ReActEventType.thought,
        content: iteration.thought,
      ),);
    }
    if (iteration.tool != null && iteration.tool!.isNotEmpty) {
      steps.add(ReActStep(
        type: ReActEventType.toolCall,
        content: 'Executing tool "${iteration.tool}" with arguments: '
            '${iteration.toolArgs ?? const <String, dynamic>{}}',
        toolName: iteration.tool,
        toolArgs: iteration.toolArgs,
      ),);
    }
    if (iteration.observation.isNotEmpty) {
      steps.add(ReActStep(
        type: ReActEventType.toolObservation,
        content: iteration.observation,
        toolName: iteration.tool,
      ),);
    }
  }
  return [
    ChatMessage(
      id: 'restored-user-${turn.turn}-${turn.timestamp.millisecondsSinceEpoch}',
      role: MessageRole.user,
      content: turn.query,
      timestamp: turn.timestamp,
    ),
    ChatMessage(
      id: assistantId,
      role: MessageRole.assistant,
      content: turn.answer,
      steps: steps,
      isStreaming: false,
      isError: turn.status == ChatTurnStatus.error,
      factCheckVerdict: turn.verdict,
      timestamp: turn.timestamp,
    ),
  ];
}

/// Rebuilds the full UI message list of a session (restore path).
List<ChatMessage> chatSessionToMessages(ChatSessionFile session) {
  final messages = <ChatMessage>[];
  var assistantIndex = 0;
  for (final turn in session.turns) {
    messages.addAll(chatTurnToMessages(
      turn,
      'restored-assistant-${assistantIndex++}-'
      '${turn.timestamp.millisecondsSinceEpoch}',
    ),);
  }
  return messages;
}
