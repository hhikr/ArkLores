import 'dart:async';

import '../gamedata/gamedata_models.dart';
import '../llm/completion_budget.dart';
import '../llm/llm_client.dart';
import 'entity_disambiguator.dart';
import 'evidence_notebook.dart';
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
    LLMClient? writerClient,
    LLMClient? extractorClient,
    EntityDisambiguator? disambiguator,
    int minimumToolCalls = 0,
    int stepMaxTokens = 1024,
    int safetyMaxIterations = 100,
    int maxToolSteps = 40,
  })  : _maxToolSteps = maxToolSteps,
        _llmClient = llmClient,
        _writerClient = writerClient ?? llmClient,
        _toolRegistry = toolRegistry,
        _extractorClient = extractorClient,
        _disambiguator = disambiguator,
        _minimumToolCalls = minimumToolCalls,
        _stepMaxTokens = stepMaxTokens,
        _safetyMaxIterations = safetyMaxIterations;

  final LLMClient _llmClient;

  /// Writes the final answer (defaults to [_llmClient]); kept separate so
  /// the per-step decision model can run cheaper than the writer (R12).
  final LLMClient _writerClient;
  final ToolRegistry _toolRegistry;
  final LLMClient? _extractorClient;
  final EntityDisambiguator? _disambiguator;
  final int _minimumToolCalls;
  final int _stepMaxTokens;
  final int _safetyMaxIterations;

  /// R12: total tool-step budget; when spent, the answer is written from the
  /// evidence gathered so far (eval: one question looped 54 steps).
  final int _maxToolSteps;

  /// R12: older recent-window messages are clipped to this many characters.
  static const int _clipOlder = 600;

  /// R12: consecutive steps without state growth before a nudge / a finish.
  static const int _stallNudge = 4;
  static const int _stallFinish = 8;

  /// Intents that are deterministic lookups: re-running one with identical
  /// arguments can only return what the state already holds.
  static const Set<String> _dedupActions = {
    'FIND',
    'COVER',
    'MAP',
    'COLLECT',
    'READ',
    'SUMMARIZE',
  };

  /// R11: how many times the same search key may repeat before the executor
  /// forces a coverage fallback / unresolved termination.
  static const int _maxSearchRepeats = 2;

  /// R11.2: how many consecutive EMPTY responses before the loop winds down
  /// gently to unresolved (empty output is not a malformed intent).
  static const int _maxEmptyResponses = 3;

  static const String intentFormat = '''
你是剧情调查决策器。每次只输出一行意图命令，严格按以下格式，不要任何其他文字：

COVER <名字|entity_id> [scope=<scope_id>]
FIND <短语或空格分隔的词> [scope=<scope_id>] [top_k]
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
- 找剧情：COVER 列出某人物/实体在哪些章节、哪些行出场；FIND 在剧情原文
  中检索短语（事件、地点、物品、台词关键词），返回章节与行号线索。
- READ 精读章节行区间：只有 READ 读到的原文才会记为证据笔记。
- SEARCH 只查实体档案/资料（干员档案、敌人图鉴等），不检索剧情原文。
- MAP 查看章节地图；COLLECT 收集某实体证据（claim_terms 填相关词）。
- 已读区间与证据笔记记录在调查状态中，不要重复精读同一区间。
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
    // R12: the lines READ actually returned, for the writer when the
    // notebook is thin (e.g. the extractor found nothing or failed).
    final readPages = <ReadPage>[];
    final recent = <Message>[];
    var iteration = 0;
    var completedToolCalls = 0;
    var malformed = 0;
    var emptyResponses = 0;
    var networkRetries = 0;
    // R12 progress control: tool steps, consecutive steps without state
    // growth, and the signatures of deterministic lookups already executed.
    var toolSteps = 0;
    var stalled = 0;
    var lastFingerprint = '';
    final executed = <String, int>{};

    // R12 cost control: only the latest observation is sent in full; older
    // window entries are clipped (read text already lives in the notebook,
    // searches in the search log). Input tokens dominated after reasoning
    // was turned off for the planner.
    List<Message> buildRequest() => [
          Message.system('$systemPrompt\n\n$intentFormat'),
          ...chatHistory,
          Message.user(
            '目标: $userQuery\n\n当前调查状态:\n${state.serialize()}',
          ),
          for (var i = 0; i < recent.length; i++)
            i == recent.length - 1 || recent[i].content.length <= _clipOlder
                ? recent[i]
                : Message.user(
                    '${recent[i].content.substring(0, _clipOlder)}…（已截断）',
                  ),
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
        // R12: a reasoning model may spend the whole ceiling on hidden
        // reasoning and return empty content; retry with headroom before
        // treating the reply as empty.
        completion = await completeWithHeadroom(
          _llmClient,
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
            yield* _finishFromState(
              state,
              readPages,
              userQuery,
              basis: 'empty_replies',
              reason: '模型多次无输出，已基于已读内容结束调查。',
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
          '(COVER/FIND/READ/SEARCH/MAP/COLLECT/SUMMARIZE/RESELECT/VERDICT/DONE)。',
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
        // R12: envelope fields are short tokens; a model may put a whole
        // sentence in `basis` (seen with reasoning off) — the writer explains
        // the reasoning in the body instead.
        final rawBasis = '${intent.args['basis'] ?? 'multi_hypothesis_contrast'}';
        yield* _finish(
          culprit: culprit,
          confidence: '${intent.args['confidence'] ?? '0.7'}',
          basis: RegExp(r'^[A-Za-z_\-]{1,40}$').hasMatch(rawBasis)
              ? rawBasis
              : 'stated_in_answer',
          state: state,
          readPages: readPages,
          userQuery: userQuery,
        );
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

      // ── R12 progress control ────────────────────────────────────────
      // Measured at the start of each tool step against the state after the
      // previous one, so every path (including early `continue`s) counts.
      toolSteps++;
      final fingerprint = state.progressFingerprint;
      stalled = fingerprint == lastFingerprint ? stalled + 1 : 0;
      lastFingerprint = fingerprint;
      if (toolSteps > _maxToolSteps || stalled >= _stallFinish) {
        yield* _finishFromState(
          state,
          readPages,
          userQuery,
          basis: toolSteps > _maxToolSteps ? 'step_budget' : 'stalled',
          reason: toolSteps > _maxToolSteps
              ? '已用完 $_maxToolSteps 步调查预算。'
              : '连续 $stalled 步没有获得新信息。',
        );
        return;
      }
      if (stalled == _stallNudge) {
        recent.add(Message.user(
          'Observation: 最近 $_stallNudge 步没有获得新信息。请 READ 尚未读过的'
          '章节、换一个检索方向，或基于证据笔记输出 VERDICT。',
        ),);
      }

      // R12: a deterministic lookup with identical arguments can only return
      // what the state already holds — answer from state instead of re-running.
      if (_dedupActions.contains(intent.action)) {
        final signature = '${intent.action} ${_canonicalArgs(args)}';
        final previous = executed[signature];
        final storyId = '${args['story_id'] ?? ''}';
        final start = (args['start_line'] as num?)?.toInt();
        final end = (args['end_line'] as num?)?.toInt();
        final rangeRead = intent.action == 'READ' &&
            start != null &&
            end != null &&
            state.wasRangeRead(storyId, start, end);
        if (previous != null || rangeRead) {
          final note = rangeRead
              ? 'READ $storyId $start-$end 的内容已经读过，要点在“证据笔记”中。'
              : '该命令在第 $previous 步已执行过，结果已记录在调查状态'
                  '（已检索/已读/证据笔记）中。';
          recent.add(Message.user(
            'Observation: $note请换关键词、READ 未读的章节，或输出 VERDICT。',
          ),);
          if (recent.length > 2) recent.removeAt(0);
          yield ReActEvent(
            type: ReActEventType.toolObservation,
            content: note,
            toolName: toolName,
          );
          continue;
        }
        executed[signature] = iteration;
      }

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
        if (repeats > _maxSearchRepeats ||
            state.consecutiveNoResult(key) >= 2) {
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
          // R12: the guide must match the actual state — with nothing read
          // yet, point at the story-finding intents instead of "已读章节".
          final guide = progressed
              ? 'SEARCH「$key」连续无新信息，但调查已有'
                  '${state.reads.length} 个已读章节'
                  '${state.evidence.any((e) => e.evidenceRows > 0) ? '与证据' : ''}。'
                  '请停止重复搜索，改为：基于证据笔记继续 READ/FIND，对相关'
                  '人物 COLLECT <entity_id> claim_terms=[...]，'
                  '或直接输出 VERDICT。'
              : 'SEARCH「$key」连续无新信息，且已做过出场枚举。SEARCH 只查'
                  '实体档案；请改用 FIND <短语> 检索剧情原文，或 READ 出场'
                  '枚举中的章节。';
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
      if (intent.action == 'FIND' || intent.action == 'COVER') {
        state.noteSearchLog(_searchLogKey(intent.action, args), _storyIdsIn(observation));
      }
      recent.add(Message.user('Observation: $observation'));
      if (recent.length > 2) recent.removeAt(0);
      onStateChanged?.call(state.serialize());
      yield ReActEvent(
        type: ReActEventType.toolObservation,
        content: observation,
        toolName: toolName,
      );

      // R12: after READ, question-aware extraction turns the returned lines
      // into line-anchored notes in state, so read content survives the
      // 2-message recent window and reaches the writer (M-C).
      final page = (intent.action == 'READ' || intent.action == 'SUMMARIZE')
          ? parseReadObservation(observation)
          : null;
      if (page != null) {
        readPages.add(page);
        final extractor = _extractorClient;
        if (extractor != null) {
          final notes = await extractEvidenceNotes(
            extractor,
            userQuery: userQuery,
            page: page,
          );
          if (notes.isNotEmpty) {
            state.addNotes(notes);
            onStateChanged?.call(state.serialize());
          }
        }
      }
    }
  }

  String _toolNameFor(String action) => switch (action) {
        'READ' => 'read_story_lines',
        'SEARCH' => 'search_local_lore',
        'COVER' => 'search_story_coverage',
        'FIND' => 'search_story_lines',
        'MAP' => 'get_story_map',
        'COLLECT' => 'collect_suspect_evidence',
        'SUMMARIZE' => 'read_story_lines',
        _ => '',
      };

  Map<String, dynamic> _intentArgsToToolArgs(IntentRecord intent) =>
      Map<String, dynamic>.from(intent.args);

  /// Order-independent rendering of tool args for duplicate detection.
  static String _canonicalArgs(Map<String, dynamic> args) {
    final keys = args.keys.toList()..sort();
    return keys.map((k) => '$k=${args[k]}').join(';');
  }

  /// `FIND 匕首 @scope` / `COVER 角色名` — the state's search-log key.
  static String _searchLogKey(String action, Map<String, dynamic> args) {
    final target = args['query'] ?? args['entity_id'] ?? '';
    final scope = args['scope_id'] ?? args['scope_filter'];
    return '$action $target${scope == null ? '' : ' @$scope'}';
  }

  /// First story ids listed in a FIND/COVER observation (`Story: <id> | …`).
  static List<String> _storyIdsIn(String observation, {int limit = 5}) {
    final ids = <String>[];
    for (final match
        in RegExp(r'^Story: (\S+)', multiLine: true).allMatches(observation)) {
      final id = match.group(1)!;
      if (!ids.contains(id)) ids.add(id);
      if (ids.length >= limit) break;
    }
    return ids;
  }

  /// Extracts candidate entities from a compact "Ambiguous" observation
  /// (R10/R11 form: "  1. id | name | type | source | match_type | conf").
  /// R12: the type/source/match columns are kept — the disambiguation helper
  /// previously received a hard-coded `entity`/`game_data` for every
  /// candidate and could only judge by id and name.
  List<_Candidate> _parseCandidates(String observation) {
    final linePattern = RegExp(r'^\s*(\d+)\.\s+(\S+)\s*\|(.*)$', multiLine: true);
    final candidates = <_Candidate>[];
    for (final match in linePattern.allMatches(observation)) {
      final cols = match.group(3)!.split('|').map((c) => c.trim()).toList();
      String col(int i) => i < cols.length ? cols[i] : '';
      candidates.add(_Candidate(
        entityId: match.group(2)!.trim(),
        name: col(0),
        entityType: col(1),
        sourceType: col(2),
        matchType: col(3),
        confidence: double.tryParse(col(4)),
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
          entityType: c.entityType.isEmpty ? 'entity' : c.entityType,
          sourceType: c.sourceType.isEmpty ? 'game_data' : c.sourceType,
          matchedAlias: '',
          matchType: c.matchType.isEmpty ? 'name_exact' : c.matchType,
          confidence: c.confidence ?? 1.0,
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

  /// Writer role (M-C) + R12 provenance: composes the answer from the
  /// notebook and read lines, checks every cited line was actually read
  /// (one corrective rewrite, then a source warning), emits it and completes.
  Stream<ReActEvent> _finish({
    required String culprit,
    required String confidence,
    required String basis,
    required InvestigationState state,
    required List<ReadPage> readPages,
    required String userQuery,
  }) async* {
    String body;
    try {
      body = await _composeAnswer(
        culprit: culprit,
        confidence: confidence,
        basis: basis,
        state: state,
        readPages: readPages,
        userQuery: userQuery,
      );
      var invalid = unreadCitations(body, state);
      if (invalid.isNotEmpty) {
        body = await _composeAnswer(
          culprit: culprit,
          confidence: confidence,
          basis: basis,
          state: state,
          readPages: readPages,
          userQuery: userQuery,
          invalidCitations: invalid,
        );
        invalid = unreadCitations(body, state);
      }
      if (invalid.isNotEmpty) {
        body = '$body\n\n> 来源警告：以下引用的行未在本次调查中实际读取，'
            '可能不准确：${invalid.join('、')}';
      }
    } catch (e) {
      body = '（无法生成答案正文：$e）';
    }
    yield* _emitFinal(
      '[INVESTIGATION_VERDICT: culprit=$culprit | '
      'confidence=$confidence | basis=$basis]\n$body',
    );
    yield const ReActEvent(type: ReActEventType.complete);
  }

  /// R12: ends a run that stopped making progress (stall, step budget,
  /// repeated empty replies). With anything read, the writer still answers
  /// from the evidence gathered — an honest partial answer beats discarding
  /// read lines; with nothing read it is a plain unresolved.
  Stream<ReActEvent> _finishFromState(
    InvestigationState state,
    List<ReadPage> readPages,
    String userQuery, {
    required String basis,
    required String reason,
  }) {
    if (readPages.isEmpty && state.notes.isEmpty) {
      return _terminateUnresolved(state, reason);
    }
    return _finish(
      culprit: 'unresolved',
      confidence: '0',
      basis: basis,
      state: state,
      readPages: readPages,
      userQuery: userQuery,
    );
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
      case 'SUMMARIZE':
        // R12: record the lines the tool ACTUALLY returned (DATA block /
        // row numbers), not the requested window — the observation budget
        // may cut a page short, and nothing unread may count as read.
        final page = parseReadObservation(observation);
        if (page == null) return;
        state.noteRead(page.storyId, page.firstLine, page.lastLine);
        state.noteStage(action == 'READ' ? 'S3' : 'S4');
      case 'COVER':
        state.noteStage('S1');
      case 'FIND':
        state.noteStage('S1');
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

  /// Upper bound of raw read text handed to the writer.
  static const int _maxWriterSourceChars = 8000;

  /// Writer role: turns the final verdict + state into a structured answer.
  /// R12: the writer sees the evidence notebook AND the raw lines READ
  /// returned, so the answer rests on original text instead of the planner
  /// model's memory; [invalidCitations] drives a corrective rewrite.
  Future<String> _composeAnswer({
    required String culprit,
    required String confidence,
    required String basis,
    required InvestigationState state,
    required List<ReadPage> readPages,
    required String userQuery,
    List<String> invalidCitations = const [],
  }) async {
    final source = StringBuffer();
    for (final page in readPages) {
      for (final line in page.lines) {
        final row = '${page.storyId}:${line.index} ${line.text}\n';
        if (source.length + row.length > _maxWriterSourceChars) break;
        source.write(row);
      }
    }
    final correction = invalidCitations.isEmpty
        ? ''
        : '\n\n上一版答案引用了未读取的行：${invalidCitations.join('、')}。'
            '请重写，只引用下方“已读原文”中出现的 story_id:行号。';
    final result = await completeWithHeadroom(
      _writerClient,
      [
        Message.system(
          '你是剧情调查员。只根据下方“证据笔记”和“已读原文”回答用户问题：\n'
          '1. 开头一行直接回答问题。调查决策器给出的结论主体是 $culprit'
          '（置信度 $confidence，依据 $basis）；若原文不支持它，直接说明并给出'
          '原文真正支持的答案。\n'
          '2. 然后 2-5 条证据，每条附引用，格式为 story_id:行号（或 '
          'story_id:起-止），只能引用已读原文中出现的行。\n'
          '3. 列出与结论矛盾或削弱结论的原文（如有）。\n'
          '4. 最后一段写置信度（0-1）与可能的替代解读。\n'
          '原文没有覆盖的部分明确写“资料未覆盖”，不得用记忆补充。用 Markdown。',
        ),
        Message.user(
          '问题: $userQuery\n\n调查状态:\n${state.serialize()}'
          '\n\n已读原文:\n${source.isEmpty ? '（无）' : source}$correction',
        ),
      ],
      temperature: 0.2,
      maxTokens: 4096,
      retryPartial: true, // a cut-off answer is not an answer
    );
    return result.content.trim();
  }
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
    this.entityType = '',
    this.sourceType = '',
    this.matchType = '',
    this.confidence,
    this.choseTopFallback = false,
  });
  final String entityId;
  final String name;
  final String entityType;
  final String sourceType;
  final String matchType;
  final double? confidence;
  final bool choseTopFallback;
}
