import 'dart:async';
import 'dart:convert';

import '../llm/llm_client.dart';
import 'agent_logger.dart';
import 'evidence_summary.dart';
import 'loop_memory.dart';
import 'react_event.dart';
import 'react_parser.dart';
import 'tools/agent_tool.dart';
import 'tools/tool_registry.dart';

/// Types of events emitted by the ReAct Loop. (Re)exported for compatibility.
export 'react_event.dart'
    show
        FinalAnswerTransform,
        ReActEvent,
        ReActEventType,
        applyAnswerEvent,
        finalAnswerOf;

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

  /// Legacy context-budget knob (R3). Superseded by the layered memory (M1):
  /// the request now keeps only [LoopMemory.recentWindowSize] recent raw
  /// turns plus the compact [LoopMemory] block, so this value is no longer
  /// consulted. Kept for constructor compatibility.
  // ignore: unused_field
  final int _maxObservationHistory;

  /// How many extra attempts after a truncated step response (R7-3).
  static const int _maxTruncatedRetries = 2;

  /// Consecutive malformed responses (no Action / Final Answer key) allowed
  /// before giving up (R7-2).
  static const int _maxMalformedResponses = 3;

  /// Runs the ReAct Loop and yields [ReActEvent]s.
  Stream<ReActEvent> run({
    required String systemPrompt,
    required List<Message> chatHistory,
    required String userQuery,
    String? agentName,
    FinalAnswerTransform? finalAnswerTransform,
    void Function(int iteration, String rawResponse)? onRawLlmResponse,
    void Function(String memoryBlock)? onMemoryChanged,
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
6. Observations can be long. Briefly note in your Thought the key conclusions you draw from each Observation; later turns will only retain your Thought notes and the most recent two turns of raw text.

Let's begin!
''';

    // 2. Prepare conversation messages. The full request is rebuilt every
    // iteration as: base (system + chat history + query) + memory block (L1)
    // + recent window of raw turns (L2). Old turns leave the request once the
    // window slides; their key content survives in LoopMemory.
    // R7-1: the memory block lives INSIDE the system message, never as a
    // separate user message — a standalone "调查要点" user block made the
    // model continue writing prose without the required Thought: prefix.
    final chatHistoryList = chatHistory;
    final query = userQuery;
    final memory = LoopMemory();
    final recentWindow = <Message>[];
    var iteration = 0;
    var completed = false;
    var completedToolCalls = 0;
    var truncatedRetries = 0;
    var malformedCount = 0;

    List<Message> buildRequest({List<Message>? tail}) {
      final systemText = memory.isEmpty
          ? '$systemPrompt\n\n$reactFormatPrompt'
          : '$systemPrompt\n\n$reactFormatPrompt\n\n'
              '【系统维护的调查记录，非对话内容，请勿续写；'
              '严格按格式输出 Thought/Action/Final Answer】\n'
              '${memory.buildBlock()}';
      return [
        Message.system(systemText),
        ...chatHistoryList,
        Message.user(query),
        ...recentWindow,
        if (tail != null) ...tail,
      ];
    }

    // Legacy debug logger: only created when the caller passes an agentName
    // (Roleplay keeps it). Ask-page agents pass null: their full transcript
    // is recorded by the caller through [onRawLlmResponse] + the event stream
    // into the chat session store instead, avoiding duplicate log files.
    final AgentLogger? logger = agentName == null
        ? null
        : AgentLogger(userQuery, agentName: agentName);
    final evidenceSummary = EvidenceSummary();
    final observations = <String>[];

    var previewOpen = false;
    while (!completed) {
      if (previewOpen) {
        // The previous step's live "Final Answer" text was not accepted.
        yield const ReActEvent(type: ReActEventType.finalAnswerReset);
        previewOpen = false;
      }
      iteration++;
      logger?.logIteration(iteration);
      if (iteration > _safetyMaxIterations) {
        logger?.logError(
          'SAFETY CAP: $iteration iterations without a Final Answer; '
          'stopping to avoid a runaway loop.',
        );
        break;
      }

      // Ask for one Thought and Action step. Keep this bounded, but leave
      // enough room for providers that include verbose reasoning text.
      ChatCompletionResult completion;
      // R16: every step streams; text after "Final Answer:" is shown live
      // and replaced by the checked answer (or cleared) when the step ends.
      final preview = _FinalAnswerPreview();
      try {
        final deltas = _llmClient.streamCompletion(
          buildRequest(),
          temperature: 0.1, // Low temperature for high format compliance
          maxTokens: _stepMaxTokens,
          stop: const [
            'Observation:',
            '\nObservation:',
            'observation:',
            '\nobservation:',
          ],
        );
        final text = StringBuffer();
        CompletionDelta? last;
        await for (final delta in deltas) {
          if (delta.done) last = delta;
          if (delta.content.isEmpty) continue;
          text.write(delta.content);
          final live = preview.advance(text.toString());
          if (live.isNotEmpty) {
            yield ReActEvent(
              type: ReActEventType.finalAnswerToken,
              content: live,
            );
          }
        }
        completion = ChatCompletionResult(
          content: text.toString(),
          finishReason: last?.finishReason,
        );
      } catch (e) {
        if (preview.started) {
          yield const ReActEvent(type: ReActEventType.finalAnswerReset);
        }
        logger?.logError('LLM_ERROR: $e');
        await logger?.flush();
        yield ReActEvent(type: ReActEventType.error, content: 'LLM Error: $e');
        return;
      }
      final response = completion.content;
      onRawLlmResponse?.call(iteration, response);
      // Cleared at the next step unless this step's answer is accepted.
      previewOpen = preview.started;
      if (completion.wasTruncated) {
        // R7-3: truncation is recoverable, not fatal. Retry up to
        // [_maxTruncatedRetries] times with a "be concise" hint; only give up
        // afterwards. The truncated response never enters the recent window.
        if (truncatedRetries < _maxTruncatedRetries) {
          truncatedRetries++;
          logger?.logError(
            'TRUNCATED_RETRY ($truncatedRetries/$_maxTruncatedRetries): '
            'output was truncated; asking for a concise step.',
          );
          recentWindow.add(Message.user(
            'Observation: Error - your previous response was truncated. '
            'Output a short, concise Action (or Final Answer) now.',
          ),);
          _pruneWindow(recentWindow);
          continue;
        }
        final errorMsg =
            'LLM response was truncated before the ReAct step completed. Please retry with a narrower question.';
        logger?.logError('TRUNCATED_REACT_STEP: $errorMsg');
        await logger?.flush();
        yield ReActEvent(type: ReActEventType.error, content: errorMsg);
        return;
      }

      // Add assistant response to the recent window so it has context
      recentWindow.add(Message.assistant(response));
      logger?.logRawResponse(response);

      // Parse Thought, Action, Action Input
      final thought = parseReActKey(response, 'Thought');
      final action = parseReActKey(response, 'Action').trim().split('\n').first;
      final actionInputRaw = parseReActKey(response, 'Action Input').trim();
      final finalAnswer = parseReActKey(response, 'Final Answer');

      logger?.logParsed(
        thought: thought,
        action: action,
        actionInput: actionInputRaw,
        finalAnswer: finalAnswer,
      );

      if (thought.isNotEmpty) {
        memory.noteThought(iteration, thought);
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
          logger?.logError('PREMATURE_FINAL_ANSWER: $errorMsg');
          recentWindow.add(Message.user('Observation: Error - $errorMsg'));
          _pruneWindow(recentWindow);
          continue;
        }

        if (actualAnswer.trim().isEmpty) {
          final errorMsg =
              'The model returned an empty final answer. Please retry.';
          logger?.logError('EMPTY_FINAL_ANSWER: $errorMsg');
          await logger?.flush();
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
        logger?.logFinalAnswer(effectiveAnswer);
        await logger?.flush();
        yield* _emitFinalAnswer(effectiveAnswer);
        completed = true;
        break;
      }

      if (action.isEmpty) {
        // R7-2: reaching here means the response had no Action and no
        // "Final Answer:" key (the finalAnswer branch above already handled
        // the keyed case). Bare prose — e.g. a Thought that lost its prefix —
        // must NOT be treated as the final answer. Ask for a proper step;
        // give up after a few consecutive malformed responses.
        if (finalAnswer.isEmpty) {
          if (malformedCount >= _maxMalformedResponses) {
            const errorMsg =
                'The model repeatedly failed to output a valid Action or '
                'Final Answer. Please retry with a narrower question.';
            logger?.logError('MALFORMED_RESPONSE: $errorMsg');
            await logger?.flush();
            yield const ReActEvent(type: ReActEventType.error, content: errorMsg);
            return;
          }
          malformedCount++;
          final errorMsg = 'Your response did not contain a valid Action or '
              'Final Answer key. Output "Action:" with a tool name, or '
              '"Final Answer:" with your answer.';
          logger?.logError('MALFORMED_RESPONSE: $errorMsg');
          recentWindow.add(Message.user('Observation: Error - $errorMsg'));
          _pruneWindow(recentWindow);
          continue;
        }
        if (completedToolCalls < _minimumToolCalls) {
          final errorMsg = 'A final answer requires at least '
              '$_minimumToolCalls completed tool call(s). Use a registered '
              'tool before answering.';
          logger?.logError('PREMATURE_FINAL_ANSWER: $errorMsg');
          recentWindow.add(Message.user('Observation: Error - $errorMsg'));
          _pruneWindow(recentWindow);
          continue;
        }
        final effectiveAnswer = _finalizeAnswer(
          response,
          evidenceSummary,
          observations,
          finalAnswerTransform,
        );
        logger?.logFinalAnswer(effectiveAnswer);
        await logger?.flush();
        yield* _emitFinalAnswer(effectiveAnswer);
        completed = true;
        break;
      }

      // We have a tool action to call!
      final tool = _toolRegistry.getTool(action);
      if (tool == null) {
        final errorMsg = 'Tool "$action" is not registered.';
        logger?.logError(errorMsg);
        evidenceSummary.addError();
        yield ReActEvent(type: ReActEventType.error, content: errorMsg);
        recentWindow.add(Message.user('Observation: Error - $errorMsg'));
        _pruneWindow(recentWindow);
        continue;
      }

      // Parse tool arguments
      final arguments = parseActionInput(actionInputRaw, tool);

      logger?.logToolCall(action, arguments);
      yield ReActEvent(
        type: ReActEventType.toolCall,
        content: 'Executing tool "$action" with arguments: $arguments',
        toolName: action,
        toolArgs: arguments,
      );

      // Execute tool
      String observation;
      var toolOk = false;
      try {
        final result = await tool.execute(arguments);
        if (result is ToolExecutionResult) {
          observation = result.observation;
          toolOk = true;
          logger?.logToolDiagnostics(result.debugLog ?? '');
        } else {
          observation = result?.toString() ?? 'No output';
          toolOk = true;
        }
      } catch (e) {
        observation = 'Error executing tool: $e';
      }
      if (toolOk) {
        _noteToolResult(memory, action, arguments);
      }

      logger?.logObservation(observation);
      completedToolCalls++;
      evidenceSummary.addObservation(observation);
      observations.add(observation);
      yield ReActEvent(
        type: ReActEventType.toolObservation,
        content: observation,
        toolName: action,
      );

      // Add observation to the recent window so it can think on the next
      // iteration; older turns slide out and their essence lives in memory.
      recentWindow.add(Message.user('Observation: $observation'));
      _pruneWindow(recentWindow);
      onMemoryChanged?.call(memory.buildBlock());
    }

    if (!completed) {
      // Loop finished without Final Answer, stream the final model response
      // or a fallback. The fallback request uses the same layered context
      // (base + memory + recent window), never the full raw history.
      try {
        final fallbackPrompt = buildFallbackPrompt(evidenceSummary);

        final completion = await _llmClient.chatCompletion(
          buildRequest(tail: [Message.user(fallbackPrompt)]),
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

        logger?.logFallback(fallbackPrompt, finalResponse);
        onRawLlmResponse?.call(iteration + 1, finalResponse);
        if (content.trim().isEmpty) {
          const errorMsg =
              'The model returned an empty final answer. Please retry.';
          logger?.logError('EMPTY_FINAL_ANSWER: $errorMsg');
          await logger?.flush();
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
        logger?.logFinalAnswer(effectiveAnswer);
        await logger?.flush();
        yield* _emitFinalAnswer(effectiveAnswer);
      } catch (e) {
        logger?.logError('Failed to generate final answer: $e');
        await logger?.flush();
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

  /// Keeps only the [LoopMemory.recentWindowSize] most recent turns (an
  /// assistant message plus its following messages) in [window]. Older raw
  /// turns leave the request; their conclusions survive in [LoopMemory].
  void _pruneWindow(List<Message> window) {
    var assistantCount = 0;
    for (final message in window) {
      if (message.role == MessageRole.assistant) assistantCount++;
    }
    var excess = assistantCount - LoopMemory.recentWindowSize;
    while (excess > 0 && window.isNotEmpty) {
      final firstAssistant =
          window.indexWhere((message) => message.role == MessageRole.assistant);
      if (firstAssistant < 0) break;
      var end = firstAssistant + 1;
      while (end < window.length &&
          window[end].role != MessageRole.assistant) {
        end++;
      }
      window.removeRange(0, end);
      excess--;
    }
  }

  /// Indexes a successful tool call into [LoopMemory] so the model can see,
  /// after the raw observation leaves the recent window, that the chapter was
  /// read / the scope was mapped / an entity's appearances were collected.
  void _noteToolResult(
    LoopMemory memory,
    String action,
    Map<String, dynamic> arguments,
  ) {
    switch (action) {
      case 'read_story_lines':
        final storyId = '${arguments['story_id'] ?? ''}'.trim();
        if (storyId.isEmpty) return;
        final start = (arguments['start_line'] as num?)?.toInt() ?? 0;
        final pageToken =
            int.tryParse('${arguments['page_token'] ?? ''}'.trim());
        final from = pageToken ?? start;
        final maxLines = (arguments['max_lines'] as num?)?.toInt();
        final to = from + (maxLines ?? 0);
        memory.noteRead(storyId, from, to);
      case 'get_story_map':
        final scopeId = '${arguments['scope_id'] ?? ''}'.trim();
        if (scopeId.isNotEmpty) {
          memory.noteMapped(scopeId);
          return;
        }
        final storyIds = arguments['story_ids'];
        if (storyIds is List && storyIds.isNotEmpty) {
          memory.noteMapped(
            'story_ids:${storyIds.map((item) => '$item').join(',')}',
          );
        }
      case 'collect_entity_evidence':
        memory.noteEvidence('${arguments['entity_id'] ?? ''}');
    }
  }

  /// R16: the checked answer replaces whatever was streamed live (the source
  /// guard / transform may have changed it).
  Stream<ReActEvent> _emitFinalAnswer(String answer) async* {
    yield ReActEvent(
      type: ReActEventType.finalAnswerReplace,
      content: answer,
    );
  }
}

/// R16: live text of a streaming ReAct step after its `Final Answer:` key.
class _FinalAnswerPreview {
  static final RegExp _key = RegExp(r'(^|\n)\s*Final Answer:\s*');
  int _sent = -1;

  bool get started => _sent >= 0;

  /// The not-yet-shown answer text in [text] (the step so far); '' before
  /// the key appears.
  String advance(String text) {
    if (_sent < 0) {
      final match = _key.firstMatch(text);
      if (match == null) return '';
      _sent = match.end;
    }
    if (text.length <= _sent) return '';
    final live = text.substring(_sent);
    _sent = text.length;
    return live;
  }
}
