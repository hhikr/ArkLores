/// Pure Dart event types shared by the ReAct loop and the planner loop.
///
/// Kept out of any Flutter-bound module so CLI/driver tooling (which runs with
/// `dart run`, no Flutter SDK) can emit and subscribe to these events without
/// pulling in Flutter dependencies.
library;

/// Output transform applied to the final answer before it is streamed.
typedef FinalAnswerTransform = String Function(
  String answer,
  List<String> observations,
);

/// Types of events emitted by the ReAct/Planner loops.
enum ReActEventType {
  thought,
  toolCall,
  toolObservation,
  finalAnswerToken,
  error,
  complete,
}

/// Event emitted by the loops for UI subscription.
class ReActEvent {
  const ReActEvent({
    required this.type,
    this.content = '',
    this.toolName,
    this.toolArgs,
  });

  final ReActEventType type;
  final String content;
  final String? toolName;
  final Map<String, dynamic>? toolArgs;

  @override
  String toString() =>
      'ReActEvent(type: $type, content: $content, toolName: $toolName, toolArgs: $toolArgs)';
}