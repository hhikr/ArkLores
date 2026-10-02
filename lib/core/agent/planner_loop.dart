import 'dart:async';

import '../gamedata/gamedata_models.dart';
import '../gamedata/story_catalog.dart';
import '../llm/completion_budget.dart';
import '../llm/llm_client.dart';
import 'entity_disambiguator.dart';
import 'evidence_notebook.dart';
import 'investigation_state.dart';
import 'planner_intent.dart';
import 'react_event.dart' show ReActEvent, ReActEventType;
import 'story_answer.dart';
import 'tools/agent_tool.dart';
import 'tools/observation_data.dart';
import 'tools/tool_registry.dart';

/// R14: story id → catalog entry lookup (readable chapter names).
typedef StoryCatalogLookup = Future<Map<String, StoryCatalogEntry>> Function(
  Iterable<String> storyIds,
);

/// R15: names (characters / speakers) and catalog collections / chapters
/// written in a question.
typedef QuestionContextLookup
    = Future<({List<String> names, List<NamedStoryTarget> targets})> Function(
  String question,
);

/// Compacts an OUTLINE observation for the state: one line per chapter
/// (`label | story_id`) followed by its synopsis clipped to
/// [synopsisChars]; DATA block and notes dropped. Exposed for tests.
String compactOutline(String observation, {int synopsisChars = 120}) {
  final out = StringBuffer();
  final lines = observation.split('\n');
  for (final raw in lines) {
    final line = raw.trimRight();
    if (line.startsWith('Outline:')) {
      out.writeln('  ${line.substring('Outline:'.length).trim()}');
      continue;
    }
    final row = RegExp(r'^(\d+)\. (.+?) \| (\S+) \|').firstMatch(line);
    if (row != null) {
      out.writeln('   ${row.group(1)}. ${row.group(2)} | ${row.group(3)}'
          '${line.contains('← 当前章') ? ' ←' : ''}');
      continue;
    }
    final synopsis = RegExp(r'^\s+梗概: (.*)$').firstMatch(line);
    if (synopsis != null) {
      final text = synopsis.group(1)!.replaceAll('…', '');
      out.writeln('      ${text.length > synopsisChars ? '${text.substring(0, synopsisChars)}…' : text}');
    }
  }
  return out.toString().trimRight();
}

/// Why the planner handed over to the writer (R16). Only [answer] is the
/// planner saying the evidence is enough; the others are limits. None of
/// them decides the status on its own when the writer reports coverage.
enum StopReason {
  answer,
  budget,
  stalled,
  onlyRereads,
  repeatedSearches,
  emptyReplies,
  safetyCap;

  /// Status when the writer gives no coverage line.
  StoryAnswerStatus get fallbackStatus => this == answer || this == onlyRereads
      ? StoryAnswerStatus.answered
      : StoryAnswerStatus.partial;

  /// What the writer is told about the stop: neutral — a limit says nothing
  /// about whether the text read so far answers the question.
  String get writerNote => switch (this) {
        answer || onlyRereads => '',
        budget => '\n说明：检索因步数上限结束，这本身不代表证据不足。已读原文足以回答'
            '问题核心时正常作答；只把确实缺少原文的部分写成“资料未覆盖”。',
        _ => '\n说明：检索在没有新发现时结束，这本身不代表证据不足。已读原文足以'
            '回答问题核心时正常作答；只把确实缺少原文的部分写成“资料未覆盖”。',
      };
}

/// The writer's own judgement of the read text (R16).
enum StoryCoverage { full, gaps }

/// Asks the writer for its coverage line (stripped from the answer).
const String coverageInstruction =
    '最后单独一行输出 [COVERAGE: full] 或 [COVERAGE: gaps]：已读原文回答了问题的'
    '核心就写 full；问题的核心部分缺少原文证据才写 gaps（次要细节缺失不算）。';

final RegExp _coverageLine = RegExp(
    r'\n?[ \t>*_`]*\[COVERAGE:\s*(full|gaps)\s*\][ \t*_`]*',
    caseSensitive: false,);

/// Splits the `[COVERAGE: …]` line off a writer answer; exposed for tests.
({String body, StoryCoverage? coverage}) splitCoverage(String answer) {
  StoryCoverage? coverage;
  final body = answer.replaceAllMapped(_coverageLine, (m) {
    coverage = m.group(1)!.toLowerCase() == 'full'
        ? StoryCoverage.full
        : StoryCoverage.gaps;
    return '';
  });
  return (body: body.trim(), coverage: coverage);
}

