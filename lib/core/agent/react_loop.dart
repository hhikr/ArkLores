import 'dart:async';
import 'dart:convert';
import '../llm/llm_client.dart';
import 'agent_logger.dart';
import 'tools/agent_tool.dart';
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
        .map((t) =>
            '- `${t.name}`: ${t.description}. Parameters Schema: ${jsonEncode(t.parameters)}')
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

CRITICAL FORMATTING RULES:
1. Each key (Thought, Action, Action Input, Final Answer) MUST start on a new line. Do NOT combine them on the same line.
2. Do NOT format keys with markdown bolding or list symbols. Write them exactly as "Thought:", "Action:", "Action Input:", "Final Answer:".
3. Action Input MUST be strict JSON with quoted keys and string values, for example {"query": "缪尔赛思", "top_k": 5}.
4. Write ONLY one Thought, Action, and Action Input at a time. Do NOT write "Observation:" or hallucinate observations yourself. Stop generating immediately after writing "Action Input:".
5. When you are ready to answer, output "Final Answer:" with non-empty Markdown content. Do not call more tools after "Final Answer:".

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
    final logger = AgentLogger(userQuery);

    while (iteration < _maxIterations && !completed) {
      iteration++;
      logger.logIteration(iteration, _maxIterations);

      // We ask the LLM for a Thought and Action step (we restrict maxTokens to keep it concise)
      ChatCompletionResult completion;
      try {
        completion = await _llmClient.chatCompletion(
          loopMessages,
          temperature: 0.1, // Low temperature for high format compliance
          maxTokens: 1024,
          stop: const [
            'Observation:',
            '\nObservation:',
            'observation:',
            '\nobservation:'
          ],
        );
      } catch (e) {
        yield ReActEvent(type: ReActEventType.error, content: 'LLM Error: $e');
        return;
      }
      final response = completion.content;
      if (completion.wasTruncated) {
        final errorMsg =
            'LLM response was truncated before the ReAct step completed. Please retry with a shorter query or a larger max token limit.';
        logger.logError('TRUNCATED_REACT_STEP: $errorMsg');
        await logger.flush();
        yield ReActEvent(type: ReActEventType.error, content: errorMsg);
        return;
      }

      // Add assistant response to loop messages so it has context
      loopMessages.add(Message.assistant(response));
      logger.logRawResponse(response);

      // Parse Thought, Action, Action Input
      final thought = _parseKey(response, 'Thought');
      final action = _parseKey(response, 'Action').trim();
      final actionInputRaw = _parseKey(response, 'Action Input').trim();
      final finalAnswer = _parseKey(response, 'Final Answer');

      logger.logParsed(
        thought: thought,
        action: action,
        actionInput: actionInputRaw,
        finalAnswer: finalAnswer,
      );

      if (thought.isNotEmpty) {
        yield ReActEvent(type: ReActEventType.thought, content: thought);
      }

      // If LLM output a Final Answer directly, we are done
      if (finalAnswer.isNotEmpty ||
          (action.isEmpty &&
              finalAnswer.isEmpty &&
              response.contains('Final Answer:'))) {
        final actualAnswer = finalAnswer.isNotEmpty
            ? finalAnswer
            : response.split('Final Answer:').last.trim();

        if (actualAnswer.trim().isEmpty) {
          final errorMsg =
              'The model returned an empty final answer. Please retry.';
          logger.logError('EMPTY_FINAL_ANSWER: $errorMsg');
          await logger.flush();
          yield ReActEvent(type: ReActEventType.error, content: errorMsg);
          completed = true;
          break;
        }

        logger.logFinalAnswer(actualAnswer);
        await logger.flush();
        yield ReActEvent(
            type: ReActEventType.finalAnswerToken, content: actualAnswer);
        completed = true;
        break;
      }

      if (action.isEmpty) {
        // If no action or final answer, default to treating the response as final answer
        yield ReActEvent(
            type: ReActEventType.finalAnswerToken, content: response);
        completed = true;
        break;
      }

      // We have a tool action to call!
      final tool = _toolRegistry.getTool(action);
      if (tool == null) {
        final errorMsg = 'Tool "$action" is not registered.';
        logger.logError(errorMsg);
        yield ReActEvent(type: ReActEventType.error, content: errorMsg);
        loopMessages.add(Message.user('Observation: Error - $errorMsg'));
        continue;
      }

      // Parse tool arguments
      final arguments = _parseActionInput(actionInputRaw, tool);

      logger.logToolCall(action, arguments);
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
        if (result is ToolExecutionResult) {
          observation = result.observation;
          logger.logToolDiagnostics(result.debugLog ?? '');
        } else {
          observation = result?.toString() ?? 'No output';
        }
      } catch (e) {
        observation = 'Error executing tool: $e';
      }

      logger.logObservation(observation);
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
        final fallbackPrompt =
            'Please summarize all findings and output your Final Answer now.';
        loopMessages.add(Message.user(fallbackPrompt));

        final completion = await _llmClient.chatCompletion(
          loopMessages,
          temperature: 0.2,
          maxTokens: 3072,
        );
        final finalResponse = completion.content;
        final finalAnswer = _parseKey(finalResponse, 'Final Answer');
        var content = finalAnswer.isNotEmpty ? finalAnswer : finalResponse;
        if (completion.wasTruncated) {
          content = content.trim().isEmpty
              ? 'The model response was truncated before it produced a final answer. Please retry with a narrower question.'
              : '$content\n\n> Note: the model response was truncated and may be incomplete.';
        }

        logger.logFallback(fallbackPrompt, finalResponse);
        if (content.trim().isEmpty) {
          const errorMsg =
              'The model returned an empty final answer. Please retry.';
          logger.logError('EMPTY_FINAL_ANSWER: $errorMsg');
          await logger.flush();
          yield const ReActEvent(type: ReActEventType.error, content: errorMsg);
          yield const ReActEvent(type: ReActEventType.complete);
          return;
        }
        logger.logFinalAnswer(content);
        await logger.flush();
        yield ReActEvent(
          type: ReActEventType.finalAnswerToken,
          content: content,
        );
      } catch (e) {
        logger.logError('Failed to generate final answer: $e');
        await logger.flush();
        yield ReActEvent(
            type: ReActEventType.error,
            content: 'Failed to generate final answer: $e');
      }
    }

    yield const ReActEvent(type: ReActEventType.complete);
  }

  /// Parses a value for a specific key (e.g. "Thought:") from the response.
  /// Handles markdown formatting like bolding, bullet points, and inline key placement.
  String _parseKey(String text, String key) {
    // Matches the key optionally preceded by start of text, space, or newline, and optional bold asterisks
    final pattern =
        RegExp('(?:^|\\s)\\**$key\\**\\s*:\\s*(.*)', caseSensitive: false);
    final match = pattern.firstMatch(text);
    if (match != null) {
      var value = match.group(1) ?? '';

      // Handle inline next key on the same line (e.g. Action: search_wiki Action Input: {...})
      final nextKeyInlinePattern = RegExp(
          r'\b(Thought|Action|Action Input|Observation|Final Answer)\s*:',
          caseSensitive: false);
      final inlineMatch = nextKeyInlinePattern.firstMatch(value);
      if (inlineMatch != null) {
        value = value.substring(0, inlineMatch.start).trim();
        return _cleanValue(value);
      }

      // Continue parsing subsequent lines until the next key or end of text
      final startIndex = text.indexOf(match.group(0)!);
      final remainingText = text.substring(startIndex + match.group(0)!.length);
      final nextKeyPattern = RegExp(
          r'^[-\\*\\s]*\**(Thought|Action|Action Input|Observation|Final Answer)\**\s*:',
          caseSensitive: false,
          multiLine: true);
      final nextKeyMatch = nextKeyPattern.firstMatch(remainingText);
      if (nextKeyMatch != null) {
        final contentEnd = remainingText.indexOf(nextKeyMatch.group(0)!);
        return _cleanValue(
            '${value.trim()}\n${remainingText.substring(0, contentEnd).trim()}');
      }
      return _cleanValue('${value.trim()}\n${remainingText.trim()}');
    }
    return '';
  }

  /// Cleans up trailing formatting symbols like markdown bolding **.
  String _cleanValue(String val) {
    var cleaned = val.trim();
    if (cleaned.endsWith('**')) {
      cleaned = cleaned.substring(0, cleaned.length - 2).trim();
    }
    if (cleaned.startsWith('**')) {
      cleaned = cleaned.substring(2).trim();
    }
    return cleaned;
  }

  Map<String, dynamic> _parseActionInput(String raw, AgentTool tool) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return {};

    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
    } catch (_) {
      // Fall through to the tolerant parser below.
    }

    final properties = tool.parameters['properties'];
    final knownKeys = properties is Map
        ? properties.keys.map((key) => '$key').toSet()
        : <String>{};

    final pairs = _parseLooseKeyValuePairs(trimmed, knownKeys);
    if (pairs.isNotEmpty) return pairs;

    if (knownKeys.contains('query')) {
      return {'query': _stripLooseQuotes(trimmed)};
    }
    if (knownKeys.contains('chunk_id')) {
      return {'chunk_id': _stripLooseQuotes(trimmed)};
    }
    return {};
  }

  Map<String, dynamic> _parseLooseKeyValuePairs(
    String raw,
    Set<String> knownKeys,
  ) {
    var text = raw.trim();
    if (text.startsWith('{') && text.endsWith('}')) {
      text = text.substring(1, text.length - 1).trim();
    }
    if (text.isEmpty) return {};

    final result = <String, dynamic>{};
    for (final part in _splitLoosePairs(text)) {
      final separator = part.indexOf(':');
      if (separator <= 0) continue;

      final key = _stripLooseQuotes(part.substring(0, separator).trim());
      if (!knownKeys.contains(key)) continue;

      final valueText = part.substring(separator + 1).trim();
      result[key] = _coerceLooseValue(key, valueText);
    }
    return result;
  }

  List<String> _splitLoosePairs(String text) {
    final parts = <String>[];
    final buffer = StringBuffer();
    var inSingleQuote = false;
    var inDoubleQuote = false;

    for (var i = 0; i < text.length; i++) {
      final char = text[i];
      if (char == "'" && !inDoubleQuote) {
        inSingleQuote = !inSingleQuote;
      } else if (char == '"' && !inSingleQuote) {
        inDoubleQuote = !inDoubleQuote;
      }

      if (char == ',' && !inSingleQuote && !inDoubleQuote) {
        parts.add(buffer.toString().trim());
        buffer.clear();
      } else {
        buffer.write(char);
      }
    }

    final last = buffer.toString().trim();
    if (last.isNotEmpty) parts.add(last);
    return parts;
  }

  dynamic _coerceLooseValue(String key, String rawValue) {
    final value = _stripLooseQuotes(rawValue);
    if (key == 'top_k') {
      return int.tryParse(value) ?? value;
    }
    if (value == 'true') return true;
    if (value == 'false') return false;
    return value;
  }

  String _stripLooseQuotes(String value) {
    var cleaned = value.trim();
    if ((cleaned.startsWith('"') && cleaned.endsWith('"')) ||
        (cleaned.startsWith("'") && cleaned.endsWith("'"))) {
      cleaned = cleaned.substring(1, cleaned.length - 1).trim();
    }
    return cleaned;
  }
}
