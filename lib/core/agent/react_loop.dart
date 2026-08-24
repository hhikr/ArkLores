import 'dart:async';
import 'dart:convert';

import '../llm/llm_client.dart';
import 'agent_logger.dart';
import 'evidence_summary.dart';
import 'react_parser.dart';
import 'tools/agent_tool.dart';
import 'tools/tool_registry.dart';

typedef FinalAnswerTransform = String Function(
  String answer,
  List<String> observations,
);

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

/// Executor for the ReAct (Reasoning and Acting) loop.
///
/// The loop is NOT bounded by a step limit: agents may keep reasoning and
/// calling tools until the model produces a Final Answer (or an error
/// terminates the session). A large internal safety cap only guards against a
/// runaway model that never finalizes; it is not a user-facing limit.
class ReActLoop {

  ReActLoop({
    required LLMClient llmClient,
    required ToolRegistry toolRegistry,
    int minimumToolCalls = 0,
    int stepMaxTokens = 2048,
    int maxObservationHistory = 8,
    int safetyMaxIterations = 1000,
  })  : _llmClient = llmClient,
        _toolRegistry = toolRegistry,
        _minimumToolCalls = minimumToolCalls,
        _stepMaxTokens = stepMaxTokens,
        _maxObservationHistory = maxObservationHistory,
        _safetyMaxIterations = safetyMaxIterations;
  final LLMClient _llmClient;
  final ToolRegistry _toolRegistry;
  final int _minimumToolCalls;
  final int _stepMaxTokens;

  /// Runaway-model safety net, NOT a user-facing step limit. Normal sessions
  /// finish far below this; only if a model never produces a Final Answer
  /// does the loop stop here and surface what was gathered via the fallback.
  /// Injectable so fallback behavior stays testable.
  final int _safetyMaxIterations;

  /// Max full `Observation:` messages kept in the LLM history (R3 context
  /// budget, design decision 2). Older observations are replaced by a
  /// placeholder. 0 disables trimming. The transform-side `observations`
  /// snapshot always contains the complete list, so trimming never weakens
  /// code-level validation.
  final int _maxObservationHistory;

  /// Runs the ReAct Loop and yields [ReActEvent]s.
  Stream<ReActEvent> run({
    required String systemPrompt,
    required List<Message> chatHistory,
    required String userQuery,
    String agentName = 'ReAct',
    FinalAnswerTransform? finalAnswerTransform,
  }) async* {
    // 1. Build the instruction prompt specifying the ReAct format and available tools
    final toolsDesc = _toolRegistry.allTools
        .map((t) =>
            '- `${t.name}`: ${t.description}. Parameters Schema: ${jsonEncode(t.parameters)}',)
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
    var completedToolCalls = 0;
    final logger = AgentLogger(userQuery, agentName: agentName);
    final evidenceSummary = EvidenceSummary();
    final observations = <String>[];

    while (!completed) {
      iteration++;
      logger.logIteration(iteration);
      if (iteration > _safetyMaxIterations) {
        logger.logError(
          'SAFETY CAP: $iteration iterations without a Final Answer; '
          'stopping to avoid a runaway loop.',
        );
        break;
      }

      // Ask for one Thought and Action step. Keep this bounded, but leave
      // enough room for providers that include verbose reasoning text.
      ChatCompletionResult completion;
      try {
        completion = await _llmClient.chatCompletion(
          loopMessages,
          temperature: 0.1, // Low temperature for high format compliance
          maxTokens: _stepMaxTokens,
          stop: const [
            'Observation:',
            '\nObservation:',
            'observation:',
            '\nobservation:',
          ],
        );
      } catch (e) {
        logger.logError('LLM_ERROR: $e');
        await logger.flush();
        yield ReActEvent(type: ReActEventType.error, content: 'LLM Error: $e');
        return;
      }
      final response = completion.content;
      if (completion.wasTruncated) {
        final errorMsg =
            'LLM response was truncated before the ReAct step completed. Please retry with a narrower question.';
        logger.logError('TRUNCATED_REACT_STEP: $errorMsg');
        await logger.flush();
        yield ReActEvent(type: ReActEventType.error, content: errorMsg);
        return;
      }

      // Add assistant response to loop messages so it has context
      loopMessages.add(Message.assistant(response));
      logger.logRawResponse(response);

      // Parse Thought, Action, Action Input
      final thought = parseReActKey(response, 'Thought');
      final action = parseReActKey(response, 'Action').trim().split('\n').first;
      final actionInputRaw = parseReActKey(response, 'Action Input').trim();
      final finalAnswer = parseReActKey(response, 'Final Answer');

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

        if (completedToolCalls < _minimumToolCalls) {
          final errorMsg = 'A final answer requires at least '
              '$_minimumToolCalls completed tool call(s). Use a registered '
              'tool before answering.';
          logger.logError('PREMATURE_FINAL_ANSWER: $errorMsg');
          loopMessages.add(Message.user('Observation: Error - $errorMsg'));
          continue;
        }

        if (actualAnswer.trim().isEmpty) {
          final errorMsg =
              'The model returned an empty final answer. Please retry.';
          logger.logError('EMPTY_FINAL_ANSWER: $errorMsg');
          await logger.flush();
          yield ReActEvent(type: ReActEventType.error, content: errorMsg);
          completed = true;
          break;
        }

        final effectiveAnswer = _finalizeAnswer(
          actualAnswer,
          evidenceSummary,
          observations,
          finalAnswerTransform,
        );
        logger.logFinalAnswer(effectiveAnswer);
        await logger.flush();
        yield* _emitFinalAnswer(effectiveAnswer);
        completed = true;
        break;
      }

      if (action.isEmpty) {
        if (completedToolCalls < _minimumToolCalls) {
          final errorMsg = 'A final answer requires at least '
              '$_minimumToolCalls completed tool call(s). Use a registered '
              'tool before answering.';
          logger.logError('PREMATURE_FINAL_ANSWER: $errorMsg');
          loopMessages.add(Message.user('Observation: Error - $errorMsg'));
          continue;
        }
        final effectiveAnswer = _finalizeAnswer(
          response,
          evidenceSummary,
          observations,
          finalAnswerTransform,
        );
        logger.logFinalAnswer(effectiveAnswer);
        await logger.flush();
        yield* _emitFinalAnswer(effectiveAnswer);
        completed = true;
        break;
      }

      // We have a tool action to call!
      final tool = _toolRegistry.getTool(action);
      if (tool == null) {
        final errorMsg = 'Tool "$action" is not registered.';
        logger.logError(errorMsg);
        evidenceSummary.addError();
        yield ReActEvent(type: ReActEventType.error, content: errorMsg);
        loopMessages.add(Message.user('Observation: Error - $errorMsg'));
        continue;
      }

      // Parse tool arguments
      final arguments = parseActionInput(actionInputRaw, tool);

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
      completedToolCalls++;
      evidenceSummary.addObservation(observation);
      observations.add(observation);
      yield ReActEvent(
        type: ReActEventType.toolObservation,
        content: observation,
        toolName: action,
      );

      // Add observation to LLM history so it can think on the next iteration
      loopMessages.add(Message.user('Observation: $observation'));
      _trimObservationHistory(loopMessages);
    }