/// Final status of a run (R16): nothing read → not covered; otherwise the
/// writer's coverage; [stop] only when the writer gave none.
StoryAnswerStatus answerStatus({
  required bool nothingRead,
  required StoryCoverage? coverage,
  required StopReason stop,
}) {
  if (nothingRead) return StoryAnswerStatus.notCovered;
  return switch (coverage) {
    StoryCoverage.full => StoryAnswerStatus.answered,
    StoryCoverage.gaps => StoryAnswerStatus.partial,
    null => stop.fallbackStatus,
  };
}

/// Upper bound of raw read text handed to the writer (R16: 60000; R14 had
/// 30000 filled in reading order, which cut the chapters read last).
const int maxWriterSourceChars = 60000;

/// Lines around a noted line that go to the writer first.
const int _noteContext = 5;

/// The read text for the writer (R16), within [maxChars]: first the noted
/// lines of every chapter with [_noteContext] lines around them, then the
/// rest of every chapter in turns of [_fillChunk] lines — so a chapter read
/// late is never cut whole. Output keeps chapter order and line order;
/// skipped stretches show as `…`. Exposed for tests.
String buildWriterSource(
  List<ReadPage> pages,
  InvestigationState state, {
  int maxChars = maxWriterSourceChars,
}) {
  final chapters = <String, Map<int, String>>{};
  for (final page in pages) {
    final rows = chapters.putIfAbsent(page.storyId, () => {});
    for (final line in page.lines) {
      rows.putIfAbsent(line.index, () => line.text);
    }
  }
  if (chapters.isEmpty) return '';
  String row(String id, int i) => '$id:$i ${chapters[id]![i]}\n';
  String header(String id) {
    final label = state.storyEntries[id]?.label;
    return label == null ? '' : '〔$id = $label〕\n';
  }

  final chosen = {for (final id in chapters.keys) id: <int>{}};
  var used = 0;
  for (final id in chapters.keys) {
    used += header(id).length;
  }
  bool take(String id, int i) {
    if (chosen[id]!.contains(i) || !chapters[id]!.containsKey(i)) return true;
    final cost = row(id, i).length;
    if (used + cost > maxChars) return false;
    used += cost;
    chosen[id]!.add(i);
    return true;
  }

  // Pass 1: noted lines with context, newest notes first.
  var full = false;
  for (final note in state.notes.reversed) {
    if (!chapters.containsKey(note.storyId)) continue;
    for (var i = note.line - _noteContext; i <= note.line + _noteContext; i++) {
      if (!take(note.storyId, i)) {
        full = true;
        break;
      }
    }
    if (full) break;
  }
  // Pass 2: the rest, chapter by chapter in turns.
  final orders = {
    for (final e in chapters.entries) e.key: (e.value.keys.toList()..sort()),
  };
  final cursor = {for (final id in chapters.keys) id: 0};
  while (!full) {
    var progressed = false;
    for (final id in chapters.keys) {
      final order = orders[id]!;
      var taken = 0;
      while (cursor[id]! < order.length && taken < _fillChunk) {
        final i = order[cursor[id]!];
        if (!chosen[id]!.contains(i)) {
          if (!take(id, i)) {
            full = true;
            break;
          }
          taken++;
        }
        cursor[id] = cursor[id]! + 1;
        progressed = true;
      }
      if (full) break;
    }
    if (!progressed) break;
  }

  final out = StringBuffer();
  for (final id in chapters.keys) {
    final lines = chosen[id]!.toList()..sort();
    if (lines.isEmpty) continue;
    out.write(header(id));
    final all = orders[id]!;
    var previous = -1;
    for (final i in lines) {
      final position = all.indexOf(i);
      if (previous >= 0 && position > previous + 1) out.write('…\n');
      if (previous < 0 && position > 0) out.write('…\n');
      out.write(row(id, i));
      previous = position;
    }
    if (previous < all.length - 1) out.write('…\n');
  }
  return out.toString();
}

const int _fillChunk = 20;

