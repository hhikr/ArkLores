import 'dart:async';

import '../gamedata/gamedata_models.dart';
import '../llm/completion_budget.dart';
import '../llm/llm_client.dart';
import 'entity_disambiguator.dart';
import 'evidence_notebook.dart';
import 'investigation_state.dart';
import 'planner_intent.dart';
import 'react_event.dart' show ReActEvent, ReActEventType;
import 'story_answer.dart';
import 'tools/agent_tool.dart';
import 'tools/tool_registry.dart';

/// Planner loop (R8, M-A): the decision agent outputs a single short intent
/// per call; a code executor runs the tool, parses the result and updates the
/// [InvestigationState]; an extractor turns read pages into line-anchored
/// notes; a writer answers from the notes and the read lines. The request
/// context is bounded (state serialization + last observation), so it never
/// grows with the run.
///
/// R13: one pipeline for every story question. [AnswerStyle] only changes the
/// writer's output format; retrieval, evidence, citation checks and the
/// [StoryAnswerStatus] are the same for all questions and styles.
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
  /// evidence gathered so far.
  final int _maxToolSteps;

  /// R12: older recent-window messages are clipped to this many characters.
  static const int _clipOlder = 600;

  /// R12: consecutive steps without state growth before a nudge / a finish.
  static const int _stallNudge = 4;
  static const int _stallFinish = 8;

  /// Intents that are deterministic lookups: re-running one with identical
  /// arguments can only return what the state already holds.
  static const Set<String> _dedupActions = {
    'SEARCH',
    'FIND',
    'COVER',
    'MAP',
    'COLLECT',
    'READ',
    'SUMMARIZE',
  };

  /// R11.2: consecutive EMPTY responses before the run is finished from
  /// state (empty output is not a malformed intent).
  static const int _maxEmptyResponses = 3;

  static const String intentFormat = '''
你是剧情问答的检索决策器。每次只输出一行意图命令，严格按以下格式，不要任何其他文字：

COVER <名字|entity_id> [scope=<scope_id>]
FIND <短语或空格分隔的词> [scope=<scope_id>] [top_k]
READ <story_id> [start_line end_line] [max_lines] [page_token]
SEARCH <query> [id=<entity_id>] [top_k]
MAP <scope_id>
COLLECT <entity_id> [scope_ids=[a,b]] [terms=[c,d]] [page_token]
SUMMARIZE <story_id> [start_line end_line]
RESELECT <entity_id>
ANSWER [confidence]
DONE

规则：
- 一次只输出一行，无前后缀。
- 找剧情：COVER 列出某人物/实体在哪些章节、哪些行出场；FIND 在剧情原文
  中检索短语（事件、地点、物品、台词关键词），返回章节与行号线索。
- READ 精读章节行区间：只有 READ 读到的原文才会记为证据笔记。
- SEARCH 只查实体档案/资料（干员档案、敌人图鉴等），不检索剧情原文。
- MAP 查看章节地图；COLLECT 列出某实体的全部出场行（terms 填相关词，命中的排前面）。
- 已读区间、已检索与证据笔记记录在状态中，同样的命令不会重复执行。
- 目标实体已在状态中消歧时直接用其 entity_id；消歧结果不对时用 RESELECT 切换候选。
- 证据足以回答时输出 ANSWER（可附 0-1 置信度），系统会据此写答案。
''';

  /// Runs the planner loop, yielding streamed [ReActEvent]s compatible with
  /// the existing chat UI.
  Stream<ReActEvent> run({
    required String systemPrompt,
    required List<Message> chatHistory,
    required String userQuery,
    AnswerStyle style = AnswerStyle.answer,
    void Function(int iteration, String rawResponse)? onRawLlmResponse,
    void Function(String state)? onStateChanged,
  }) async* {
    final state = InvestigationState();
    // R12: the lines READ actually returned, for the writer.
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

    Stream<ReActEvent> finish(StoryAnswerStatus status, {String? confidence}) =>
        _finish(
          status: status,
          confidence: confidence,
          style: style,
          state: state,
          readPages: readPages,
          userQuery: userQuery,
          chatHistory: chatHistory,
        );

    // R12 cost control: only the latest observation is sent in full; older
    // window entries are clipped (read text already lives in the notebook,
    // searches in the search log).
    List<Message> buildRequest() => [
          Message.system('$systemPrompt\n\n$intentFormat'),
          ...chatHistory,
          Message.user(
            '目标: $userQuery\n\n当前状态:\n${state.serialize()}',
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
        yield* finish(StoryAnswerStatus.partial);
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
        // R11.2: an EMPTY response means the model has nothing to say; it is
        // not a malformed intent. Retry a bounded number of times, then
        // answer from what was read. Actual garbage text counts as malformed.
        if (response.isEmpty) {
          emptyResponses++;
          if (emptyResponses >= _maxEmptyResponses) {
            yield* finish(StoryAnswerStatus.partial);
            return;
          }
          recent.add(Message.user(
            'Observation: 收到空输出。请输出下一条意图；证据已够时输出 ANSWER。',
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
          '(COVER/FIND/READ/SEARCH/MAP/COLLECT/SUMMARIZE/RESELECT/ANSWER/DONE)。',
        ),);
        continue;
      }
      malformed = 0;
      emptyResponses = 0;

      // ANSWER and DONE both hand over to the writer (DONE used to end the
      // run without any answer when the model skipped the verdict line).
      if (intent.action == 'ANSWER' || intent.action == 'DONE') {
        if (completedToolCalls < _minimumToolCalls) {
          recent.add(Message.user(
            'Observation: 工具调用不足 $_minimumToolCalls 次，请先检索并阅读原文。',
          ),);
          continue;
        }
        yield* finish(
          StoryAnswerStatus.answered,
          confidence: intent.args['confidence'] as String?,
        );
        return;
      }

      if (intent.action == 'RESELECT') {
        final id = '${intent.args['entity_id'] ?? ''}';
        if (id.isEmpty) {
          recent.add(Message.user('Observation: RESELECT 缺 entity_id。'));
          continue;
        }
        final target = _resolveEntityId(id, state);
        final name = state.candidateName(target) ?? target;
        if (state.wasAttempted(target)) {
          recent.add(Message.user(
            'Observation: 候选 $target（$name）本次已尝试过，'
            '请从 ${state.candidateIds(excluding: target).join(", ")} 中选择'
            '尚未尝试的候选。',
          ),);
          continue;
        }
        state.setTargetEntity(target, name);
        state.noteSearchedName(target, target);
        recent.add(Message.user(
          'Observation: 已切换到候选 $target（$name）。'
          '后续 SEARCH/COVER/COLLECT 直接用该 entity_id。',
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
      final args = Map<String, dynamic>.from(intent.args);

      // R11: an already-disambiguated name is searched by its resolved id
      // instead of re-entering the ambiguity branch.
      if (intent.action == 'SEARCH' && args['entity_id'] is! String) {
        final resolved = state.searchedNameTarget('${args['query'] ?? ''}');
        if (resolved != null) args['entity_id'] = resolved;
      }

      // ── R12 progress control ────────────────────────────────────────
      // Measured at the start of each tool step against the state after the
      // previous one, so every path (including early `continue`s) counts.
      toolSteps++;
      final fingerprint = state.progressFingerprint;
      stalled = fingerprint == lastFingerprint ? stalled + 1 : 0;
      lastFingerprint = fingerprint;
      if (toolSteps > _maxToolSteps || stalled >= _stallFinish) {
        yield* finish(StoryAnswerStatus.partial);
        return;
      }
      if (stalled == _stallNudge) {
        recent.add(Message.user(
          'Observation: 最近 $_stallNudge 步没有获得新信息。请 READ 尚未读过的'
          '章节、换一个检索方向，或基于证据笔记输出 ANSWER。',
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
              : '该命令在第 $previous 步已执行过，结果已记录在状态'
                  '（已检索/已读/证据笔记）中。';
          recent.add(Message.user(
            'Observation: $note请换关键词、READ 未读的章节，或输出 ANSWER。',
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
      // R10/R11: an ambiguous SEARCH is resolved by the disambiguation helper
      // (semantic fit with the question, falling back to the top candidate),
      // so the model never loops on the same ambiguous name.
      if (intent.action == 'SEARCH' && observation.contains('Ambiguous')) {
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
              '后续请直接用该 entity_id；若选择不对，可用 RESELECT 切换其他候选。';
        }
      }
      _updateState(state, intent.action, args, observation);
      if (intent.action == 'FIND' || intent.action == 'COVER') {
        state.noteSearchLog(
          _searchLogKey(intent.action, args),
          _storyIdsIn(observation),
          leads: _storyIdsIn(observation, literalOnly: true),
        );
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
      // 2-message recent window and reaches the writer.
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
        'COLLECT' => 'collect_entity_evidence',
        'SUMMARIZE' => 'read_story_lines',
        _ => '',
      };

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
  /// [literalOnly] skips stories FIND marked as semantic-only neighbours.
  static List<String> _storyIdsIn(
    String observation, {
    int limit = 5,
    bool literalOnly = false,
  }) {
    final ids = <String>[];
    for (final match
        in RegExp(r'^Story: (\S+)(.*)$', multiLine: true).allMatches(observation)) {
      if (literalOnly && match.group(2)!.contains('仅语义相近')) continue;
      final id = match.group(1)!;
      if (!ids.contains(id)) ids.add(id);
      if (ids.length >= limit) break;
    }
    return ids;
  }

  /// Extracts candidate entities from a compact "Ambiguous" observation
  /// (`  1. id | name | type | source | match_type | conf`). R12: the
  /// type/source/match columns are kept for the disambiguation helper.
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
    final resolved = [
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

  /// Id resolution for RESELECT: prefers a candidate from the last
  /// disambiguation list (also by id suffix); otherwise the raw id.
  String _resolveEntityId(String raw, InvestigationState state) {
    final value = raw.trim();
    for (final id in state.candidateIds()) {
      if (id == value || id.endsWith(':$value')) return id;
    }
    return value;
  }

  /// Writer role + provenance (R12/R13): composes the answer in [style] from
  /// the notebook and read lines, checks every cited line was actually read
  /// (one corrective rewrite, then a source warning), prefixes the
  /// code-decided envelope, emits it and completes.
  Stream<ReActEvent> _finish({
    required StoryAnswerStatus status,
    required String? confidence,
    required AnswerStyle style,
    required InvestigationState state,
    required List<ReadPage> readPages,
    required String userQuery,
    required List<Message> chatHistory,
  }) async* {
    // Nothing read means nothing can be cited, whatever the planner thought.
    final nothingRead = readPages.isEmpty && state.notes.isEmpty;
    final finalStatus = nothingRead ? StoryAnswerStatus.notCovered : status;
    String body;
    try {
      body = await _composeAnswer(
        status: finalStatus,
        style: style,
        state: state,
        readPages: readPages,
        userQuery: userQuery,
        chatHistory: chatHistory,
      );
      var invalid = unreadCitations(body, state);
      if (invalid.isNotEmpty) {
        body = await _composeAnswer(
          status: finalStatus,
          style: style,
          state: state,
          readPages: readPages,
          userQuery: userQuery,
          chatHistory: chatHistory,
          invalidCitations: invalid,
        );
        invalid = unreadCitations(body, state);
      }
      if (style == AnswerStyle.factCheck) {
        body = normalizeFactCheckBody(
          body,
          nothingRead: nothingRead,
          hasValidCitation: citationCount(body) > invalid.length,
        );
      }
      if (invalid.isNotEmpty) {
        body = '$body\n\n> 来源警告：以下引用的行未实际读取，'
            '可能不准确：${invalid.join('、')}';
      }
    } catch (e) {
      body = '（无法生成答案正文：$e）';
    }
    yield* _emitFinal(
      '${formatStoryAnswerEnvelope(finalStatus, confidence: nothingRead ? '0' : confidence)}\n$body',
    );
    yield const ReActEvent(type: ReActEventType.complete);
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
        // row numbers), not the requested window.
        final page = parseReadObservation(observation);
        if (page == null) return;
        state.noteRead(page.storyId, page.firstLine, page.lastLine);
      case 'MAP':
        final scopeId = '${args['scope_id'] ?? ''}';
        if (scopeId.isNotEmpty) state.noteMapped(scopeId);
      case 'COLLECT':
        final entityId = '${args['entity_id'] ?? ''}';
        final rowsMatch = RegExp(r'evidence_rows[":\s]+(\d+)')
            .firstMatch(observation);
        final rows = int.tryParse(rowsMatch?.group(1) ?? '') ?? 0;
        state.noteEvidence(entityId, evidenceRows: rows, scopes: const []);
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

  /// Writer role: the evidence notebook AND the raw lines READ returned go
  /// to the writer, so the answer rests on original text instead of model
  /// memory; [invalidCitations] drives a corrective rewrite.
  Future<String> _composeAnswer({
    required StoryAnswerStatus status,
    required AnswerStyle style,
    required InvestigationState state,
    required List<ReadPage> readPages,
    required String userQuery,
    required List<Message> chatHistory,
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
    final statusNote = switch (status) {
      StoryAnswerStatus.answered => '',
      StoryAnswerStatus.partial =>
        '\n注意：检索在证据充分之前停止了（预算或无新进展），请明确说明哪些部分'
            '资料不足，不要把不完整的证据说成定论。',
      StoryAnswerStatus.notCovered =>
        '\n注意：本次没有读到任何相关原文。请如实说明知识库未找到相关内容'
            '（可列出检索过的方向），不要回答具体事实。',
    };
    final correction = invalidCitations.isEmpty
        ? ''
        : '\n\n上一版答案引用了未读取的行：${invalidCitations.join('、')}。'
            '请重写，只引用下方“已读原文”中出现的 story_id:行号。';
    final result = await completeWithHeadroom(
      _writerClient,
      [
        Message.system(
          '你是明日方舟剧情资料员。只根据下方“证据笔记”和“已读原文”回答，'
          '引用格式为 story_id:行号（或 story_id:起-止），只能引用已读原文中出现的行。'
          '原文没有覆盖的部分明确写“资料未覆盖”，不得用记忆补充。用 Markdown。\n'
          '${_styleInstructions(style)}$statusNote',
        ),
        ...chatHistory,
        Message.user(
          '问题: $userQuery\n\n检索状态:\n${state.serialize()}'
          '\n\n已读原文:\n${source.isEmpty ? '（无）' : source}$correction',
        ),
      ],
      temperature: 0.2,
      maxTokens: 4096,
      retryPartial: true, // a cut-off answer is not an answer
    );
    return result.content.trim();
  }

  static String _styleInstructions(AnswerStyle style) => switch (style) {
        AnswerStyle.answer => '输出格式：\n'
            '1. 开头一行直接回答问题。\n'
            '2. 然后 2-5 条证据，每条附引用。\n'
            '3. 列出与结论矛盾或削弱结论的原文（如有）。\n'
            '4. 最后一段写置信度（0-1）与可能的替代解读。',
        AnswerStyle.summary => '输出格式（梗概）：\n'
            '1. 概述（1-2 句）。\n'
            '2. 按时间顺序的关键事件，每条附引用。\n'
            '3. 重要节点与关联人物/章节。\n'
            '4. 末尾说明资料覆盖范围（读了哪些章节，哪些未读）。',
        AnswerStyle.factCheck => '输出格式（事实核查）：\n'
            '第一行严格输出 [FACT_CHECK_VERDICT:<supported|refuted|uncertain|unavailable>]。\n'
            '- supported/refuted：已读原文直接支持/否定该说法，且正文必须引用这些行；\n'
            '- uncertain：证据冲突、间接或不完整；\n'
            '- unavailable：没有读到与该说法相关的原文。没检索到不等于反证。\n'
            '然后依次写：核查结论、主张拆解、直接证据（附引用）、间接证据、证据缺失。',
      };
}

/// Normalizes the fact-check verdict line of a writer answer (R13): a
/// definite verdict needs cited, actually-read text. Exposed for tests.
String normalizeFactCheckBody(
  String body, {
  required bool nothingRead,
  required bool hasValidCitation,
}) {
  final marker = RegExp(
    r'\[FACT_CHECK_VERDICT:(supported|refuted|uncertain|unavailable)\]\s*',
    caseSensitive: false,
  );
  final requested = marker.firstMatch(body)?.group(1)?.toLowerCase();
  var verdict = requested ?? 'uncertain';
  if (nothingRead) {
    verdict = 'unavailable';
  } else if ((verdict == 'supported' || verdict == 'refuted') &&
      !hasValidCitation) {
    verdict = 'uncertain';
  }
  return '[FACT_CHECK_VERDICT:$verdict]\n${body.replaceFirst(marker, '').trim()}';
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
