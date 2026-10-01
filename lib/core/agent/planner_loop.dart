import 'dart:async';

import '../gamedata/gamedata_models.dart';
import '../llm/llm_client.dart';
import 'entity_disambiguator.dart';
import 'investigation_state.dart';
import 'planner_intent.dart';
import 'react_event.dart' show ReActEvent, ReActEventType;
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
    EntityDisambiguator? disambiguator,
    int minimumToolCalls = 0,
    int stepMaxTokens = 1024,
    int safetyMaxIterations = 100,
  })  : _llmClient = llmClient,
        _toolRegistry = toolRegistry,
        _extractorClient = extractorClient,
        _disambiguator = disambiguator,
        _minimumToolCalls = minimumToolCalls,
        _stepMaxTokens = stepMaxTokens,
        _safetyMaxIterations = safetyMaxIterations;

  final LLMClient _llmClient;
  final ToolRegistry _toolRegistry;
  final LLMClient? _extractorClient;
  final EntityDisambiguator? _disambiguator;
  final int _minimumToolCalls;
  final int _stepMaxTokens;
  final int _safetyMaxIterations;

  /// R11: how many times the same search key may repeat before the executor
  /// forces a coverage fallback / unresolved termination.
  static const int _maxSearchRepeats = 2;

  /// R11.2: how many consecutive EMPTY responses before the loop winds down
  /// gently to unresolved (empty output is not a malformed intent).
  static const int _maxEmptyResponses = 3;

  static const String intentFormat = '''
你是剧情调查决策器。每次只输出一行意图命令，严格按以下格式，不要任何其他文字：

READ <story_id> [start_line end_line] [max_lines] [page_token]
SEARCH <query> [id=<entity_id>] [top_k]
MAP <scope_id>
COLLECT <entity_id> [scope_ids=[a,b]] [claim_terms=[c,d]] [page_token]
SUMMARIZE <story_id> [start_line end_line]
RESELECT <entity_id>
VERDICT <culprit> <confidence> <basis>
DONE

规则：
- 一次只输出一行，无前后缀。
- READ 精读章节行区间；MAP 查看章节地图；SEARCH 全文检索；
  COLLECT 收集某实体证据（claim_terms 填案件相关词）。
- 已读章节的要点会记录在调查状态中，不要重复精读同一区间。
- 目标实体已在状态中消歧时，不要重复 SEARCH 原名，直接用其 entity_id；
  SEARCH 支持 id=<entity_id> 直接按 id 检索。
- 消歧结果不对时用 RESELECT <entity_id> 切换到其他候选，不要反复搜索原名。
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
    var emptyResponses = 0;
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
        // R11.2: an EMPTY response means the model has nothing to say (e.g.
        // repeated identical observations exhausted its reasoning). That is
        // NOT a malformed intent — retry a bounded number of times, then wind
        // down gently to unresolved instead of a hard error. Actual garbage
        // text still counts as malformed and terminates.
        if (response.trim().isEmpty) {
          emptyResponses++;
          if (emptyResponses >= _maxEmptyResponses) {
            yield* _terminateUnresolved(
              state,
              '模型多次无输出（可能是对重复观察无话可说），'
                  '已温和结束调查。',
            );
            return;
          }
          recent.add(Message.user(
            'Observation: 收到空输出。请继续调查：基于已读章节 '
            'COLLECT <entity_id> 收集证据，或输出 VERDICT；'
            '若无新进展请输出 DONE 结束。',
          ),);
          continue;
        }
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
      emptyResponses = 0;

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

      if (intent.action == 'RESELECT') {
        final id = '${intent.args['entity_id'] ?? ''}';
        if (id.isEmpty) {
          recent.add(Message.user('Observation: RESELECT 缺 entity_id。'));
          continue;
        }
        final resolved = await _resolveEntityIdOrNull(id, state);
        final target = resolved ?? id;
        final name = state.candidateName(target) ?? target;
        if (state.wasAttempted(target)) {
          recent.add(Message.user(
            'Observation: 候选 $target（$name）本次调查已尝试过，'
            '请从 ${state.candidateIds(excluding: target).join(", ")} 中选择'
            '尚未尝试的候选，或结束调查。',
          ),);
          continue;
        }
        state.setTargetEntity(target, name);
        state.noteSearchedName(target, target);
        // R11.1: the new candidate investigates from its own baseline —
        // clear any counts the previous candidate accumulated so a fresh
        // SEARCH of this id is not mis-terminated as a repeat.
        state.resetSearchTrackingFor(target);
        recent.add(Message.user(
          'Observation: 已切换到候选 $target（$name）。'
          '后续 SEARCH/COLLECT 直接用该 entity_id；该候选的搜索计数已重置，'
          '可从头开始调查。',
        ),);
        onStateChanged?.call(state.serialize());
        yield ReActEvent(
          type: ReActEventType.toolObservation,
          content: '已切换到候选 $target（$name）。',
          toolName: 'reselect',
        );
        continue;
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

      // ── R11.1 SEARCH key normalization ──────────────────────────────
      // Resolve the canonical entity id BEFORE the call so counts and
      // fallback markers use the same key (name/id no longer split), and the
      // already-disambiguated name re-search injects the id instead of
      // re-entering the ambiguity branch.
      var key = '${args['query'] ?? args['entity_id'] ?? ''}';
      if (intent.action == 'SEARCH') {
        final explicitId = args['entity_id'];
        final searchedTarget = state.searchedNameTarget(key);
        if (searchedTarget != null && explicitId is! String) {
          args['entity_id'] = searchedTarget;
          key = searchedTarget;
        } else if (explicitId is String && explicitId.trim().isNotEmpty) {
          key = explicitId.trim();
        }
      }

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
      // R10: when SEARCH hits an ambiguous entity, auto-pick the top
      // candidate into state and tell the model, so it never loops on the
      // same ambiguous query. R11: the pick is done by the disambiguation
      // helper (semantic fit with the question), falling back to #1.
      if (intent.action == 'SEARCH') {
        final isAmbiguous = observation.contains('Ambiguous');
        final hasResult = !isAmbiguous && !_isNoResult(observation);
        // R11.1: count progress AFTER the call — productive repeats (fresh
        // results) reset the counters; only no-result / identical-content
        // repeats accumulate, and only then may the executor terminate.
        final contentChanged =
            state.hasSearchContentChanged(key, observation);
        state.noteSearchProgress(
          key: key,
          hadResult: hasResult,
          contentChanged: contentChanged,
        );
        state.noteSearchObservation(key, observation);

        final repeats = state.searchRepeatCount(key);
        final alreadyFellBack = state.hasCoverageFallback(key);
        if (repeats > _maxSearchRepeats || state.consecutiveNoResult >= 2) {
          // Same key keeps producing NO progress. Before terminating, check
          // whether the investigation has made non-search progress: if it
          // has, guide the model to use it (COLLECT / VERDICT) instead of
          // killing a live investigation.
          final progressed = state.hasReadOrEvidence;
          final guided = alreadyFellBack || progressed;
          if (!guided) {
            final fallback = await _coverageFallback(
              state: state,
              query: '${args['query'] ?? ''}',
              entityId: '${args['entity_id'] ?? ''}',
            );
            if (fallback != null) {
              state.noteCoverageFallback(key);
              recent.add(Message.user('Observation: $fallback'));
              onStateChanged?.call(state.serialize());
              yield ReActEvent(
                type: ReActEventType.toolObservation,
                content: fallback,
                toolName: 'search_story_coverage',
              );
              continue;
            }
            // No coverage at all and no other progress: terminate.
            yield* _terminateUnresolved(
              state,
              '连续多次 SEARCH「$key」均无新信息，'
                  '且该实体没有可枚举的剧情出场。',
            );
            return;
          }
          // Has read/evidence (or already fell back): guide, do not kill.
          final guide = 'SEARCH「$key」连续无新信息，但调查已有'
              '${state.reads.length} 个已读章节'
              '${state.evidence.any((e) => e.evidenceRows > 0) ? '与证据' : ''}。'
              '请停止重复搜索，改为：对已读章节中的嫌疑人调用 '
              'COLLECT <entity_id> claim_terms=[...] 收集证据，'
              '或基于已读内容直接输出 VERDICT。';
          state.noteCoverageFallback(key);
          recent.add(Message.user('Observation: $guide'));
          onStateChanged?.call(state.serialize());
          yield ReActEvent(
            type: ReActEventType.toolObservation,
            content: guide,
            toolName: 'search_local_lore',
          );
          continue;
        }
        if (isAmbiguous) {
          final candidates = _parseCandidates(observation);
          final pick = await _disambiguateOrTop(
            candidates: candidates,
            query: '${args['query'] ?? ''}',
            state: state,
          );
          if (pick != null) {
            state.setTargetEntity(pick.entityId, pick.name);
            state.noteSearchedName('${args['query'] ?? ''}', pick.entityId);
            state.setCandidateNames({
              for (final c in candidates) c.entityId: c.name,
            });
            observation = '实体歧义已按问题语义消解：目标实体 = '
                '${pick.entityId}（${pick.name}'
                '${pick.choseTopFallback ? '，消歧失败回退最高置信度候选' : ''}）。'
                '后续 SEARCH/COLLECT 请直接用该 entity_id；若选择不对，'
                '可用 RESELECT 切换其他候选。';
          } else {
            // No candidates parsed (should not happen): keep the compact
            // ambiguous observation so the model sees the list.
          }
        }
      }
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

  /// Extracts candidate entities from a compact "Ambiguous" observation
  /// (R10/R11 form: "  1. `entity_id` | `name` | `type` | `source` | ...").
  List<_Candidate> _parseCandidates(String observation) {
    final linePattern = RegExp(
      r'^\s*(\d+)\.\s+(\S+)\s*\|\s*([^|\n]+)',
      multiLine: true,
    );
    final candidates = <_Candidate>[];
    for (final match in linePattern.allMatches(observation)) {
      candidates.add(_Candidate(
        entityId: match.group(2)!.trim(),
        name: match.group(3)!.trim(),
      ),);
    }
    return candidates;
  }

  /// Runs the disambiguation helper over [candidates]; falls back to the
  /// top candidate when the helper is unavailable or fails (R11).
  Future<_Candidate?> _disambiguateOrTop({
    required List<_Candidate> candidates,
    required String query,
    required InvestigationState state,
  }) async {
    if (candidates.isEmpty) return null;
    final helper = _disambiguator;
    if (helper == null) return candidates.first;
    final resolved = await _resolveCandidateIds(candidates);
    final result = await helper.choose(
      query: query,
      candidates: resolved,
      excludeIds: state.wasAttempted(resolved.first.entityId)
          ? state.candidateIds(excluding: resolved.first.entityId)
          : [],
    );
    return _Candidate(
      entityId: result.entityId,
      name: result.name,
      choseTopFallback: result.choseTopFallback,
    );
  }

  /// Converts parsed compact candidates into [GameDataEntityCandidate]s for
  /// the disambiguation helper (ids come canonical from the tool).
  Future<List<GameDataEntityCandidate>> _resolveCandidateIds(
    List<_Candidate> candidates,
  ) async {
    return [
      for (final c in candidates)
        GameDataEntityCandidate(
          entityId: c.entityId,
          name: c.name,
          entityType: 'entity',
          sourceType: 'game_data',
          matchedAlias: '',
          matchType: 'name_exact',
          confidence: 1.0,
        ),
    ];
  }

  /// Lightweight id resolution for RESELECT: prefers a candidate from the
  /// last disambiguation list; otherwise accepts the raw id as-is (the tool
  /// layer resolves suffix-only ids against the DB).
  Future<String?> _resolveEntityIdOrNull(String raw, InvestigationState state) async {
    final value = raw.trim();
    if (value.isEmpty) return null;
    final candidates = state.candidateIds();
    if (candidates.contains(value)) return value;
    // Suffix-only: find the canonical candidate whose id ends with `:<value>`
    // or equals it.
    for (final id in candidates) {
      if (id == value || id.endsWith(':$value')) return id;
    }
    return value.isEmpty ? null : value;
  }

  /// Emits a final `culprit=unresolved` answer with [reason] and ends the
  /// run (R11.1): only reached when NO non-search progress exists.
  Stream<ReActEvent> _terminateUnresolved(
    InvestigationState state,
    String reason,
  ) async* {
    yield* _emitFinal(
      '[INVESTIGATION_VERDICT: culprit=unresolved | confidence=0 | '
      'basis=insufficient_evidence]\n'
      '调查无法推进：$reason\n'
      '已收集内容：\n${state.serialize()}',
    );
    yield const ReActEvent(type: ReActEventType.complete);
  }

  /// Forces `search_story_coverage` for [entityId]/[query] and returns a
  /// short observation for the next loop turn, or null when the entity has no
  /// coverage at all (caller terminates with unresolved).
  Future<String?> _coverageFallback({
    required InvestigationState state,
    required String query,
    required String entityId,
  }) async {
    final tool = _toolRegistry.getTool('search_story_coverage');
    if (tool == null) return null;
    final target = entityId.isNotEmpty
        ? entityId
        : state.targetEntityId;
    if (target == null || target.isEmpty) {
      return '无法自动转枚举出场：目标实体未消歧。请先 SEARCH 原名或 id= 消歧。';
    }
    final result = await tool.execute({'entity_id': target});
    final observation = (result is ToolExecutionResult)
        ? result.observation
        : '${result ?? ''}';
    state.noteStage('S1');
    // Empty coverage: nothing enumerable — let the caller terminate with
    // unresolved instead of feeding the model a pointless observation.
    if (_isEmptyCoverage(observation)) return null;
    return 'SEARCH 重复且无进展，已自动转 search_story_coverage 枚举出场：\n'
        '$observation';
  }

  bool _isEmptyCoverage(String observation) {
    final lower = observation.toLowerCase();
    return lower.contains('no story coverage found') ||
        lower.contains('coverage scopes: 0') ||
        lower.contains('coverage stories: 0');
  }

  bool _isNoResult(String observation) {
    final lower = observation.toLowerCase();
    return lower.contains('no matching') ||
        lower.contains('no result') ||
        lower.contains('未找到') ||
        lower.contains('not found') ||
        lower.contains('no appearances');
  }

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
      case 'RESELECT':
        state.noteStage('S1');
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

/// One candidate parsed from a compact ambiguous observation.
class _Candidate {
  const _Candidate({
    required this.entityId,
    required this.name,
    this.choseTopFallback = false,
  });
  final String entityId;
  final String name;
  final bool choseTopFallback;
}