/// Streamed answer text of one writer call.
class _AnswerBuffer {
  final StringBuffer _text = StringBuffer();
  bool get isEmpty => _text.isEmpty;
  void write(String text) => _text.write(text);
  String get text => _text.toString().trim();
}

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
    StoryCatalogLookup? storyCatalogLookup,
    QuestionContextLookup? questionContextLookup,
  })  : _maxToolSteps = maxToolSteps,
        _storyCatalogLookup = storyCatalogLookup,
        _questionContextLookup = questionContextLookup,
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

  /// R14: resolves story ids to catalog entries (readable chapter names) for
  /// the state the planner and the writer see; null leaves raw ids.
  final StoryCatalogLookup? _storyCatalogLookup;

  /// R15: names / collections in the question (null: none detected).
  final QuestionContextLookup? _questionContextLookup;

  Future<({List<String> names, List<NamedStoryTarget> targets})>
      _questionContext(String question) async {
    final lookup = _questionContextLookup;
    if (lookup == null) {
      return (names: <String>[], targets: <NamedStoryTarget>[]);
    }
    try {
      return await lookup(question);
    } catch (_) {
      // A hint only; the run works without it.
      return (names: <String>[], targets: <NamedStoryTarget>[]);
    }
  }

  /// R15: people of the question whose COVER overview goes into state.
  static const int _maxOverviewNames = 2;
  static const int _maxOverviewRows = 15;

  /// Overview lines of a COVER for [name] (`出场总览…` up to the details), or
  /// null when the tool is not registered or finds nothing.
  Future<String?> _coverageOverview(String name) async {
    final tool = _toolRegistry.getTool('search_story_coverage');
    if (tool == null) return null;
    try {
      final result = await tool.execute({'query': name});
      final text = result is ToolExecutionResult ? result.observation : '$result';
      final start = text.indexOf('出场总览');
      if (start < 0) return null;
      final end = text.indexOf('出场明细', start);
      final lines = text
          .substring(start, end < 0 ? text.length : end)
          .trimRight()
          .split('\n');
      final rows = lines.skip(1).toList();
      if (rows.length <= _maxOverviewRows) return lines.join('\n');
      // Keep the collections with the most mentions, still in release
      // order, so a frequent name does not flood the state.
      int mentions(String row) =>
          int.tryParse(RegExp(r'提及 (\d+) 次').firstMatch(row)?.group(1) ?? '') ??
          0;
      final keep = ([...rows]..sort((a, b) => mentions(b).compareTo(mentions(a))))
          .take(_maxOverviewRows)
          .toSet();
      return [
        lines.first,
        for (final row in rows)
          if (keep.contains(row)) row,
        '  （另有 ${rows.length - _maxOverviewRows} 个提及较少的故事集未列出）',
      ].join('\n');
    } catch (_) {
      return null;
    }
  }

  /// R12: older recent-window messages are clipped to this many characters.
  static const int _clipOlder = 600;

  /// R12: consecutive steps without state growth before a nudge / a finish.
  static const int _stallNudge = 4;
  static const int _stallFinish = 8;

  /// R14: consecutive commands blocked as duplicates before the run is
  /// written up from what it gathered.
  static const int _maxConsecutiveDuplicates = 3;

  /// Intents that are deterministic lookups: re-running one with identical
  /// arguments can only return what the state already holds.
  static const Set<String> _dedupActions = {
    'SEARCH',
    'FIND',
    'COVER',
    'MAP',
    'OUTLINE',
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
OUTLINE <故事集名|scope_id|story_id>
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
  中检索词语（人物、动作、地点、物品、台词里会出现的词），返回章节与行号线索；
  各词分别匹配，同时命中多个词的行排在前面。
- OUTLINE 列出一个故事集（活动/主线章节/干员密录）全部章节的名称、顺序和官方
  梗概，用来把握整个故事的前因后果、决定读哪些章节。
- READ 精读章节行区间：只有 READ 读到的原文才会记为证据笔记。
- SEARCH 只查实体档案/资料（干员档案、敌人图鉴等），不检索剧情原文。
- MAP 查看章节地图；COLLECT 列出某实体的全部出场行（terms 填相关词，命中的排前面）。
- 已读章节（区间、摘要、证据笔记）与已检索记录在状态中，同样的命令不会重复执行。
- 可以在意图后加“# 简短计划”，如 READ <story_id> 0 200 # 接着读下一章；
  系统把它记为状态里的“当前计划”，下一步可以接着做。
- 状态里的“步数”是检索预算；快用完时先 READ 最关键的未读章节，再 ANSWER。
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
    List<ReadPage> priorPages = const [],
    void Function(int iteration, String rawResponse)? onRawLlmResponse,
    void Function(String state)? onStateChanged,
  }) async* {
    final state = InvestigationState()..stepBudget = _maxToolSteps;
    // R12: the lines READ actually returned, for the writer.
    final readPages = <ReadPage>[];
    final previousQuestions = [
      for (final m in chatHistory)
        if (m.role == MessageRole.user) m.content,
    ];
    final previousAnswers = [
      for (final m in chatHistory)
        if (m.role == MessageRole.assistant) m.content,
    ];
    // R15: names and collections the question brings up. A question that
    // names someone or some story the previous turn never mentioned starts
    // a new topic: the previous turn's pages would only anchor the search
    // where the last answer was.
    final context = await _questionContext(userQuery);
    state.namedTargets.addAll(context.targets);
    final previousTurn = previousQuestions.isEmpty
        ? ''
        : '${previousQuestions.last}\n'
            '${previousAnswers.isEmpty ? '' : previousAnswers.last}';
    final newNames = [
      for (final name in [
        ...context.names,
        for (final t in context.targets) t.name,
      ])
        if (!previousTurn.contains(name)) name,
    ];
    final followUp = previousQuestions.isNotEmpty && newNames.isEmpty;
    // R15: every collection the people in the question appear in, in
    // release order, stays in state from the first step — a planner that
    // only sees the chapters it already read (or the previous answer's
    // story) cannot know the person also appears elsewhere.
    for (final name in context.names.take(_maxOverviewNames)) {
      final overview = await _coverageOverview(name);
      if (overview != null) state.entityOverviews[name] = overview;
    }
    if (previousQuestions.isNotEmpty && !followUp) {
      state.newTopicNames.addAll(newNames.toSet());
    }
    // R14: a follow-up question inherits the original text the previous turn
    // read: it counts as read (no re-reading, citable) and reaches the
    // writer after this turn's own pages.
    final inheritedPages = followUp ? priorPages : const <ReadPage>[];
    for (final page in inheritedPages) {
      state.noteRead(page.storyId, page.firstLine, page.lastLine);
    }
    state.priorReadStories.addAll(inheritedPages.map((p) => p.storyId));
    await _refreshLabels(state);
    // R14: the extractor sees no chat history; a follow-up ("那根本原因
    // 呢？") is only meaningful with the previous question attached.
    final extractorQuery = followUp
        ? '$userQuery（承接上一问：${previousQuestions.last}）'
        : userQuery;
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
    final outlineCache = <String, String>{};
    // R16: already-read ranges shown again once (signature of the request).
    final reshown = <String>{};
    var duplicates = 0;
    var onlyRereads = true;

    Stream<ReActEvent> finish(StopReason stop, {String? confidence}) => _finish(
          stop: stop,
          confidence: confidence,
          style: style,
          state: state,
          readPages: [...readPages, ...inheritedPages],
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
        yield* finish(StopReason.safetyCap);
        return;
      }

      ChatCompletionResult completion;
      try {
        // R12: a reasoning model may spend the whole ceiling on hidden
        // reasoning and return empty content; retry with headroom before
        // treating the reply as empty.
        state.stepsUsed = toolSteps;
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
      final raw = completion.content.trim();
      onRawLlmResponse?.call(iteration, raw);
      // R16: `<intent> # <plan>` — the plan note is kept in state for
      // continuity and never takes part in any decision.
      final split = splitPlanNote(raw);
      final response = split.intent;
      if (split.plan.isNotEmpty) state.plan = split.plan;

      final intent = parseIntent(response);
      if (intent == null) {
        // R11.2: an EMPTY response means the model has nothing to say; it is
        // not a malformed intent. Retry a bounded number of times, then
        // answer from what was read. Actual garbage text counts as malformed.
        if (response.isEmpty) {
          emptyResponses++;
          if (emptyResponses >= _maxEmptyResponses) {
            yield* finish(StopReason.emptyReplies);
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
          '(COVER/FIND/OUTLINE/READ/SEARCH/MAP/COLLECT/SUMMARIZE/RESELECT/ANSWER/DONE)。',
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
          StopReason.answer,
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
        yield* finish(
          toolSteps > _maxToolSteps ? StopReason.budget : StopReason.stalled,
        );
        return;
      }
      if (stalled == _stallNudge) {
        recent.add(Message.user(
          'Observation: 最近 $_stallNudge 步没有获得新信息。请 READ 尚未读过的'
          '章节、换一个检索方向，或基于证据笔记输出 ANSWER。',
        ),);
      }

      // R14: a READ that starts inside already-read lines continues at the
      // first unread line (live runs re-read 30-line windows of the same
      // chapter many times over).
      var advanced = false;
      if ((intent.action == 'READ' || intent.action == 'SUMMARIZE') &&
          args['page_token'] == null) {
        final storyId = '${args['story_id'] ?? ''}';
        final start = (args['start_line'] as num?)?.toInt() ?? 0;
        final end = (args['end_line'] as num?)?.toInt();
        final unread = state.firstUnreadLine(storyId, start);
        if (unread > start && (end == null || unread <= end)) {
          args['start_line'] = unread;
          advanced = true;
        }
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
        // R15: a search made only of spellings the DB is known not to
        // contain cannot find anything, whatever scope or top_k it uses.
        final searchTerms = intent.action == 'FIND' || intent.action == 'COVER'
            ? '${args['query'] ?? ''}'
                .split(RegExp(r'\s+'))
                .where((t) => t.isNotEmpty)
                .toList()
            : const <String>[];
        final missingOnly = searchTerms.isNotEmpty &&
            searchTerms.every(state.missingTerms.containsKey);
        // R15: an outline asked for again is served from cache (the state
        // keeps only a clipped copy). It costs a tool step but is not a
        // stall: live runs re-opened the outline between reads to pick the
        // next chapter, and blocking it ended the run early.
        final cachedOutline = outlineCache[signature];
        if (cachedOutline != null) {
          final cachedData = parseDataBlocks(cachedOutline)
              .where((d) => d['type'] == 'get_story_outline')
              .firstOrNull;
          final inState = state.outlines
              .containsKey('${cachedData?['collection_id'] ?? ''}');
          recent.add(Message.user(
            inState
                ? 'Observation: 这个故事集的梗概第 $previous 步已获取，完整列在状态'
                    '“已看梗概”里，不必再 OUTLINE：从中挑还没读的章节 READ。'
                : 'Observation: （与第 $previous 步相同的梗概）\n$cachedOutline',
          ),);
          if (recent.length > 2) recent.removeAt(0);
          yield ReActEvent(
            type: ReActEventType.toolObservation,
            content: cachedOutline,
            toolName: toolName,
          );
          continue;
        }
        final isReread =
            (intent.action == 'READ' || intent.action == 'SUMMARIZE') &&
                (previous != null || rangeRead);
        // R16: a planner asking for lines it already read wants to look at
        // them again (it only keeps digests and notes); refusing made it
        // ask up to 15 times. The text is shown again once, from the pages
        // in hand, at the cost of a tool step.
        // A planner that keeps asking for text it has (live: 9 of 21 steps
        // after the first re-show) is done reading — the same as ANSWER;
        // the writer sees all of it and says whether it covers the question.
        if (isReread && reshown.length >= _maxReshows && readPages.isNotEmpty) {
          yield* finish(StopReason.onlyRereads);
          return;
        }
        if (isReread && reshown.add('$storyId ${start ?? 0}-${end ?? ''}')) {
          final text = _rereadText(
            [...inheritedPages, ...readPages],
            storyId,
            start ?? 0,
            end,
          );
          if (text.isNotEmpty) {
            final shown = '（这段原文之前已读过，再给你看一次；之后不再重复提供，'
                '写答案时也会完整使用）\n$text';
            recent.add(Message.user('Observation: $shown'));
            if (recent.length > 2) recent.removeAt(0);
            yield ReActEvent(
              type: ReActEventType.toolObservation,
              content: shown,
              toolName: toolName,
            );
            continue;
          }
        }
        if (previous != null || rangeRead || missingOnly) {
          // R14: nothing ran, so the tool budget is not spent; but a planner
          // that only repeats itself has nothing left to look up — finish.
          toolSteps--;
          duplicates++;
          final isRead =
              intent.action == 'READ' || intent.action == 'SUMMARIZE';
          if (!isRead) onlyRereads = false;
          if (duplicates >= _maxConsecutiveDuplicates) {
            // Asking only to re-read text it already has means the planner
            // has nothing new to read — the same as ANSWER. Repeating a
            // search means it is still looking but stuck — a stall.
            yield* finish(
              onlyRereads && readPages.isNotEmpty
                  ? StopReason.onlyRereads
                  : StopReason.repeatedSearches,
            );
            return;
          }
          final note = isReread
              ? 'READ $storyId 这一段已经给你看过（读取和重看各一次）：已读原文会完整'
                  '交给写答案的环节，不必再看。'
              : missingOnly && previous == null
                  ? '库中没有“${searchTerms.join(' ')}”这个写法（之前的检索已确认），'
                      '换范围或数量也不会有结果；看状态里列出的相近名字。'
                  : '该命令在第 $previous 步已执行过，结果已记录在状态'
                      '（已检索/已读/证据笔记）中。';
          recent.add(Message.user(
            'Observation: $note如果还有没读过、与问题相关的章节（看“已看梗概”），'
            '就 READ 它；如果没有新的方向，现在就输出 ANSWER。',
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
      duplicates = 0;
      onlyRereads = true;

      yield ReActEvent(
        type: ReActEventType.status,
        content: '第 $toolSteps 步 · ${_stepLabel(intent.action, args, state)}',
      );
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
      // R16: continuing past the read lines found nothing — the chapter was
      // read to its end. Said plainly: the raw "No lines" read like a failed
      // READ and the planner asked again (live).
      if (advanced && observation.startsWith('No lines in the requested range')) {
        final storyId = '${args['story_id'] ?? ''}';
        observation = '$storyId 已经读到结尾（已读 ${state.segmentsText(storyId)}），'
            '没有更多行。这一章的摘要和笔记在状态“已读章节”里。';
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
      if (intent.action == 'OUTLINE' && !observation.startsWith('Error')) {
        outlineCache['${intent.action} ${_canonicalArgs(args)}'] = observation;
      }
      _updateState(state, intent.action, args, observation);
      if (intent.action == 'FIND' || intent.action == 'COVER') {
        state.noteMissingTerms(observation);
        state.noteSearchLog(
          _searchLogKey(intent.action, args),
          _storyIdsIn(observation),
          leads: _storyIdsIn(observation, literalOnly: true),
        );
      }
      await _refreshLabels(state);
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
          final digest = await digestReadPage(
            extractor,
            userQuery: extractorQuery,
            page: page,
            // R14: pages are up to ~150 lines now.
            maxNotes: 10,
          );
          state
            ..noteDigest(page.storyId, digest.digest)
            ..addNotes(digest.notes);
          onStateChanged?.call(state.serialize());
        }
      }
    }
  }

  /// R16: the lines of [storyId] in [start]..[end] from pages already in
  /// hand (`N | text` rows, at most [_maxRereadLines]); '' when none.
  static String _rereadText(
    List<ReadPage> pages,
    String storyId,
    int start,
    int? end,
  ) {
    final rows = <int, String>{};
    for (final page in pages) {
      if (page.storyId != storyId) continue;
      for (final line in page.lines) {
        if (line.index < start || (end != null && line.index > end)) continue;
        rows[line.index] = line.text;
      }
    }
    if (rows.isEmpty) return '';
    final indexes = rows.keys.toList()..sort();
    return [
      'Story: $storyId',
      for (final i in indexes.take(_maxRereadLines)) '$i | ${rows[i]}',
      if (indexes.length > _maxRereadLines)
        '…（其余 ${indexes.length - _maxRereadLines} 行略）',
    ].join('\n');
  }

  static const int _maxRereadLines = 200;

  /// R16: already-read passages shown again per run; asking for more ends
  /// the search (see the re-read branch in [run]).
  static const int _maxReshows = 2;

  /// Short description of a step for the live status line (R16).
  String _stepLabel(
    String action,
    Map<String, dynamic> args,
    InvestigationState state,
  ) {
    String story(String id) => state.storyEntries[id]?.label ?? id;
    final query = '${args['query'] ?? args['entity_id'] ?? ''}';
    final storyId = '${args['story_id'] ?? ''}';
    final scope = '${args['scope_id'] ?? args['target'] ?? ''}';
    return switch (action) {
      'READ' || 'SUMMARIZE' => '阅读 ${story(storyId)}',
      'FIND' => '搜索原文“$query”',
      'COVER' => '查出场 $query',
      'SEARCH' => '查档案 $query',
      'OUTLINE' => '看梗概 ${scope.isEmpty ? query : scope}',
      'MAP' => '查章节地图 $scope',
      'COLLECT' => '汇总出场 $query',
      _ => action,
    };
  }

  /// R14: labels the story ids that entered the state since the last step.
  Future<void> _refreshLabels(InvestigationState state) async {
    final lookup = _storyCatalogLookup;
    if (lookup == null) return;
    final ids = state.storyIdsWithoutLabel;
    if (ids.isEmpty) return;
    try {
      state.addStoryEntries(ids, await lookup(ids));
    } catch (_) {
      // Labels are a convenience; raw ids still work.
    }
  }

  String _toolNameFor(String action) => switch (action) {
        'READ' => 'read_story_lines',
        'SEARCH' => 'search_local_lore',
        'COVER' => 'search_story_coverage',
        'FIND' => 'search_story_lines',
        'MAP' => 'get_story_map',
        'OUTLINE' => 'get_story_outline',
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

  /// Writer role + provenance (R12/R13/R16): streams the answer in [style]
  /// from the notebook and read lines, checks every cited line was actually
  /// read (one corrective rewrite, streamed again, then a source warning),
  /// and replaces the streamed text with the checked answer under the
  /// status envelope.
  ///
  /// R16: the status follows the evidence, not why the search stopped: the
  /// writer says whether the read text covers the core of the question
  /// (`[COVERAGE: …]`); [stop] only decides when that line is missing.
  Stream<ReActEvent> _finish({
    required StopReason stop,
    required String? confidence,
    required AnswerStyle style,
    required InvestigationState state,
    required List<ReadPage> readPages,
    required String userQuery,
    required List<Message> chatHistory,
  }) async* {
    // Nothing read means nothing can be cited, whatever the planner thought.
    final nothingRead = readPages.isEmpty && state.notes.isEmpty;
    yield const ReActEvent(type: ReActEventType.status, content: '正在撰写答案');
    String body;
    StoryCoverage? coverage;
    try {
      final draft = _AnswerBuffer();
      yield* _streamAnswer(
        draft,
        stop: stop,
        nothingRead: nothingRead,
        style: style,
        state: state,
        readPages: readPages,
        userQuery: userQuery,
        chatHistory: chatHistory,
      );
      body = draft.text;
      var invalid = unreadCitations(body, state);
      if (invalid.isNotEmpty) {
        yield ReActEvent(
          type: ReActEventType.finalAnswerReset,
          content: '正在修正引用：${invalid.length} 处引用的行没有读过',
        );
        final rewrite = _AnswerBuffer();
        yield* _streamAnswer(
          rewrite,
          stop: stop,
          nothingRead: nothingRead,
          style: style,
          state: state,
          readPages: readPages,
          userQuery: userQuery,
          chatHistory: chatHistory,
          invalidCitations: invalid,
        );
        body = rewrite.text;
        invalid = unreadCitations(body, state);
      }
      final parsed = splitCoverage(body);
      body = parsed.body;
      coverage = parsed.coverage;
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
    final status = answerStatus(
      nothingRead: nothingRead,
      coverage: coverage,
      stop: stop,
    );
    yield ReActEvent(
      type: ReActEventType.finalAnswerReplace,
      content:
          '${formatStoryAnswerEnvelope(status, confidence: nothingRead ? '0' : confidence)}\n$body',
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
      case 'OUTLINE':
        final data = parseDataBlocks(observation)
            .where((b) => b['type'] == 'get_story_outline')
            .firstOrNull;
        final collectionId = '${data?['collection_id'] ?? ''}';
        if (collectionId.isNotEmpty) {
          state.noteOutline(collectionId, compactOutline(observation));
        }
      case 'COLLECT':
        final entityId = '${args['entity_id'] ?? ''}';
        final rowsMatch = RegExp(r'evidence_rows[":\s]+(\d+)')
            .firstMatch(observation);
        final rows = int.tryParse(rowsMatch?.group(1) ?? '') ?? 0;
        state.noteEvidence(entityId, evidenceRows: rows, scopes: const []);
    }
  }

  /// Ceiling of one writer call (R16: generous so a streamed answer is not
  /// cut; billing follows the tokens produced).
  static const int _writerMaxTokens = 8192;

  /// Writer role: the evidence notebook AND the raw lines READ returned go
  /// to the writer, so the answer rests on original text instead of model
  /// memory; [invalidCitations] drives a corrective rewrite. R16: streamed
  /// into [out] token by token (hidden reasoning, when the writer thinks,
  /// streams as [ReActEventType.reasoningToken]).
  Stream<ReActEvent> _streamAnswer(
    _AnswerBuffer out, {
    required StopReason stop,
    required bool nothingRead,
    required AnswerStyle style,
    required InvestigationState state,
    required List<ReadPage> readPages,
    required String userQuery,
    required List<Message> chatHistory,
    List<String> invalidCitations = const [],
  }) async* {
    final source = buildWriterSource(readPages, state);
    final stopNote = nothingRead
        ? '\n注意：本次没有读到任何相关原文。请如实说明知识库未找到相关内容'
            '（可列出检索过的方向），不要回答具体事实。'
        : stop.writerNote;
    final correction = invalidCitations.isEmpty
        ? ''
        : '\n\n上一版答案引用了未读取的行：${invalidCitations.join('、')}。'
            '请重写，只引用下方“已读原文”中出现的 story_id:行号。';
    final messages = [
      Message.system(
        '你是明日方舟剧情资料员。只根据下方“证据笔记”和“已读原文”回答，'
        '引用格式为 story_id:行号（或 story_id:起-止），只能引用已读原文中出现的行。'
        '正文提到章节时用读者看得懂的名称（如〔〕中给出的“故事集 关卡号 标签《章名》”），'
        '不要把 story_id 当作章节名写进句子；story_id 只出现在引用里。'
        '“已看梗概”是官方简介，只能帮助理解前后文和事件顺序，不能代替原文作为证据。'
        '回答要考虑整个故事的前因后果，而不只是事件发生的那一幕。'
        '原文没有覆盖的部分明确写“资料未覆盖”，不得用记忆补充。用 Markdown。'
        '问题里的名字若列在检索状态“库中没有的写法”中，而已读原文与问题的其余部分'
        '对得上状态列出的某个相近名字，就按那个名字作答，并在第一句说明按哪个名字理解；'
        '不要只因写法不同就判定资料未覆盖。\n'
        '${_styleInstructions(style)}\n$coverageInstruction$stopNote',
      ),
      ...chatHistory,
      Message.user(
        '问题: $userQuery\n\n检索状态:\n${state.serializeForWriter()}'
        '\n\n已读原文:\n${source.isEmpty ? '（无）' : source}$correction',
      ),
    ];
    var maxTokens = _writerMaxTokens;
    while (true) {
      String? finishReason;
      await for (final delta in _writerClient.streamCompletion(
        messages,
        temperature: 0.2,
        maxTokens: maxTokens,
      )) {
        if (delta.reasoningContent.isNotEmpty) {
          yield ReActEvent(
            type: ReActEventType.reasoningToken,
            content: delta.reasoningContent,
          );
        }
        if (delta.content.isNotEmpty) {
          // Leading whitespace of the reply is dropped, as before.
          final text = out.isEmpty ? delta.content.trimLeft() : delta.content;
          if (text.isNotEmpty) {
            out.write(text);
            yield ReActEvent(
              type: ReActEventType.finalAnswerToken,
              content: text,
            );
          }
        }
        if (delta.done) finishReason = delta.finishReason;
      }
      // Hidden reasoning used the whole ceiling before any answer text:
      // once more with the hard ceiling (completion_budget.dart).
      if (finishReason == 'length' &&
          out.isEmpty &&
          maxTokens < maxCompletionTokens) {
        maxTokens = maxCompletionTokens;
        continue;
      }
      if (finishReason == 'length' && !out.isEmpty) {
        const note = '\n\n> 注意：答案达到长度上限，可能不完整。';
        out.write(note);
        yield const ReActEvent(
          type: ReActEventType.finalAnswerToken,
          content: note,
        );
      }
      return;
    }
  }

  static String _styleInstructions(AnswerStyle style) => switch (style) {
        AnswerStyle.answer => '输出格式：\n'
            '1. 开头一行直接回答问题：给出已读原文最能支持的答案。背景因素、更抽象的'
            '动因放到第 4 条的替代解读里，不要用它们代替对问题本身的回答。\n'
            '2. 然后 2-5 条证据，每条附引用。\n'
            '3. 列出与结论矛盾或削弱结论的原文（如有）。\n'
            '4. 最后一段写置信度（0-1）；有原文依据的替代解读才写，'
            '不要推测原文没有写到的动机或安排。',
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