    if (!completed) {
      // Loop finished without Final Answer, stream the final model response or a fallback
      try {
        final fallbackPrompt = buildFallbackPrompt(evidenceSummary);
        loopMessages.add(Message.user(fallbackPrompt));

        final completion = await _llmClient.chatCompletion(
          loopMessages,
          temperature: 0.2,
          maxTokens: 3072,
        );
        final finalResponse = completion.content;
        final finalAnswer = parseReActKey(finalResponse, 'Final Answer');
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
        final effectiveAnswer = _finalizeAnswer(
          content,
          evidenceSummary,
          observations,
          finalAnswerTransform,
        );
        logger.logFinalAnswer(effectiveAnswer);
        await logger.flush();
        yield* _emitFinalAnswer(effectiveAnswer);
      } catch (e) {
        logger.logError('Failed to generate final answer: $e');
        await logger.flush();
        yield ReActEvent(
            type: ReActEventType.error,
            content: 'Failed to generate final answer: $e',);
      }
    }

    yield const ReActEvent(type: ReActEventType.complete);
  }

  String _finalizeAnswer(
    String answer,
    EvidenceSummary evidenceSummary,
    List<String> observations,
    FinalAnswerTransform? transform,
  ) {
    final guarded = applySourceGuard(answer, evidenceSummary);
    return transform == null
        ? guarded
        : transform(guarded, List.unmodifiable(observations));
  }

  /// Emits the final answer in chunks so the UI can render long answers
  /// progressively instead of waiting for the whole block.
  ///
  /// The content is already fully available (ReAct steps require complete
  /// responses for parsing, and verdict/source transforms must run on the
  /// whole text); chunking is a rendering decision only. Chunks are small
  /// enough for smooth UI updates and large enough to avoid event flooding.
  void _trimObservationHistory(List<Message> loopMessages) {
    if (_maxObservationHistory <= 0) return;
    var count = 0;
    for (final message in loopMessages) {
      if (_isUntrimmedObservation(message)) count++;
    }
    final excess = count - _maxObservationHistory;
    if (excess <= 0) return;
    var replaced = 0;
    for (var i = 0; i < loopMessages.length && replaced < excess; i++) {
      if (_isUntrimmedObservation(loopMessages[i])) {
        loopMessages[i] = Message.user(
          'Observation: [prior observation trimmed to control context size]',
        );
        replaced++;
      }
    }
  }

  bool _isUntrimmedObservation(Message message) =>
      message.role == MessageRole.user &&
      message.content.startsWith('Observation: ') &&
      !message.content.contains('[prior observation trimmed');

  Stream<ReActEvent> _emitFinalAnswer(String answer) async* {
    const chunkSize = 120;
    for (var i = 0; i < answer.length; i += chunkSize) {
      final end = i + chunkSize < answer.length ? i + chunkSize : answer.length;
      yield ReActEvent(
        type: ReActEventType.finalAnswerToken,
        content: answer.substring(i, end),
      );
    }
  }
}
