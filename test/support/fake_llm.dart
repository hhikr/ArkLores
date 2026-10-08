import 'package:arklores/core/llm/llm_client.dart';

/// A model that answers from a script: reply n is `replies[n]`, the last one
/// repeats. Every request it received is kept in [received].
///
/// For a reply that depends on the request, pass [respond] instead; it gets
/// the messages and the 1-based call number.
class ScriptedLLM extends LLMClient {
  ScriptedLLM(List<String> replies)
      : assert(replies.isNotEmpty),
        _respond = ((_, n) => replies[n <= replies.length ? n - 1 : replies.length - 1]);

  ScriptedLLM.respond(String Function(List<Message> messages, int call) respond)
      : _respond = respond;

  final String Function(List<Message>, int) _respond;
  final List<List<Message>> received = [];

  int get calls => received.length;

  @override
  Future<String> chat(
    List<Message> messages, {
    List<Map<String, dynamic>>? tools,
    double temperature = 0.7,
    int maxTokens = 2048,
    List<String>? stop,
  }) async {
    received.add(List.of(messages));
    return _respond(messages, received.length);
  }
}

/// A ReAct step that calls [tool] with [input] (a JSON object literal).
String reactAction(String tool, String input, {String thought = 'look it up'}) =>
    'Thought: $thought\nAction: $tool\nAction Input: $input';

/// A ReAct step that ends with [answer].
String reactFinal(String answer, {String thought = 'done'}) =>
    'Thought: $thought\nFinal Answer: $answer';
