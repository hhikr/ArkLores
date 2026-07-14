import 'dart:async';
import 'dart:convert';
import '../llm/llm_client.dart';
import 'tools/tool_registry.dart';

/// Types of events emitted by the ReAct Loop.
enum ReActEventType {
  thought,
  toolCall,
  toolObservation,
  finalAnswerToken,
  error,
  complete,
}

/// Event emitted by the ReAct Loop for UI subscription.
class ReActEvent {
  final ReActEventType type;
  final String content;
  final String? toolName;
  final Map<String, dynamic>? toolArgs;

  const ReActEvent({
    required this.type,
    this.content = '',
    this.toolName,
    this.toolArgs,
  });

  @override
  String toString() =>
      'ReActEvent(type: $type, content: $content, toolName: $toolName, toolArgs: $toolArgs)';
}

/// Executor for the ReAct (Reasoning and Acting) loop.
class ReActLoop {
  final LLMClient _llmClient;
  final ToolRegistry _toolRegistry;
  final int _maxIterations;

  ReActLoop({
    required LLMClient llmClient,
    required ToolRegistry toolRegistry,
    int maxIterations = 5,
  })  : _llmClient = llmClient,
        _toolRegistry = toolRegistry,
        _maxIterations = maxIterations;

  /// Runs the ReAct Loop and yields [ReActEvent]s.
  Stream<ReActEvent> run({
    required String systemPrompt,
    required List<Message> chatHistory,
    required String userQuery,
  }) async* {
    // 1. Build the instruction prompt specifying the ReAct format and available tools
    final toolsDesc = _toolRegistry.allTools
        .map((t) => '- `${t.name}`: ${t.description}. Parameters Schema: ${jsonEncode(t.parameters)}')
        .join('\n');

    final reactFormatPrompt = '''
You must solve the user's request using the ReAct (Reasoning and Acting) framework.
You have access to the following tools:
$toolsDesc

Format your response strictly using the following keys:
Thought: <your thinking process here explaining why you need to call a tool or what you have learned>
Action: <the tool name to call, must be one of [${_toolRegistry.allTools.map((t) => t.name).join(', ')}] or empty if you have the final answer>
Action Input: <the JSON-formatted arguments matching the tool schema, e.g., {"query": "something"}>
Observation: <the output of the tool execution - this will be supplied to you, do not write it yourself>

Once you have gathered enough information, output:
Thought: I have enough information to answer.
Final Answer: <your complete, well-structured, final response in Markdown format, with proper citation marks like [chunk_id]>

Let's begin!
''';

    // 2. Prepare conversation messages
    final messages = [
      Message.system('$systemPrompt\n\n$reactFormatPrompt'),
      ...chatHistory,
      Message.user(userQuery),
    ];

    final loopMessages = List<Message>.from(messages);
    var iteration = 0;
    var completed = false;

    while (iteration < _maxIterations && !completed) {
      iteration++;

      // We ask the LLM for a Thought and Action step (we restrict maxTokens to keep it concise)
      String response;
      try {
        response = await _llmClient.chat(
          loopMessages,
          temperature: 0.1, // Low temperature for high format compliance
          maxTokens: 1024,
        );
      } catch (e) {
        yield ReActEvent(type: ReActEventType.error, content: 'LLM Error: $e');
        return;
      }

      // Add assistant response to loop messages so it has context
      loopMessages.add(Message.assistant(response));

      // Parse Thought, Action, Action Input
      final thought = _parseKey(response, 'Thought');
      final action = _parseKey(response, 'Action').trim();
      final actionInputRaw = _parseKey(response, 'Action Input').trim();
      final finalAnswer = _parseKey(response, 'Final Answer');

      if (thought.isNotEmpty) {
        yield ReActEvent(type: ReActEventType.thought, content: thought);
      }

      // If LLM output a Final Answer directly, we are done
      if (finalAnswer.isNotEmpty || (action.isEmpty && finalAnswer.isEmpty && response.contains('Final Answer:'))) {
        final actualAnswer = finalAnswer.isNotEmpty
            ? finalAnswer
            : response.split('Final Answer:').last.trim();

        yield ReActEvent(type: ReActEventType.finalAnswerToken, content: actualAnswer);
        completed = true;
        break;
      }

      if (action.isEmpty) {
        // If no action or final answer, default to treating the response as final answer
        yield ReActEvent(type: ReActEventType.finalAnswerToken, content: response);
        completed = true;
        break;
      }

      // We have a tool action to call!
      final tool = _toolRegistry.getTool(action);
      if (tool == null) {
        final errorMsg = 'Tool "$action" is not registered.';
        yield ReActEvent(type: ReActEventType.error, content: errorMsg);
        loopMessages.add(Message.user('Observation: Error - $errorMsg'));
        continue;
      }

      // Parse tool arguments
      Map<String, dynamic> arguments = {};
      if (actionInputRaw.isNotEmpty) {
        try {
          final decoded = jsonDecode(actionInputRaw);
          if (decoded is Map<String, dynamic>) {
            arguments = decoded;
          }
        } catch (_) {
          // If JSON decode fails, try to build a default parameter map if the tool expects a string query
          if (tool.parameters['properties']?['query'] != null) {
            arguments = {'query': actionInputRaw};
          } else if (tool.parameters['properties']?['chunk_id'] != null) {
            arguments = {'chunk_id': actionInputRaw};
          }
        }
      }

      yield ReActEvent(
        type: ReActEventType.toolCall,
        content: 'Executing tool "$action" with arguments: $arguments',
        toolName: action,
        toolArgs: arguments,
      );

      // Execute tool
      String observation;
      try {
        final result = await tool.execute(arguments);
        observation = result?.toString() ?? 'No output';
      } catch (e) {
        observation = 'Error executing tool: $e';
      }

      yield ReActEvent(
        type: ReActEventType.toolObservation,
        content: observation,
        toolName: action,
      );

      // Add observation to LLM history so it can think on the next iteration
      loopMessages.add(Message.user('Observation: $observation'));
    }

    if (!completed) {
      // Loop finished without Final Answer, stream the final model response or a fallback
      try {
        final fallbackPrompt = 'Please summarize all findings and output your Final Answer now.';
        loopMessages.add(Message.user(fallbackPrompt));
        
        final finalResponse = await _llmClient.chat(loopMessages, temperature: 0.2);
        final finalAnswer = _parseKey(finalResponse, 'Final Answer');
        
        yield ReActEvent(
          type: ReActEventType.finalAnswerToken,
          content: finalAnswer.isNotEmpty ? finalAnswer : finalResponse,
        );
      } catch (e) {
        yield ReActEvent(type: ReActEventType.error, content: 'Failed to generate final answer: $e');
      }
    }

    yield const ReActEvent(type: ReActEventType.complete);
  }

  /// Parses a value for a specific key (e.g. "Thought:") from the response.
  String _parseKey(String text, String key) {
    final pattern = RegExp('^$key:\\s*(.*)', caseSensitive: false, multiLine: true);
    final match = pattern.firstMatch(text);
    if (match != null) {
      final value = match.group(1) ?? '';
      // Continue parsing until the next key or end of text
      final startIndex = text.indexOf(match.group(0)!);
      final remainingText = text.substring(startIndex + match.group(0)!.length);
      final nextKeyPattern = RegExp(r'^(Thought|Action|Action Input|Observation|Final Answer):', caseSensitive: false, multiLine: true);
      final nextKeyMatch = nextKeyPattern.firstMatch(remainingText);
      if (nextKeyMatch != null) {
        final contentEnd = remainingText.indexOf(nextKeyMatch.group(0)!);
        return '${value.trim()}\n${remainingText.substring(0, contentEnd).trim()}'.trim();
      }
      return '${value.trim()}\n${remainingText.trim()}'.trim();
    }
    return '';
  }
}
