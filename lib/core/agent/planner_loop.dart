import 'dart:async';

import '../llm/llm_client.dart';
import 'investigation_state.dart';
import 'planner_intent.dart';
import 'react_loop.dart' show ReActEvent, ReActEventType;
import 'tools/agent_tool.dart';
import 'tools/tool_registry.dart';

/// Planner loop (R8, M-A): the decision agent outputs a single short intent
/// per call; a code executor runs the tool, parses the result and updates the
/// [InvestigationState]; an optional extractor turns read observations into
/// key points. The request context is bounded (state serialization + last
/// observation), so it never grows with the investigation — nothing needs
/// truncating.
class PlannerLoop {
  PlannerLoop({
    required LLMClient llmClient,
    required ToolRegistry toolRegistry,
    LLMClient? extractorClient,
    int minimumToolCalls = 0,
    int stepMaxTokens = 1024,
    int safetyMaxIterations = 100,
  })  : _llmClient = llmClient,
        _toolRegistry = toolRegistry,
        _extractorClient = extractorClient,
        _minimumToolCalls = minimumToolCalls,
        _stepMaxTokens = stepMaxTokens,
        _safetyMaxIterations = safetyMaxIterations;

  final LLMClient _llmClient;
  final ToolRegistry _toolRegistry;
  final LLMClient? _extractorClient;
  final int _minimumToolCalls;
  final int _stepMaxTokens;
  final int _safetyMaxIterations;

  static const String intentFormat = '''
你是剧情调查决策器。每次只输出一行意图命令，严格按以下格式，不要任何其他文字：

READ <story_id> [start_line end_line] [max_lines] [page_token]
SEARCH <query> [top_k]
MAP <scope_id>
COLLECT <entity_id> [scope_ids=[a,b]] [claim_terms=[c,d]] [page_token]
SUMMARIZE <story_id> [start_line end_line]
VERDICT <culprit> <confidence> <basis>
DONE

规则：
- 一次只输出一行，无前后缀。
- READ 精读章节行区间；MAP 查看章节地图；SEARCH 全文检索；
  COLLECT 收集某实体证据（claim_terms 填案件相关词）。
- 已读章节的要点会记录在调查状态中，不要重复精读同一区间。
- 已有足够证据时输出 VERDICT，下一轮输出 DONE。
''';

  /// Runs the planner loop, yielding streamed [ReActEvent]s compatible with
  /// the existing chat UI.
  Stream<ReActEvent> run({
    required String systemPrompt,
    required List<Message> chatHistory,
    required String userQuery,
    void Function(int iteration, String rawResponse)? onRawLlmResponse,
    void Function(String state)? onStateChanged,
  }) async* {
    final state = InvestigationState();
    final recent = <Message>[];
    var iteration = 0;
    var completedToolCalls = 0;
    var malformed = 0;
    var networkRetries = 0;

    List<Message> buildRequest() => [
          Message.system('$systemPrompt\n\n$intentFormat'),
          ...chatHistory,
          Message.user(
            '目标: $userQuery\n\n当前调查状态:\n${state.serialize()}',
          ),
          ...recent,
        ];

    while (true) {
      iteration++;
      if (iteration > _safetyMaxIterations) {
        yield const ReActEvent(
          type: ReActEventType.error,
          content: 'SAFETY CAP: too many iterations without a verdict.',
        );
        return;
      }

      ChatCompletionResult completion;
      try {
        completion = await _llmClient.chatCompletion(
          buildRequest(),
          temperature: 0.1,
          maxTokens: _stepMaxTokens,
        );
      } catch (e) {
        if (_isNetworkError('$e') && networkRetries < 2) {
          networkRetries++;
          recent.add(Message.user(
            'Observation: 网络错误，请重试当前步骤。',
          ),);
          continue;
        }
        yield ReActEvent(
          type: ReActEventType.error,
          content: 'LLM Error: $e',
        );
        return;
      }
      networkRetries = 0;
      final response = completion.content.trim();
      onRawLlmResponse?.call(iteration, response);

      final intent = parseIntent(response);
      if (intent == null) {
        malformed++;
        if (malformed >= 3) {
          yield const ReActEvent(
            type: ReActEventType.error,
            content: '模型连续输出无效意图，终止。',
          );
          return;
        }
        recent.add(Message.user(
          'Observation: 无效意图："$response"。请只输出一行 intent '
          '(READ/SEARCH/MAP/COLLECT/SUMMARIZE/VERDICT/DONE)。',
        ),);
        continue;
      }
      malformed = 0;

      if (intent.action == 'DONE') {
        if (completedToolCalls < _minimumToolCalls) {
          recent.add(Message.user(
            'Observation: 工具调用不足 $_minimumToolCalls 次，继续调查。',
          ),);
          continue;
        }
        yield const ReActEvent(type: ReActEventType.complete);
        return;
      }

      if (intent.action == 'VERDICT') {
        final culprit = '${intent.args['culprit'] ?? ''}';
        if (culprit.isEmpty) {
          recent.add(Message.user('Observation: VERDICT 缺 culprit。'));
          continue;
        }
        final basis = '${intent.args['basis'] ?? 'multi_hypothesis_contrast'}';
        final confidence = '${intent.args['confidence'] ?? '0.7'}';
        // Writer role (M-C): compose the answer body from the state — one
        // bounded call citing what was actually read/collected.
        String body;
        try {
          body = await _composeAnswer(
            culprit: culprit,
            confidence: confidence,
            basis: basis,
            state: state,
            userQuery: userQuery,
          );
        } catch (e) {
          body = '（无法生成答案正文：$e）';
        }
        final answer = '[INVESTIGATION_VERDICT: culprit=$culprit | '
            'confidence=$confidence | basis=$basis]\n$body';
        yield* _emitFinal(answer);
        yield const ReActEvent(type: ReActEventType.complete);
        return;
      }

      final toolName = _toolNameFor(intent.action);
      final tool = _toolRegistry.getTool(toolName);
      if (tool == null) {
        recent.add(Message.user(
          'Observation: 工具 $toolName 不存在。',
        ),);
        continue;
      }
      final args = _intentArgsToToolArgs(intent);
      yield ReActEvent(
        type: ReActEventType.toolCall,
        content: 'Executing tool "$toolName" with arguments: $args',
        toolName: toolName,
        toolArgs: args,
      );
      String observation;
      try {
        final result = await tool.execute(args);
        observation = (result is ToolExecutionResult)
            ? result.observation
            : '${result ?? 'No output'}';
      } catch (e) {
        observation = 'Error executing tool: $e';
      }
      completedToolCalls++;
      _updateState(state, intent.action, args, observation);
      recent.add(Message.user('Observation: $observation'));
      if (recent.length > 2) recent.removeAt(0);
      onStateChanged?.call(state.serialize());
      yield ReActEvent(
        type: ReActEventType.toolObservation,
        content: observation,
        toolName: toolName,
      );

      // Automatic extraction after READ so key points live in state and the
      // model never re-reads to recall content (M-C).
      if (intent.action == 'READ' && _extractorClient != null) {
        try {
          final points = await extractKeyPoints(_extractorClient, observation);
          state.setKeyPoints('${args['story_id']}', points);
        } catch (_) {
          // Extraction failure is non-fatal; the read index remains.
        }
      }
    }
  }

