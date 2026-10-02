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

  /// R16: drop the answer text streamed so far (e.g. a citation rewrite
  /// follows); [ReActEvent.content] is a short reason for the step list.
  finalAnswerReset,

  /// R16: the complete final answer, replacing what was streamed (adds the
  /// status envelope and source warnings once the text is checked).
  finalAnswerReplace,

  /// R16: hidden-reasoning text streamed live; shown while the answer is
  /// written, never stored with the answer.
  reasoningToken,

  /// R16: what the run is doing right now ("第 7 步 · 阅读 …"), for the
  /// status line while streaming.
  status,
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

/// Final answer text after [event] given the text [before] it (R16): tokens
/// append, a reset clears, a replace sets the whole text; other events leave
/// it unchanged.
String applyAnswerEvent(String before, ReActEvent event) =>
    switch (event.type) {
      ReActEventType.finalAnswerToken => before + event.content,
      ReActEventType.finalAnswerReset => '',
      ReActEventType.finalAnswerReplace => event.content,
      _ => before,
    };

/// The final answer a whole event sequence produces.
String finalAnswerOf(Iterable<ReActEvent> events) =>
    events.fold('', applyAnswerEvent);
