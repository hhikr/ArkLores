import 'dart:convert';

import '../llm/llm_client.dart';
import 'chat_message.dart';
import 'react_loop.dart' show ReActEventType;
import 'story_answer.dart' show FactCheckVerdict;
import 'turn_stats.dart';

/// Serializable models for AI chat session persistence (Ask page).
///
/// A session file captures a full user-facing conversation: every turn
/// (question + answer) including the complete ReAct chain (raw LLM responses
/// per iteration, parsed keys, tool calls and full observations), model/base_url
/// per turn, verdict, what the turn cost, errors and cancellations. Sessions
/// saved before v0.10.7 also carry user_mode / effective_mode / router (the
/// removed answer modes); they are ignored when reading.
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

/// One question-answer turn of a chat session.
class ChatSessionTurn {

  factory ChatSessionTurn.fromJson(Map<String, dynamic> json) {
    return ChatSessionTurn(
      turn: (json['turn'] as num?)?.toInt() ?? 0,
      timestamp: DateTime.tryParse('${json['timestamp'] ?? ''}') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      query: '${json['query'] ?? ''}',
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
      memory: json['memory'] as String?,
      usage: json['usage'] is Map
          ? TurnStats.fromJson(Map<String, dynamic>.from(json['usage'] as Map))
          : null,
      timeline: json['timeline'] is List
          ? [
              for (final item in json['timeline'] as List)
                if (item is Map) Map<String, Object?>.from(item),
            ]
          : null,
    );
  }
  const ChatSessionTurn({
    required this.turn,
    required this.timestamp,
    required this.query,
    required this.model,
    required this.baseUrl,
    this.iterations = const [],
    this.answer = '',
    this.verdict,
    this.status = ChatTurnStatus.completed,
    this.error,
    this.durationMs,
    this.memory,
    this.usage,
    this.timeline,
  });

  final int turn;
  final DateTime timestamp;
  final String query;

  /// What the turn cost (calls, tokens, time); null in older sessions.
  final TurnStats? usage;

  /// Per-call wall-clock timeline of the turn (start order), for analysing
  /// where the time went.
  final List<Map<String, Object?>>? timeline;

  final String model;
  final String baseUrl;
  final List<ReActIterationRecord> iterations;
  final String answer;
  final FactCheckVerdict? verdict;
  final ChatTurnStatus status;
  final String? error;
  final int? durationMs;

  /// Snapshot of the loop's layered memory block at turn end (M1/M7):
  /// read index, mapped scopes, collected evidence and Thought notes.
  final String? memory;

  Map<String, dynamic> toJson() => {
        'turn': turn,
        'timestamp': timestamp.toIso8601String(),
        'query': query,
        'model': model,
        'base_url': baseUrl,
        'iterations': iterations.map((i) => i.toJson()).toList(growable: false),
        'answer': answer,
        if (verdict != null) 'verdict': verdict!.name,
        'status': status.jsonValue,
        if (error != null) 'error': error,
        if (durationMs != null) 'duration_ms': durationMs,
        if (memory != null) 'memory': memory,
        if (usage != null) 'usage': usage!.toJson(),
        if (timeline != null && timeline!.isNotEmpty) 'timeline': timeline,
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
      // R7-5: error/canceled turns carry no answer — surface the recorded
      // error text so restored history (and the read-only viewer) shows
      // what actually went wrong instead of an empty bubble.
      content: turn.answer.isEmpty ? (turn.error ?? '') : turn.answer,
      steps: steps,
      isStreaming: false,
      isError: turn.status == ChatTurnStatus.error,
      factCheckVerdict: turn.verdict,
      stats: turn.usage,
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