  String _toolNameFor(String action) => switch (action) {
        'READ' => 'read_story_lines',
        'SEARCH' => 'search_local_lore',
        'MAP' => 'get_story_map',
        'COLLECT' => 'collect_suspect_evidence',
        'SUMMARIZE' => 'read_story_lines',
        _ => '',
      };

  Map<String, dynamic> _intentArgsToToolArgs(IntentRecord intent) =>
      Map<String, dynamic>.from(intent.args);

  void _updateState(
    InvestigationState state,
    String action,
    Map<String, dynamic> args,
    String observation,
  ) {
    switch (action) {
      case 'READ':
        final storyId = '${args['story_id'] ?? ''}';
        if (storyId.isEmpty) return;
        final start = (args['start_line'] as num?)?.toInt() ?? 0;
        final end = (args['end_line'] as num?)?.toInt() ??
            (start + ((args['max_lines'] as num?)?.toInt() ?? 60));
        state.noteRead(storyId, start, end);
        state.noteStage('S3');
      case 'MAP':
        final scopeId = '${args['scope_id'] ?? ''}';
        if (scopeId.isNotEmpty) state.noteMapped(scopeId);
        state.noteStage('S2');
      case 'COLLECT':
        final entityId = '${args['entity_id'] ?? ''}';
        final rowsMatch = RegExp(r'evidence_rows[":\s]+(\d+)')
            .firstMatch(observation);
        final rows = int.tryParse(rowsMatch?.group(1) ?? '') ?? 0;
        state.noteEvidence(entityId, evidenceRows: rows, scopes: const []);
        state.noteStage('S6');
      case 'SEARCH':
        state.noteStage('S1');
      case 'SUMMARIZE':
        state.noteStage('S4');
    }
  }

  Stream<ReActEvent> _emitFinal(String answer) async* {
    const chunkSize = 120;
    for (var i = 0; i < answer.length; i += chunkSize) {
      final end = i + chunkSize < answer.length ? i + chunkSize : answer.length;
      yield ReActEvent(
        type: ReActEventType.finalAnswerToken,
        content: answer.substring(i, end),
      );
    }
  }

  /// Writer role: turns the final verdict + state into a structured answer
  /// with line-level citations drawn from what was actually read/collected.
  Future<String> _composeAnswer({
    required String culprit,
    required String confidence,
    required String basis,
    required InvestigationState state,
    required String userQuery,
  }) async {
    final result = await _llmClient.chatCompletion(
      [
        Message.system(
          '你是剧情调查员。基于调查状态写最终答案：开头一行结论（凶手/主犯是 '
          '$culprit，置信度 $confidence，依据 $basis），然后 2-4 条证据'
          '（引用实际读取的章节与行区间），如有可能列出反方证据。'
          '每条证据必须来自"已读"列表中的章节。用 Markdown。',
        ),
        Message.user('问题: $userQuery\n\n调查状态:\n${state.serialize()}'),
      ],
      temperature: 0.2,
      maxTokens: 2048,
    );
    return result.content.trim();
  }
}

/// Condenses a raw read observation into ≤150-char key points (M-C).
Future<String> extractKeyPoints(LLMClient client, String passage) async {
  final limited = passage.length > 3000
      ? passage.substring(0, 3000)
      : passage;
  final result = await client.chatCompletion(
    [
      Message.system(
        '用不超过150个字提取这段剧情的关键要点：谁、发生了什么、任何直接指认/动作/证据。不要总结评价，只要事实要点。',
      ),
      Message.user(limited),
    ],
    temperature: 0,
    maxTokens: 256,
  );
  final points = result.content.trim();
  return points.length > 150 ? points.substring(0, 150) : points;
}

bool _isNetworkError(String message) {
  final lower = message.toLowerCase();
  return lower.contains('connection closed') ||
      lower.contains('socketexception') ||
      lower.contains('clientexception') ||
      lower.contains('connection refused') ||
      lower.contains('timed out') ||
      lower.contains('handshakeexception') ||
      lower.contains('connection terminated');
}
