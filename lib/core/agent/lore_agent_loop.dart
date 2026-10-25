/// R17: the story agent — one model, general tools, an append-only
/// conversation.
///
/// General agents given only the knowledge DB answered story questions far
/// better than the R13–R16 planner pipeline (`logs/成熟的agent如何处理/`).
/// What they shared, and what this loop keeps:
/// - the model that reads the text writes the answer (no digests, no
///   separate writer choosing excerpts);
/// - expressive tools: one search over every source, read-only SQL over the
///   whole corpus, chapter reads, grep with context (`lore_tools.dart`);
/// - an append-only message list, so providers serve most of each request
///   from their prompt cache;
/// - no hand-written progress rules — only a turn limit, a context budget
///   (oldest tool results folded) and one citation check at the end.
///
/// 0.14 (`notes/ask_0.14_review.md`, kept locally): the question is searched
/// once before the first turn; tool calls pass a gate before they run or
/// enter the conversation; a provider that answers a turn badly is asked
/// again that turn only; the answer is rewritten at most once, and only when
/// a few dropped citations would not do; sub-agents are off unless asked
/// for, and their steps are shown. The digest ([digest]) and the reader's
/// review ([review]) are not part of a question: the app runs them when the
/// player asks for them under a finished answer.
///
/// Every story question takes this same path (R13), with one prompt.
library;

import 'dart:async';
import 'dart:convert';

import '../gamedata/game_retrieval.dart';
import '../gamedata/multi_game_retrieval.dart';
import '../llm/embedding_client.dart';
import '../llm/llm_client.dart';
import '../materials/material_document.dart';
import '../materials/material_snapshot.dart';
import '../wiki/wiki_lookup.dart';
import '../wiki/wiki_page.dart';
import 'coverage.dart';
import 'line_picker.dart';
import 'lore_agent_prompts.dart';
import 'lore_answer_json.dart';
import 'lore_answer_stages.dart';
import 'lore_tools.dart';
import 'react_event.dart';
import 'search_planner.dart';
import 'story_answer.dart';
import 'tool_call_gate.dart';
import 'tools/agent_tool.dart';
import 'tools/search_tool.dart';
import 'tools/wiki_tools.dart';

/// The messages and seen lines of a conversation, carried into follow-up
/// questions so they continue with the text already read.
class LoreConversation {
  LoreConversation({
    List<Message>? messages,
    SeenLines? seen,
    this.question = '',
    this.entries = const [],
  })  : messages = messages ?? [],
        seen = seen ?? SeenLines();

  /// The entries of the last answer with the citations that passed the
  /// check (what "提要" reorganises); empty when it was not a JSON answer.
  final List<LoreAnswerEntry> entries;

  /// Everything after the system prompt: questions, tool calls, tool
  /// results and answers.
  final List<Message> messages;
  final SeenLines seen;

  /// The last question as the user wrote it (0.14: a follow-up's search
  /// before the first turn includes it).
  final String question;
}

/// `story_id:12` or `story_id:12-40` (story ids end in .txt).
final RegExp _citation =
    RegExp(r'([\w\-/\.\[\]]+\.txt)\s*[:：]\s*L?(\d+)(?:\s*[-–~]\s*L?(\d+))?');

final RegExp _coverageLine =
    RegExp(r'\[COVERAGE\s*[:：=]\s*([A-Za-z_]+)\s*\]', caseSensitive: false);

/// "gaps" for the words a model uses to say something was left unread
/// (gaps / partial / incomplete ...), "full" otherwise.
String _coverageOf(String word) {
  final w = word.toLowerCase();
  return w.contains('gap') || w.contains('partial') || w.contains('incomplete')
      ? 'gaps'
      : 'full';
}

/// A plain-text tool call (providers without function calling).
final RegExp _textToolCall = RegExp(r'```(?:tool|json)\s*([\s\S]*?)```');

/// How turns reach the provider. Starts with streamed native function
/// calls. A turn that comes back empty is asked once more the same way,
/// then without streaming ([plain]: some relays break streams or do not
/// stream), then with tools described in the prompt ([textProtocol]: tool
/// calls dropped or malformed). 0.14: that change holds for the turn that
/// needed it; the next turn tries the usual way again, unless turns needed
/// it [stickyAfter] times or the provider refused tools outright. Shared
/// with the sub-agents of the same question.
class AgentTransport {
  bool plain = false;
  bool textProtocol = false;

  /// The provider answered a request with tools with an error about them:
  /// tools stay in the prompt for the rest of the question.
  bool toolsRefused = false;

  /// Turns that had to be sent another way.
  int degradedTurns = 0;
  static const int stickyAfter = 2;
}

class LoreAgentLoop {
  LoreAgentLoop({
    required this.client,
    required this.store,
    this.planClient,
    this.planTimeout = const Duration(seconds: 25),
    this.embeddingClient,
    this.wiki,
    this.materials,
    this.maxTurns = 30,
    this.contextCharBudget = 80000,
    this.maxTokens = 8192,
    this.temperature = 0.3,
    this.subtask = false,
    this.subtaskMaxTurns = 10,
    this.delegate = false,
    this.maxSubtasks = 2,
    this.preSearch = true,
    this.pickLines = false,
    this.streamRetryDelay = const Duration(seconds: 2),
    this.heartbeat = const Duration(seconds: 10),
    this.onSpan,
    AgentTransport? transport,
  }) : transport = transport ?? AgentTransport();

  /// 0.14: the status line while a rejected final answer is written again
  /// (all the player sees of it).
  static const String redoStatus = '回答格式出错，正在重新构思回答…';

  /// 0.14: the client that writes the first searches (default: [client]).
  /// The app passes its plain client, so the "深度思考" one does not think
  /// over a list of search words; a plan later than [planTimeout] is not
  /// waited for.
  final LLMClient? planClient;
  final Duration planTimeout;

  /// How turns are sent (see [AgentTransport]).
  final AgentTransport transport;
  final MaterialSnapshot? materials;

  /// Measurement only: called when a tool run, a local check (citation
  /// text lookup, catalog lookup) or a failed model call finishes, with its
  /// name and wall-clock start and end. Never changes behaviour.
  final void Function(String name, DateTime start, DateTime end)? onSpan;

  Future<T> _span<T>(String name, Future<T> Function() action) async {
    final start = DateTime.now();
    try {
      return await action();
    } finally {
      onSpan?.call(name, start, DateTime.now());
    }
  }

  /// A turn cut by a dropped connection (the app was backgrounded, the
  /// network changed) is asked again up to [_maxStreamRetries] times; the
  /// conversation only grows when a turn completes, so asking again is safe.
  final Duration streamRetryDelay;
  static const int _maxStreamRetries = 2;

  /// While a model call has sent nothing yet, the status line says how long
  /// it has waited, every [heartbeat].
  final Duration heartbeat;

  final LLMClient client;
  final GameDataRetrieval store;

  /// Optional story vectors for `search` (keyword-only without).
  final EmbeddingClient? embeddingClient;

  /// 0.13: the games' wikis (`wiki_search`, `wiki_read`, a third kind of
  /// citation, and a part of `search`); null leaves them out.
  final WikiLookup? wiki;

  /// A sub-agent run by `delegate`: its own conversation, no `delegate`
  /// tool, findings instead of a full answer.
  final bool subtask;

  /// Turn limit of each sub-agent.
  final int subtaskMaxTurns;

  /// 0.14: whether the main agent has the `delegate` tool (off by default:
  /// sub-agents multiplied calls and time without better answers), and how
  /// many sub-agents one question may start.
  final bool delegate;
  final int maxSubtasks;

  /// 0.14: search the question before the first turn (main agent only).
  final bool preSearch;

  /// Phase 2 (S5): `gather` reads wide and picks the lines that bear on
  /// the question, a call per segment with [planClient] ([LinePicker]).
  final bool pickLines;

  /// Model turns per question; the last one must answer.
  final int maxTurns;

  /// Characters of conversation kept whole; past it the oldest tool results
  /// are folded to a one-line pointer (re-read when needed).
  final int contextCharBudget;
  final int maxTokens;
  final double temperature;

  /// Messages kept whole at the end of the conversation when folding.
  static const int _recentKept = 6;

  /// Sub-agents started so far in this question.
  int _subtasks = 0;

  /// Steps of running sub-agents, shown while the main agent waits.
  StreamController<ReActEvent>? _side;

  Stream<ReActEvent> run({
    required String query,
    List<Message> history = const [],
    LoreConversation? prior,
    void Function(LoreConversation conversation)? onConversation,
    void Function(int turn, String rawResponse)? onRawLlmResponse,
    String? asQuestion,
  }) async* {
    // [asQuestion]: what a follow-up takes as the last question when
    // [query] is not the player's own words (the reader's review).
    final seen = prior?.seen ?? SeenLines();
    seen.retainMaterials(
        {for (final d in materials?.documents ?? const <MaterialDocument>[]) d.pageId},);
    // 0.12: the prompt describes every installed game's library.
    final games = store is MultiGameRetrieval
        ? await (store as MultiGameRetrieval).installedGames()
        : const [Game.arknights];
    final delegating = delegate && !subtask;
    final tools = {
      for (final t in [
        ...loreTools(
          store,
          seen,
          materials: materials,
          embeddingClient: embeddingClient,
          wiki: wiki,
          picker:
              pickLines && !subtask ? LinePicker(planClient ?? client) : null,
        ),
        if (wiki != null) ...wikiTools(wiki!, seen),
        if (delegating) DelegateTool((args) => _runSubtask(args, seen)),
      ])
        t.name: t,
    };
    // 0.14: without meaning search the model chooses the search words (it
    // knows how the stories name things; code can only cut up the question,
    // which found a gold story for 16 of 29 eval questions), and `search`
    // says it matches the text literally.
    final search = tools['search'];
    String? keywordOnly;
    if (search is SearchTool) {
      keywordOnly = await search.keywordOnlyReason();
      search
        ..keywordOnly = keywordOnly != null
        ..onSpan = onSpan;
    }
    final toolSpecs = [for (final t in tools.values) t.toJson()];
    final gather = tools['gather'];
    if (gather is GatherTool) gather.question = asQuestion ?? query;

    String systemPrompt() {
      final base = '${loreRolePrompt(
        subtask ? LoreRole.helper : LoreRole.answer,
        games: games,
        wiki: wiki != null,
        delegate: delegating,
      )}\n\n${materials?.guide ?? ''}';
      return transport.textProtocol
          ? '$base\n\n${loreTextToolProtocol(_toolList(tools.values))}'
          : base;
    }

    // Session-record index (one per tool call, see onRawLlmResponse).
    var record = 0;

    if (keywordOnly != null && !subtask) {
      yield ReActEvent(
        type: ReActEventType.thought,
        content: '注意：$keywordOnly，只用关键词检索，问答质量会显著下降。'
            '可以在设置里配置向量服务。',
      );
    }

    final conversation = <Message>[
      if (prior != null) ...prior.messages else ...history,
      Message.user(query),
    ];
    // Indexes (in [conversation]) of tool results that may be folded.
    final toolResults = <int>{
      for (final (i, m) in conversation.indexed)
        if (m.role == MessageRole.tool) i,
    };
    // 0.14: a follow-up keeps the earlier questions, answers and what was
    // read (citable), not the earlier tool output itself.
    if (prior != null) {
      _foldOldToolResults(conversation, toolResults, const {}, all: true);
    }
    // 0.14: messages of turns whose every call was refused by the gate are
    // left out of later requests once a call has gone through (pending
    // until then, so the model still sees why it was refused).
    final hidden = <int>{};
    final refusedTurns = <int>{};
    // 0.14: lookups that found nothing. A turn of nothing but those leaves
    // the conversation once the model has answered it (it saw the result
    // once; a question that the library cannot answer filled the context
    // with two dozen empty queries); what stays is the count, per tool,
    // and past [maxFailedLookups] the tool is not run again this question.
    final failedLookups = <String, int>{};
    // What was asked each time, in brief: the turns themselves are gone, and
    // without this the model sent the same query three times.
    final triedInVain = <String, List<String>>{};
    final emptyTurns = <int>{};
    // 0.14: what each tool result showed (by its index), for the pointer a
    // folded result leaves.
    final shownIn = <int, String>{};

    // 0.14: the first steps, written by a call of its own
    // (`search_planner.dart`) and run here: searches, a collection's
    // outline, a wiki search. They enter the conversation as calls and
    // results like the model's own (folded like them); the question stays
    // as it was asked. Without a plan: with vectors the question itself is
    // searched by meaning; without, the model searches in its first turn.
    if (preSearch && !subtask && search is SearchTool) {
      yield const ReActEvent(type: ReActEventType.status, content: '正在拟定检索…');
      final plan = await _planSearches(
        query,
        prior,
        history,
        search,
        (raw) => onRawLlmResponse?.call(++record, '（拟定检索）$raw'),
        outlineDescription: tools['outline']?.description ?? '',
        wikiSearchDescription: tools['wiki_search']?.description ?? '',
        gatherDescription: tools['gather']?.description ?? '',
      );
      // A step whose tool this question does not have is left out.
      final planned = <({String tool, Map<String, dynamic> args})>[
        // S0 (refactor phase 1): a follow-up gets the text the last answer
        // cited again (its tool results are folded to pointers by now).
        if (prior != null && tools['read_story'] != null)
          for (final r in followUpReads(prior.messages, prior.seen))
            (
              tool: 'read_story',
              args: {'story_id': r.storyId, 'start': r.start, 'count': r.count},
            ),
        if (plan != null) ...[
          if (tools['outline'] != null)
            for (final c in plan.outlines)
              (tool: 'outline', args: {'collection': c}),
          for (final (i, q) in plan.queries.indexed)
            (
              tool: 'search',
              args: {
                'query': q,
                if (i == 0 && wiki != null && plan.wiki != null)
                  'wiki': plan.wiki,
              },
            ),
          if (tools['wiki_search'] != null)
            for (final q in plan.wikiSearches)
              (tool: 'wiki_search', args: {'query': q}),
          // Phase 1 (2026-10-18): the lines around the question's names,
          // after the searches (the stories they found count a little more).
          if (tools['gather'] != null && plan.anchors.isNotEmpty)
            (tool: 'gather', args: {'names': plan.anchors}),
        ] else if (keywordOnly == null)
          (tool: 'search', args: {'query': query}),
      ];
      if (planned.isNotEmpty) {
        final shown = [for (final _ in planned) SeenLines()];
        Future<(String, SearchResult?)> runOne(int k) async {
          final step = planned[k];
          try {
            if (step.tool != 'search') {
              final text = await _span(
                'tool:${step.tool}',
                () => SeenLines.duringCall(
                  shown[k],
                  () => tools[step.tool]!.execute(step.args),
                ),
              );
              return ('$text', null);
            }
            final found = await _span(
              'tool:search',
              () => SeenLines.duringCall(
                shown[k],
                () => search.run(
                  '${step.args['query']}',
                  wikiQuery: step.args['wiki'] as String?,
                ),
              ),
            );
            return (found.text, found);
          } catch (e) {
            return ('错误：${step.tool == 'search' ? '检索' : '查找'}失败（$e）', null);
          }
        }

        final runs = <Future<(String, SearchResult?)>>[];
        for (var k = 0; k < planned.length; k++) {
          runs.add(
            planned[k].tool == 'gather'
                ? Future.wait([...runs]).then((_) => runOne(k))
                : runOne(k),
          );
        }
        final calls = [
          for (final (k, step) in planned.indexed)
            ToolCall(
              id: 'planned_${k + 1}',
              name: step.tool,
              arguments: jsonEncode(step.args),
            ),
        ];
        for (final (k, step) in planned.indexed) {
          // (The first call shares the record of the plan itself.)
          if (k > 0) {
            onRawLlmResponse?.call(++record, '（拟定的第 ${k + 1} 步）');
          }
          yield ReActEvent(
            type: ReActEventType.toolCall,
            content: _describeCall(step.tool, step.args),
            toolName: step.tool,
            toolArgs: step.args,
            planned: true,
          );
        }
        yield ReActEvent(
          type: ReActEventType.status,
          content: planned.length > 1 ? '${planned.length} 项查找同时进行' : '正在检索资料…',
        );
        conversation.add(Message.assistantToolCalls('', calls));
        String? lostVectors;
        for (var k = 0; k < planned.length; k++) {
          final (text, found) = await runs[k];
          yield ReActEvent(
            type: ReActEventType.toolObservation,
            content: text,
            toolName: planned[k].tool,
          );
          if (found?.mode == SearchMode.keywordOnly && keywordOnly == null) {
            lostVectors = found?.modeNote ?? '没有向量检索';
          }
          toolResults.add(conversation.length);
          if (!shown[k].isEmpty) {
            shownIn[conversation.length] = shown[k].summary();
          }
          conversation.add(Message.toolResult(calls[k].id, text));
        }
        if (lostVectors != null) {
          yield ReActEvent(
            type: ReActEventType.thought,
            content: '注意：$lostVectors，只用关键词检索，问答质量会显著下降。'
                '可以在设置里配置向量服务。',
          );
        }
      }
    }

    // 0.14: notes a rejected final answer was asked again with (the answer
    // itself is never added); hidden once an answer is accepted.
    final redoNotes = <int>[];
    // The turn about to be sent asks again for a rejected answer.
    var redoing = false;

    var citationRetried = false;
    var missingChecked = false;
    var nudged = false;
    // R18: the answer last sent back for a rewrite (citation recheck);
    // kept if the rewrite never comes.
    String? rewriteOf;
    // That answer had no citation at all: a second one without any is the
    // model's answer (nothing better to keep), not talk about the process.
    var rewriteUncited = false;
    var hitTurnLimit = false;
    var streamRetries = 0;
    // 0.14: how this turn is being sent (see [AgentTransport]).
    var retrying = false;
    var emptyRetried = false;
    var degradedThisTurn = false;
    var turnBase = (transport.plain, transport.textProtocol);

    List<Message> visible() => [
          for (final (i, m) in conversation.indexed)
            if (!hidden.contains(i)) m,
        ];

    for (var turn = 1; turn <= maxTurns; turn++) {
      if (!retrying) {
        if (degradedThisTurn &&
            transport.degradedTurns < AgentTransport.stickyAfter) {
          transport
            ..plain = turnBase.$1
            ..textProtocol = turnBase.$2 || transport.toolsRefused;
        }
        degradedThisTurn = false;
        emptyRetried = false;
        turnBase = (transport.plain, transport.textProtocol);
      }
      retrying = false;
      void degrade() {
        if (!degradedThisTurn) transport.degradedTurns++;
        degradedThisTurn = true;
      }

      final lastTurn = turn == maxTurns;
      // (Once: an empty last turn may be sent again another way.)
      if (lastTurn && !hitTurnLimit) {
        hitTurnLimit = true;
        conversation.add(Message.user(loreTurnLimitNote));
      }
      if (transport.textProtocol) {
        _convertToTextProtocol(conversation, toolResults);
      }
      _foldOldToolResults(conversation, toolResults, shownIn);
      final statusPrefix = redoing
          ? '重新构思回答'
          : turn == 1
              ? '正在思考'
              : '第 $turn 轮';
      yield ReActEvent(
        type: ReActEventType.status,
        content: redoing
            ? redoStatus
            : turn == 1
                ? '正在思考…'
                : '第 $turn 轮 · 思考中',
      );
      redoing = false;

      final text = StringBuffer();
      final reasoning = StringBuffer();
      var answerOpen = false;
      // R17c: the main agent answers in JSON, shown as markdown while it
      // streams.
      LoreAnswerStream? jsonAnswer;
      CompletionDelta? done;
      final callStart = DateTime.now();
      try {
        final messages = [Message.system(systemPrompt()), ...visible()];
        final turnTools = transport.textProtocol ? null : toolSpecs;
        final stream = transport.plain
            ? _plainTurn(messages, turnTools)
            : client.streamTurn(
                messages,
                tools: turnTools,
                toolChoice: lastTurn && !transport.textProtocol ? 'none' : null,
                temperature: temperature,
                maxTokens: maxTokens,
              );
        await for (final item in _withHeartbeat(stream)) {
          if (item is Duration) {
            if (text.isEmpty && reasoning.isEmpty) {
              yield ReActEvent(
                type: ReActEventType.status,
                content: '$statusPrefix · 等待服务商响应（已 ${item.inSeconds} 秒）',
              );
            }
            continue;
          }
          final delta = item as CompletionDelta;
          if (delta.reasoningContent.isNotEmpty) {
            reasoning.write(delta.reasoningContent);
            yield ReActEvent(
              type: ReActEventType.reasoningToken,
              content: delta.reasoningContent,
            );
          }
          if (delta.content.isNotEmpty) {
            text.write(delta.content);
            var live = '';
            if (jsonAnswer != null) {
              live = jsonAnswer.add(delta.content);
            } else if (!subtask) {
              final start = loreAnswerJsonStart.firstMatch(text.toString());
              if (start != null) {
                if (answerOpen) {
                  yield const ReActEvent(
                    type: ReActEventType.finalAnswerReset,
                    content: '开始写正式答案',
                  );
                }
                answerOpen = true;
                jsonAnswer = LoreAnswerStream();
                live = jsonAnswer.add(text.toString().substring(start.start));
              }
            }
            if (jsonAnswer != null) {
              if (live.isNotEmpty) {
                yield ReActEvent(
                  type: ReActEventType.finalAnswerToken,
                  content: live,
                );
              }
              // Narration before a tool call is short; longer text with no
              // tool block is the answer, streamed as it comes.
            } else if (answerOpen) {
              yield ReActEvent(
                type: ReActEventType.finalAnswerToken,
                content: delta.content,
              );
            } else if (text.length >= 160 && !text.toString().contains('```')) {
              answerOpen = true;
              yield ReActEvent(
                type: ReActEventType.finalAnswerToken,
                content: text.toString(),
              );
            }
          }
          if (delta.done) done = delta;
        }
      } on LLMException catch (e) {
        // 0.14: a failed call is part of the timeline too.
        onSpan?.call(
            'llm_error:${_clip(e.message, 80)}', callStart, DateTime.now(),);
        if (!transport.textProtocol && _rejectsTools(e)) {
          // The provider has no function calling: switch to plain-text tool
          // calls and ask again.
          transport
            ..textProtocol = true
            ..toolsRefused = true;
          retrying = true;
          turn--;
          continue;
        }
        if (!lastTurn &&
            streamRetries < _maxStreamRetries &&
            _isConnectionDrop(e)) {
          streamRetries++;
          if (answerOpen) {
            yield const ReActEvent(
              type: ReActEventType.finalAnswerReset,
              content: '连接中断，重试',
            );
          }
          yield ReActEvent(
            type: ReActEventType.status,
            content:
                '${e.message.contains('timed out') ? '服务商长时间没有响应' : '连接中断'}，'
                '正在重试（$streamRetries/$_maxStreamRetries）',
          );
          await Future<void>.delayed(streamRetryDelay * streamRetries);
          retrying = true;
          turn--;
          continue;
        }
        // An answer that came (status 200) but could not be read — a body
        // that is neither a stream nor a completion, an error inside the
        // stream: asked again another way, as an empty answer is.
        // (A web page instead of an API answer is a wrong Base URL: asking
        // again cannot help.)
        if (e.statusCode == 200 &&
            !(e.body ?? '').trimLeft().startsWith('<') &&
            _nextTransport()) {
          degrade();
          if (answerOpen) {
            yield const ReActEvent(
              type: ReActEventType.finalAnswerReset,
              content: '回复无法读取，重试',
            );
          }
          onRawLlmResponse?.call(++record, '（无法读取的回复：${e.message}）');
          yield ReActEvent(
            type: ReActEventType.status,
            content: transport.textProtocol
                ? '服务商的回复无法读取，这一轮改用文本方式调用工具重试'
                : '服务商的回复无法读取，这一轮改用非流式请求重试',
          );
          retrying = true;
          turn--;
          continue;
        }
        yield ReActEvent(type: ReActEventType.error, content: e.message);
        return;
      } catch (e) {
        yield ReActEvent(type: ReActEventType.error, content: '$e');
        return;
      }

      streamRetries = 0;
      var content = text.toString();
      var calls = done?.toolCalls ?? const <ToolCall>[];
      if (calls.isEmpty) {
        final parsed = _parseTextToolCalls(content);
        if (parsed.isNotEmpty) {
          calls = parsed;
          content = content.replaceAll(_textToolCall, '').trim();
        }
      }
      // Nothing at all (no text, no call): the provider or a relay lost the
      // turn. 0.14: asked once more the same way, then without streaming,
      // then with the tools described in the prompt — for this turn.
      if (content.trim().isEmpty && calls.isEmpty) {
        final note = _emptyTurnNote(done, reasoning.isNotEmpty);
        if (!emptyRetried) {
          emptyRetried = true;
          onRawLlmResponse?.call(++record, '（空回复：$note）');
          onSpan?.call('llm_empty', callStart, DateTime.now());
          yield ReActEvent(
            type: ReActEventType.status,
            content: '服务商没有返回内容（$note），重试一次',
          );
          retrying = true;
          turn--;
          continue;
        }
        if (_nextTransport()) {
          degrade();
          onRawLlmResponse?.call(++record, '（空回复：$note）');
          onSpan?.call('llm_empty', callStart, DateTime.now());
          yield ReActEvent(
            type: ReActEventType.status,
            content: transport.textProtocol
                ? '服务商没有返回内容，这一轮改用文本方式调用工具重试'
                : '服务商没有返回内容，这一轮改用非流式请求重试',
          );
          retrying = true;
          turn--;
          continue;
        }
      }
      // Session records keep one tool per iteration: each call of a turn
      // gets its own record (the first carries the turn's raw response).
      if (calls.isEmpty || lastTurn) {
        onRawLlmResponse?.call(++record, content);
      }

      if (calls.isNotEmpty && !lastTurn) {
        if (answerOpen) {
          yield const ReActEvent(
            type: ReActEventType.finalAnswerReset,
            content: '继续查资料',
          );
        }
        if (content.trim().isNotEmpty) {
          yield ReActEvent(
              type: ReActEventType.thought, content: content.trim(),);
        }
        // 0.14: the gate — glued calls split, arguments checked against
        // each tool's schema; what enters the conversation is valid JSON.
        final checked = [
          for (final c in splitGluedCalls(calls))
            checkToolCall(c, tools[c.name], tools.keys),
        ];
        // The model has answered the last turn's empty lookups: they go.
        hidden.addAll(emptyTurns);
        emptyTurns.clear();
        final turnStart = conversation.length;
        if (transport.textProtocol) {
          conversation.add(Message.assistant(text.toString()));
        } else {
          conversation.add(
            Message.assistantToolCalls(
              content,
              [for (final c in checked) c.sanitized],
              reasoningContent: reasoning.isEmpty ? null : reasoning.toString(),
            ),
          );
        }
        final delegates = [
          for (final c in checked)
            if (c.ok && c.call.name == 'delegate') c,
        ].length;
        // All calls of a turn run at once (sub-agents in parallel); events
        // and tool messages still follow the calls' order.
        final side = delegates > 0 ? StreamController<ReActEvent>() : null;
        _side = side;
        final shown = [for (final _ in checked) SeenLines()];
        final results = [
          for (final (k, c) in checked.indexed)
            !c.ok
                ? Future<String>.value(c.error)
                : (failedLookups[c.call.name] ?? 0) >= maxFailedLookups
                    ? Future<String>.value(lookupLimitNote(c.call.name))
                    : _runTool(tools[c.call.name]!, c, shown[k]),
        ];
        var found = 0;
        for (final (k, c) in checked.indexed) {
          onRawLlmResponse?.call(
            ++record,
            k == 0
                ? '$content\n${jsonEncode([for (final c in calls) c.toJson()])}'
                    .trim()
                : '（第 $turn 轮的第 ${k + 1} 个调用）',
          );
          final label = _describeCall(c.call.name, c.arguments);
          yield ReActEvent(
            type: ReActEventType.toolCall,
            content: label,
            toolName: c.call.name,
            toolArgs: c.arguments,
          );
        }
        yield ReActEvent(
          type: ReActEventType.status,
          content: delegates > 1
              ? '第 $turn 轮 · $delegates 个子任务并行查阅中'
              : '第 $turn 轮 · ${checked.length > 1 ? '${checked.length} 个工具同时运行' : _describeCall(checked.first.call.name, checked.first.arguments)}',
        );
        if (side != null) {
          // Sub-agents' steps show up while they work.
          unawaited(Future.wait(results).whenComplete(side.close));
          await for (final event in side.stream) {
            yield event;
          }
          _side = null;
        }
        for (final (k, c) in checked.indexed) {
          var result = await results[k];
          if (c.ok && c.note != null) result = '$result\n${c.note}';
          if (lookupFoundNothing(result)) {
            final name = c.call.name;
            final n = failedLookups[name] = (failedLookups[name] ?? 0) + 1;
            if (n <= maxFailedLookups &&
                !result.startsWith(lookupLimitPrefix)) {
              final before = triedInVain[name] ??= [];
              result = '$result\n（这次问答里 $name 已有 $n 次没有结果'
                  '${n == maxFailedLookups ? '，到上限了：之后的 $name 调用不再执行。$lookupLimitAdvice' : '，上限 $maxFailedLookups 次'}'
                  '${before.isEmpty ? '' : '。此前没有结果的调用（不要再发同样的）：${[
                      for (final (i, t) in before.indexed) '${i + 1}. $t',
                    ].join('；')}'}）';
              before.add(_clip(jsonEncode(c.arguments), triedBriefChars));
            }
            if (n == maxFailedLookups) {
              yield ReActEvent(
                type: ReActEventType.recordNote,
                content: '$name 已有 $n 次没有结果，之后不再执行',
              );
            }
          } else {
            found++;
          }
          yield ReActEvent(
            type: ReActEventType.toolObservation,
            content: result,
            toolName: c.call.name,
          );
          toolResults.add(conversation.length);
          if (!shown[k].isEmpty) {
            shownIn[conversation.length] = shown[k].summary();
          }
          conversation.add(
            transport.textProtocol
                ? Message.user('工具结果（${c.call.name}）：\n$result')
                : Message.toolResult(c.call.id, result),
          );
        }
        if (checked.every((c) => !c.ok)) {
          refusedTurns.addAll([
            for (var i = turnStart; i < conversation.length; i++) i,
          ]);
        } else if (refusedTurns.isNotEmpty) {
          hidden.addAll(refusedTurns);
          refusedTurns.clear();
        }
        // Nothing found by any call of the turn: it stays for one reply.
        if (found == 0 && checked.any((c) => c.ok)) {
          emptyTurns.addAll([
            for (var i = turnStart; i < conversation.length; i++)
              // What came with it for later use (the manual) stays.
              if (!conversation[i].content.contains(libraryManualMark)) i,
          ]);
          // A call whose result stays keeps its call too.
          if (emptyTurns.length < conversation.length - turnStart) {
            emptyTurns.removeWhere((i) => i >= turnStart);
          }
        }
        continue;
      }

      // A final answer: JSON (R17c) becomes markdown with each entry's
      // citations at its end; a markdown answer is taken as it is.
      // `story_id:L12-L40` is written without the L, the form the citation
      // display reads.
      // R18: after a rewrite request, a reply with neither a JSON answer nor
      // any citation only talks about the process ("核对完毕，现在输出……"):
      // ask once more, then keep the answer that was sent back.
      if (rewriteOf != null &&
          !rewriteUncited &&
          !subtask &&
          !loreAnswerJsonStart.hasMatch(content) &&
          _citationCount(content) == 0) {
        if (!nudged && !lastTurn) {
          nudged = true;
          yield const ReActEvent(
            type: ReActEventType.recordNote,
            content: '退回：回复只描述了核对过程、没有答案',
          );
          yield const ReActEvent(
            type: ReActEventType.finalAnswerReset,
            rollback: true,
          );
          redoNotes.add(conversation.length);
          conversation.add(Message.user(loreAnswerOnlyNote));
          redoing = true;
          continue;
        }
        content = rewriteOf;
      }
      final parsedJson = subtask ? null : loreAnswerParsed(content);
      // Read past a bracket that closed the object early: the rest of the
      // turn (the kept answer, the reorganising) reads it as valid JSON.
      if (parsedJson?.repaired != null) content = parsedJson!.repaired!;
      final fromJson = parsedJson?.markdown;
      // A flat or odd citation shape is written back in the nested form, so
      // later turns (rewrite, follow-ups) do not copy it.
      final keep = fromJson == null ? content : normalizeAnswerCites(content);
      var body = (fromJson ?? content)
          .trim()
          .replaceAllMapped(
            RegExp(r'(\.txt\s*[:：]\s*)L(\d+)(\s*[-–~]\s*)?L?(\d+)?'),
            (m) => '${m.group(1)}${m.group(2)}'
                '${m.group(4) == null ? '' : '${m.group(3) ?? '-'}${m.group(4)}'}',
          )
          // 0.14: a record id is shown as `record:<id>`; its prefix written
          // twice counts once.
          .replaceAll(_doubledRecordPrefix, 'record:');
      if (fromJson == null) body = _plainAnswerCites(body);
      if (body.isEmpty) {
        if (!nudged && !lastTurn) {
          nudged = true;
          conversation.add(Message.user(loreContinueNote));
          continue;
        }
        yield ReActEvent(
          type: ReActEventType.error,
          content: '模型没有给出答案（${_emptyTurnNote(done, reasoning.isNotEmpty)}）。'
              '${transport.plain && transport.textProtocol ? '已换用非流式请求和文本方式调用工具重试，仍然没有内容。' : ''}',
        );
        return;
      }

      // 0.14: a range shown only in part is cut to the lines that were
      // shown (a search lists some lines of a passage; the range over them
      // was dropped whole, and with it a sound citation).
      // Phase 2 (S7): a story id written short (its file name only) is
      // written out when one story read in this question has that name.
      final expanded = expandShortStoryIds(body, seen.stories);
      if (expanded.$2.isNotEmpty) {
        body = expanded.$1;
        yield ReActEvent(
          type: ReActEventType.recordNote,
          content: '补全了出处的路径：${expanded.$2.join('；')}',
        );
      }
      final trims = _partlySeen(body, seen);
      for (final MapEntry(key: cite, value: runs) in trims.entries) {
        body = body.replaceAll('`$cite`', runs.map((c) => '`$c`').join(' '));
      }
      final unseen = _unseenCitations(body, seen);
      final bare = _bareStoryCitations(body);
      final citations = _citationCount(body);
      // Citations written in a shape that cannot be read are lost from the
      // answer: some items gave no ref, or (0.14: JSON or prose alike) the
      // model read lines but not one citation came out.
      final unreadable = !subtask &&
          ((parsedJson != null && parsedJson.dropped > 0) ||
              (!seen.isEmpty && citations == 0));
      // 0.14 live: the JSON object closed before its last entries (a
      // bracket too many); what stands after it is not in the answer.
      final cutShort = parsedJson != null && parsedJson.cutShort;
      // 0.14: a few citations of lines that were not read are dropped by
      // code (the rest of the answer stands on checked ones); the answer
      // is sent back only when many are, or for what code cannot fix.
      final fewUnseen = unseen.isNotEmpty && unseen.length * 3 <= citations;
      final manyUnseen = unseen.isNotEmpty && !fewUnseen;
      final sendBack = manyUnseen || bare.isNotEmpty || unreadable || cutShort;
      if (sendBack && !citationRetried && !lastTurn) {
        citationRetried = true;
        rewriteOf = keep;
        rewriteUncited = citations == 0;
        // 0.14: the turn is taken back. The rejected answer does not enter
        // the conversation and nothing of it stays on screen; why is in the
        // session record. The note it is asked again with leaves the
        // conversation once an answer is accepted.
        yield ReActEvent(
          type: ReActEventType.recordNote,
          content: '退回：${[
            if (unreadable) '没有可识别的出处',
            if (cutShort) 'JSON 提前闭合，后面的条目没有读到',
            if (manyUnseen) '${unseen.length} 处出处不在读过的原文里（${unseen.join('、')}）',
            if (bare.isNotEmpty) '${bare.length} 处出处缺少行号（${bare.join('、')}）',
          ].join('；')}',
        );
        yield const ReActEvent(
          type: ReActEventType.finalAnswerReset,
          rollback: true,
        );
        redoNotes.add(conversation.length);
        conversation.add(
          Message.user(
            loreRedoNote(
              unreadable: unreadable,
              cutShort: cutShort,
              unseen: manyUnseen ? unseen : const [],
              bare: bare,
              json: !subtask,
            ),
          ),
        );
        redoing = true;
        continue;
      }

      // Phase 2 (3.2): what the answer says was not found is looked for
      // once more by code, with the names it gave, in stories it has not
      // read; text found goes back with the answer for a rewrite (once).
      if (!subtask && !missingChecked && !lastTurn && fromJson != null) {
        final missing = loreAnswerMissing(content);
        if (missing.isNotEmpty) {
          missingChecked = true;
          final found = await _lookForMissing(missing, seen);
          final points = [
            for (final m in missing)
              m.point.isEmpty ? m.words.join('、') : m.point,
          ];
          if (found == null) {
            yield ReActEvent(
              type: ReActEventType.recordNote,
              content: '已查证“没有查到”：${points.join('；')}'
                  '（${missing.expand((m) => m.words).join('、')}在没读过的剧情里没有找到）',
            );
          } else {
            yield ReActEvent(
              type: ReActEventType.recordNote,
              content: '查证“没有查到”：${points.join('；')}，'
                  '在没读过的剧情里找到 ${found.stories} 篇，交回重写',
            );
            yield const ReActEvent(
              type: ReActEventType.finalAnswerReset,
              rollback: true,
            );
            rewriteOf = keep;
            rewriteUncited = citations == 0;
            redoNotes.add(conversation.length);
            conversation.add(Message.assistant(keep));
            redoNotes.add(conversation.length);
            conversation.add(
              Message.user(loreMissingFoundNote(points, found.text)),
            );
            redoing = true;
            continue;
          }
        }
      }

      if (trims.isNotEmpty) {
        yield ReActEvent(
          type: ReActEventType.recordNote,
          content: '出处裁到读过的行：${[
            for (final MapEntry(key: cite, value: runs) in trims.entries)
              '$cite → ${runs.join(' ')}',
          ].join('；')}',
        );
      }
      body = _dropProcessLeadIn(body);
      final coverageWord = _coverageLine.firstMatch(body)?.group(1);
      final coverage = coverageWord == null ? null : _coverageOf(coverageWord);
      body = body.replaceAll(_coverageLine, '').trim();
      var removedMaterialCitations = 0;
      if (unseen.isNotEmpty) {
        if (fewUnseen) {
          // 0.14: dropped rather than shown as unchecked; which ones is in
          // the session record only.
          for (final c in unseen) {
            body = body.replaceAll('`$c`', '');
          }
          yield ReActEvent(
            type: ReActEventType.recordNote,
            content: '删去了没在读到的原文中核实的出处：${unseen.join('、')}',
          );
        } else {
          for (final c in unseen.where((c) => c.startsWith('material:'))) {
            body = body.replaceAll('`$c`', '').replaceAll(c, '');
            removedMaterialCitations++;
          }
          body = '$body\n\n> 以下出处未能在本次读到的原文中核实：'
              '${unseen.map((c) => c.startsWith('material:') ? '补充资料的未读段落' : '`$c`').join('、')}';
        }
      }
      if (done?.finishReason == 'length') {
        body = '$body\n\n> 注意：答案达到长度上限，可能不完整。';
      }
      final verified = _citationCount(body) -
          (fewUnseen ? 0 : unseen.length - removedMaterialCitations);
      // The model's own text (JSON) stays in the conversation, so a
      // follow-up sees the format it is asked for.
      hidden.addAll(redoNotes);
      hidden.addAll(emptyTurns);
      conversation.add(Message.assistant(fromJson == null ? body : keep));

      // What "提要" would reorganise: the entries with the citations that
      // passed the check.
      final entries = [
        if (fromJson != null && !subtask)
          for (final e
              in loreAnswerEntries(content) ?? const <LoreAnswerEntry>[])
            LoreAnswerEntry(
              heading: e.heading,
              text: e.text,
              cites: [
                for (final c in e.cites)
                  if (!unseen.contains(c)) ...(trims[c] ?? [c]),
              ],
            ),
      ];

      // A claim check carries a verdict: a definite one needs cited,
      // actually-read text (checked here, not left to the model).
      if (!subtask && body.contains('[FACT_CHECK_VERDICT')) {
        body = normalizeFactCheckBody(
          body,
          nothingRead: seen.isEmpty,
          hasValidCitation: verified > 0,
        );
      }
      final status = verified <= 0
          ? StoryAnswerStatus.notCovered
          : (coverage == 'gaps' || hitTurnLimit)
              ? StoryAnswerStatus.partial
              : StoryAnswerStatus.answered;
      // What a follow-up starts from: the tool results folded now, while
      // what each showed is still known.
      _foldOldToolResults(conversation, toolResults, shownIn, all: true);
      onConversation?.call(
        LoreConversation(
          messages: visible(),
          seen: seen,
          question: asQuestion ?? query,
          entries: entries,
        ),
      );
      yield ReActEvent(
        type: ReActEventType.finalAnswerReplace,
        content: '${formatStoryAnswerEnvelope(status)}\n$body',
      );
      yield const ReActEvent(type: ReActEventType.complete);
      return;
    }
  }

  /// [stream]'s deltas, with the time waited so far (a [Duration]) every
  /// [heartbeat] until the stream ends.
  Stream<Object> _withHeartbeat(Stream<CompletionDelta> stream) {
    late final StreamController<Object> out;
    Timer? timer;
    StreamSubscription<CompletionDelta>? sub;
    final start = DateTime.now();
    out = StreamController<Object>(
      onListen: () {
        timer = Timer.periodic(heartbeat, (_) {
          if (!out.isClosed) out.add(DateTime.now().difference(start));
        });
        sub = stream.listen(
          out.add,
          onError: out.addError,
          onDone: () {
            timer?.cancel();
            out.close();
          },
        );
      },
      onCancel: () async {
        timer?.cancel();
        await sub?.cancel();
      },
    );
    return out.stream;
  }

  /// R18: the reviewer's questions about [answer] to [query] (empty when it
  /// has none or the call fails). 0.14: asked for under a finished answer;
  /// the questions go back to the main agent as a follow-up.
  Future<List<String>> review(
    String query,
    String answer, {
    void Function(String raw)? onRaw,
  }) async {
    onRaw ??= (_) {};
    try {
      final games = store is MultiGameRetrieval
          ? await (store as MultiGameRetrieval).installedGames()
          : const [Game.arknights];
      final ids = <String>{
        for (final m in _citation.allMatches(answer)) m.group(1)!,
      };
      final catalog = ids.isEmpty
          ? const <String, StoryCatalogEntry>{}
          : await _span('catalog', () => store.storyCatalogEntries(ids));
      final stories = <String>{
        for (final id in ids) catalog[id]?.label ?? fallbackStoryLabel(id),
        // 0.13: wiki pages, named as the site and title.
        for (final m in wikiCitationPattern.allMatches(answer))
          if (await wiki?.snapshot(_wikiPageIdOf(m)) case final page?)
            '${page.site.label}《${page.title}》',
      }.take(40).toList();
      final result = await client.chatCompletion(
        [
          Message.system(loreRolePrompt(LoreRole.reviewer, games: games)),
          Message.user(
            loreReviewRequest(query, stories, withoutCitations(answer)),
          ),
        ],
        temperature: temperature,
        maxTokens: 1024,
      );
      onRaw(result.content);
      return parseReviewIssues(result.content);
    } catch (e) {
      onRaw('审稿失败：$e');
      return const [];
    }
  }

  /// "提要" (0.14: asked for under a finished answer): [entries] grouped
  /// into a few paragraphs above the detailed answer [detail]. Ends with
  /// the whole text (paragraphs, [loreDetailsMarker], [detail]) and
  /// `complete`, or with an `error` when no paragraphs came out ([detail]
  /// is then all there is).
  Stream<ReActEvent> digest(
    List<LoreAnswerEntry> entries, {
    required String question,
    required String detail,
    void Function(String raw)? onRaw,
  }) async* {
    String? staged;
    yield* _stage(
      entries,
      question: question,
      detail: detail,
      onRaw: onRaw ?? (_) {},
      onStaged: (markdown) => staged = markdown,
    );
    if (staged == null) {
      yield const ReActEvent(type: ReActEventType.error, content: '没有整理出提要');
      return;
    }
    yield ReActEvent(
      type: ReActEventType.finalAnswerReplace,
      content: '$staged\n\n$loreDetailsMarker\n\n$detail',
    );
    yield const ReActEvent(type: ReActEventType.complete);
  }

  /// R18: one more call that groups [entries] into a few paragraphs.
  /// Streams the paragraphs above the detailed answer ([detail]) as they
  /// are written; [onStaged] gets the final markdown with merged citations,
  /// or nothing on any failure (only the detailed answer is shown then).
  /// 0.14: the call sees the question and the entries only — not the
  /// conversation that wrote them (which made it the largest request of a
  /// question), and nothing of it is kept in the conversation.
  Stream<ReActEvent> _stage(
    List<LoreAnswerEntry> entries, {
    required String question,
    required String detail,
    required void Function(String raw) onRaw,
    required void Function(String markdown) onStaged,
  }) async* {
    final count = entries.where((e) => e.isText).length;
    yield const ReActEvent(type: ReActEventType.status, content: '整理答案');
    final messages = [
      Message.system(loreRolePrompt(LoreRole.stager)),
      Message.user(
          loreStagePrompt(numberedEntries(entries), question: question),),
    ];
    final text = StringBuffer();
    var shown = 0;
    final start = DateTime.now();
    try {
      final stream = transport.plain
          ? _plainTurn(messages, null)
          : client.streamTurn(
              messages,
              temperature: temperature,
              maxTokens: maxTokens,
            );
      await for (final delta in stream) {
        if (delta.content.isEmpty) continue;
        text.write(delta.content);
        final preview = _stagePreview(text.toString());
        if (preview.length - shown >= 24) {
          shown = preview.length;
          yield ReActEvent(
            type: ReActEventType.finalAnswerReplace,
            content: '$preview\n\n$loreDetailsMarker\n\n$detail',
          );
        }
      }
    } on LLMException catch (e) {
      onSpan?.call('llm_error:${_clip(e.message, 80)}', start, DateTime.now());
      // Fall through: the detailed answer is shown as it is.
    } catch (_) {
      // Fall through: the detailed answer is shown as it is.
    }
    onRaw(text.toString());
    final stages = parseLoreStages(text.toString(), count);
    if (stages == null) return;
    onStaged(stagedAnswerMarkdown(stages, entries));
  }

  /// Headings and paragraphs of a reorganising reply still being written
  /// (no citations yet).
  static String _stagePreview(String partial) {
    final out = <String>[];
    for (final m in _stageField.allMatches(partial)) {
      final raw = m.group(2)!;
      String value;
      try {
        value = jsonDecode('"$raw"') as String;
      } on FormatException {
        value = raw;
      }
      if (value.trim().isEmpty) continue;
      out.add(m.group(1) == 'heading' ? '## ${value.trim()}' : value.trim());
    }
    return out.join('\n\n');
  }

  static final RegExp _stageField =
      RegExp(r'"(heading|text)"\s*:\s*"((?:[^"\\]|\\.)*)');

  /// Runs a `delegate` call: a sub-agent with its own conversation. What it
  /// saw counts as seen here, so its checked citations can be reused. Its
  /// tool steps are shown as they happen (tagged with its number).
  Future<String> _runSubtask(
    Map<String, dynamic> args,
    SeenLines parentSeen,
  ) async {
    final task = delegateTaskText(args);
    if (task.trim().isEmpty) return '错误：task 为空';
    if (_subtasks >= maxSubtasks) {
      return '错误：这个问题的子助手已经用完（最多 $maxSubtasks 个），请自己检索和阅读。';
    }
    final number = ++_subtasks;
    final childSeen = SeenLines();
    final events = <ReActEvent>[];
    await for (final event in LoreAgentLoop(
      client: client,
      store: store,
      embeddingClient: embeddingClient,
      wiki: wiki,
      materials: materials,
      maxTurns: subtaskMaxTurns,
      contextCharBudget: contextCharBudget,
      maxTokens: maxTokens,
      temperature: temperature,
      subtask: true,
      preSearch: false,
      heartbeat: heartbeat,
      onSpan: onSpan,
      transport: transport,
    ).run(
      query: task,
      prior: LoreConversation(seen: childSeen),
    )) {
      events.add(event);
      if (event.type == ReActEventType.toolCall ||
          event.type == ReActEventType.toolObservation ||
          event.type == ReActEventType.error) {
        final side = _side;
        if (side != null && !side.isClosed) {
          side.add(
            ReActEvent(
              type: event.type,
              content: event.content,
              toolName: event.toolName,
              toolArgs: event.toolArgs,
              subtask: number,
            ),
          );
        }
      }
    }
    final error = events.where((e) => e.type == ReActEventType.error);
    if (error.isNotEmpty) return '子任务出错：${error.first.content}';
    parentSeen.addAll(childSeen);
    final answer = finalAnswerOf(events);
    final findings = answer.replaceFirst(storyAnswerEnvelopePattern, '').trim();
    final status = RegExp(r'status=(\w+)').firstMatch(answer)?.group(1);
    // The sub-agent's own coverage and citation check travel with its notes.
    final header = switch (status) {
      'partial' => '子任务结果（子助手报告有没读到的部分；列出的出处已核对，可直接引用）',
      'not_covered' => '子任务结果（没有核对通过的出处，只能当线索，不能引用）',
      _ => '子任务结果（出处已核对，可直接引用）',
    };
    return '$header：\n$findings';
  }

  /// 0.14: the first searches for [query], from a call of its own (see
  /// `search_planner.dart`); null when it fails, takes too long or writes
  /// no plan. A follow-up comes with the question before it and the gist
  /// of its answer, so "they" can be written as a name.
  Future<SearchPlan?> _planSearches(
    String query,
    LoreConversation? prior,
    List<Message> history,
    SearchTool search,
    void Function(String raw) onRaw, {
    String outlineDescription = '',
    String wikiSearchDescription = '',
    String gatherDescription = '',
  }) async {
    // Fired when the plan takes too long: the request (perhaps waiting out
    // a 429) must not run on beside the main model's first call.
    final abort = Completer<void>();
    try {
      final result = await (planClient ?? client).chatCompletion(
        [
          Message.system(
            loreRolePrompt(
              LoreRole.planner,
              wiki: wiki != null,
              searchDescription: search.description,
              outlineDescription: outlineDescription,
              wikiSearchDescription: wikiSearchDescription,
              gatherDescription: gatherDescription,
            ),
          ),
          Message.user(
            loreSearchPlanRequest(query, earlier: _earlier(prior, history)),
          ),
        ],
        temperature: 0.2,
        maxTokens: 512,
        abortTrigger: abort.future,
      ).timeout(planTimeout);
      onRaw(result.content);
      return parseSearchPlan(result.content);
    } catch (e) {
      if (!abort.isCompleted) abort.complete();
      onRaw('没有拟定出检索词：$e');
      return null;
    }
  }

  /// Story text for [missing]'s names that the conversation has not shown
  /// (registered in [seen]), or null when there is none.
  Future<({String text, int stories})?> _lookForMissing(
    List<({String point, List<String> words})> missing,
    SeenLines seen,
  ) async {
    final words = <String>{for (final m in missing) ...m.words}.toList();
    final coverage = await CoverageBuilder(store).build(
      words,
      budgetChars: missingLookupChars,
    );
    final unread = [
      for (final p in coverage.passages)
        if (seen.seenRanges(p.storyId, p.first, p.last).isEmpty) p,
    ];
    if (unread.isEmpty) return null;
    for (final p in unread) {
      for (final l in p.lines) {
        seen.addStoryLine(p.storyId, l);
      }
    }
    return (
      text: renderPassages(unread, coverage.labels),
      stories: {for (final p in unread) p.storyId}.length,
    );
  }

  /// Characters of story text the lookup for an answer's `missing` gives.
  static const int missingLookupChars = 12000;

  /// Lines read again before a follow-up: the story ranges the last answer
  /// cited (and were read), each with two lines around it; ranges less than
  /// [joinGap] lines apart are read as one. In the order the answer cites
  /// them, up to [maxLines] lines in all.
  static List<({String storyId, int start, int count})> followUpReads(
    List<Message> messages,
    SeenLines seen, {
    int joinGap = 20,
    int maxLines = 400,
  }) {
    final answer = messages.lastWhere(
      (m) =>
          m.role == MessageRole.assistant &&
          (m.toolCalls ?? const []).isEmpty &&
          m.content.trim().isNotEmpty,
      orElse: () => Message.assistant(''),
    );
    // The conversation keeps the answer as the model wrote it: JSON, whose
    // `cite` arrays the pattern below does not match.
    final entries = loreAnswerEntries(answer.content);
    final cited = entries == null
        ? answer.content
        : [for (final e in entries) ...e.cites].join(' ');
    final ranges = <String, List<(int, int)>>{};
    for (final m in _citation.allMatches(cited)) {
      final story = m.group(1)!;
      final a = int.parse(m.group(2)!);
      final b = int.tryParse(m.group(3) ?? '') ?? a;
      for (final r in seen.seenRanges(story, a < b ? a : b, a < b ? b : a)) {
        (ranges[story] ??= []).add(r);
      }
    }
    final reads = <({String storyId, int start, int count})>[];
    var total = 0;
    for (final MapEntry(key: story, value: list) in ranges.entries) {
      list.sort((x, y) => x.$1.compareTo(y.$1));
      final joined = <(int, int)>[];
      for (final r in list) {
        if (joined.isNotEmpty && r.$1 - joined.last.$2 <= joinGap) {
          final last = joined.removeLast();
          joined.add((last.$1, r.$2 > last.$2 ? r.$2 : last.$2));
        } else {
          joined.add(r);
        }
      }
      for (final (a, b) in joined) {
        final start = a - 2 < 0 ? 0 : a - 2;
        var count = b + 2 - start + 1;
        if (count > ReadStoryTool.maxCount) count = ReadStoryTool.maxCount;
        if (total + count > maxLines) return reads;
        total += count;
        reads.add((storyId: story, start: start, count: count));
      }
    }
    return reads;
  }

  /// What came before a follow-up, for [_planSearches]: the last question
  /// and its answer's opening and headings (not its whole text).
  static String _earlier(LoreConversation? prior, List<Message> history) {
    final messages = prior?.messages ?? history;
    String last(MessageRole role) => messages
        .lastWhere(
          (m) =>
              m.role == role &&
              (m.toolCalls ?? const []).isEmpty &&
              m.content.trim().isNotEmpty,
          orElse: () => Message.user(''),
        )
        .content
        .trim();
    final question = prior?.question ?? last(MessageRole.user);
    if (question.isEmpty) return '';
    final answer = last(MessageRole.assistant);
    final entries = loreAnswerEntries(answer);
    final gist = entries == null
        ? _clip(withoutCitations(answer).replaceAll(RegExp(r'\s+'), ' '), 300)
        : [
            ...entries.where((e) => e.isText).take(1).map((e) => e.text),
            if (entries.any((e) => e.heading != null))
              '小节：${entries.map((e) => e.heading).nonNulls.join('、')}',
          ].join(' ');
    return '上一问：$question${gist.isEmpty ? '' : '\n上一答的要点：$gist'}';
  }

  /// Runs a call that passed the gate. Tool failures come back as text
  /// that starts with “错误”, which the step list shows as a failed step.
  /// What the call shows is noted in [shown] (see [SeenLines.duringCall]).
  Future<String> _runTool(
    AgentTool tool,
    CheckedCall call,
    SeenLines shown,
  ) async {
    try {
      return '${await _span(
        'tool:${call.call.name}',
        () => SeenLines.duringCall(shown, () => tool.execute(call.arguments)),
      )}';
    } catch (e) {
      return '错误：工具 ${call.call.name} 出错（$e）。可以换个参数再试，或换一个工具。';
    }
  }

  /// Moves [transport] to the next way of sending a turn after an empty
  /// reply: streamed native calls → not streamed → tools in the prompt,
  /// streamed → tools in the prompt, not streamed. False when all were
  /// tried.
  bool _nextTransport() {
    final t = transport;
    if (!t.plain && !t.textProtocol) {
      t.plain = true;
    } else if (t.plain && !t.textProtocol) {
      t
        ..plain = false
        ..textProtocol = true;
    } else if (!t.plain) {
      t.plain = true;
    } else {
      return false;
    }
    return true;
  }

  /// One turn without streaming ([AgentTransport.plain]), as deltas.
  Stream<CompletionDelta> _plainTurn(
    List<Message> messages,
    List<Map<String, dynamic>>? tools,
  ) async* {
    final r = await client.chatCompletion(
      messages,
      tools: tools,
      temperature: temperature,
      maxTokens: maxTokens,
    );
    if (r.content.isNotEmpty || r.reasoningContent.isNotEmpty) {
      yield CompletionDelta(
        content: r.content,
        reasoningContent: r.reasoningContent,
      );
    }
    yield CompletionDelta(
      done: true,
      finishReason: r.finishReason,
      promptTokens: r.promptTokens,
      completionTokens: r.completionTokens,
      cachedPromptTokens: r.cachedPromptTokens,
      toolCalls: r.toolCalls,
    );
  }

  /// Why a reply may have been empty, for the record and the error.
  static String _emptyTurnNote(CompletionDelta? done, bool reasoned) {
    final reason = done?.finishReason;
    final hint = switch (reason?.toLowerCase()) {
      'length' || 'max_tokens' => '输出长度上限被用完了，可能都用在了思考上',
      'content_filter' ||
      'safety' ||
      'recitation' ||
      'prohibited_content' ||
      'blocklist' =>
        '服务商的内容审核拦下了回答',
      _ => null,
    };
    return [
      '结束原因：${reason ?? '服务商没有给出'}',
      if (reasoned) '只有思考内容',
      if (hint != null) hint,
    ].join('，');
  }

  /// A failure of the connection itself (no HTTP status): a timeout, a
  /// reset socket, a client closed by the system.
  static bool _isConnectionDrop(LLMException e) =>
      e.statusCode == null &&
      (e.message.contains('timed out') ||
          e.message.contains('Network error') ||
          e.message.contains('Connection'));

  /// Characters kept of a call that found nothing, in the list of those.
  static const int triedBriefChars = 160;

  static String _clip(String text, int max) =>
      text.length <= max ? text : '${text.substring(0, max)}…';

  /// Short description of a call, for the step list and status line.
  static String _describeCall(String name, Map<String, dynamic> args) {
    String arg(String key) => '${args[key] ?? ''}'.trim();
    return switch (name) {
      'search' when arg('query').isEmpty && arg('near').isNotEmpty =>
        '找与 ${_clip(arg('near'), 60)} 相近的段落',
      'search' => '检索“${_clip(arg('query'), 40)}”'
          '${arg('collection').isNotEmpty ? '（${arg('collection')}）' : ''}',
      'sql' => '查询数据库',
      'guide' => '查看知识库手册',
      'grep' => '搜索“${arg('pattern')}”'
          '${arg('collection').isNotEmpty ? '（${arg('collection')}）' : args['story_ids'] is List ? '（${(args['story_ids'] as List).length} 个故事）' : '（全库）'}',
      'read_story' => '阅读 ${arg('story_id').split('/').last}'
          '${arg('start').isEmpty ? '' : ' L${arg('start')} 起'}',
      'outline' => '查看故事集 ${arg('collection')}',
      'similar_names' => '查找与“${arg('name')}”相近的名字',
      'gather' =>
        '按名字取材：${args['names'] is List ? (args['names'] as List).join('、') : arg('names')}',
      'wiki_search' => '在 Wiki 上搜索“${arg('query')}”',
      'wiki_read' => '阅读 Wiki 页面 ${arg('page')}',
      'delegate' => '子任务：${_clip(arg('task'), 40)}',
      _ => name,
    };
  }

  static String _toolList(Iterable<AgentTool> tools) => [
        for (final t in tools)
          '- ${t.name}：${t.description} 参数：${jsonEncode(t.parameters['properties'])}'
              '${(t.parameters['required'] as List?)?.isNotEmpty == true ? '；必填：${(t.parameters['required'] as List).join('、')}' : ''}',
      ].join('\n');

  /// Providers without function calling answer a request with `tools` with
  /// a client error.
  static bool _rejectsTools(LLMException e) {
    final code = e.statusCode;
    if (code != 400 && code != 422) return false;
    final text = '${e.message} ${e.body ?? ''}'.toLowerCase();
    return text.contains('tool') || text.contains('function');
  }

  /// Rewrites native tool-call turns as plain text (after switching to the
  /// text protocol mid-question). Messages already in text form are left
  /// as they are, so this can run every turn.
  static void _convertToTextProtocol(
    List<Message> conversation,
    Set<int> toolResults,
  ) {
    for (var i = 0; i < conversation.length; i++) {
      final m = conversation[i];
      if (m.role == MessageRole.tool) {
        conversation[i] = Message.user('工具结果：\n${m.content}');
      } else if (m.toolCalls != null) {
        final calls = [
          for (final c in m.toolCalls!)
            '```tool\n${jsonEncode({
                  'name': (c['function'] as Map?)?['name'],
                  'arguments': decodeToolArguments(
                    '${(c['function'] as Map?)?['arguments'] ?? ''}',
                  ),
                })}\n```',
        ];
        conversation[i] = Message.assistant(
          [m.content, ...calls].where((s) => s.trim().isNotEmpty).join('\n'),
        );
      }
    }
  }

  static List<ToolCall> _parseTextToolCalls(String content) {
    final calls = <ToolCall>[];
    for (final (i, match) in _textToolCall.allMatches(content).indexed) {
      final decoded = decodeToolArguments(match.group(1)!);
      final name = '${decoded['name'] ?? ''}'.trim();
      if (name.isEmpty) continue;
      final args =
          decoded['arguments'] ?? decoded['parameters'] ?? decoded['args'];
      calls.add(
        ToolCall(
          id: 'text_$i',
          name: name,
          arguments: jsonEncode(args is Map ? args : const {}),
        ),
      );
    }
    return calls;
  }

  /// Folds the oldest tool results to a pointer while the conversation is
  /// over [contextCharBudget] (the recent [_recentKept] messages stay
  /// whole); with [all], every tool result so far (a follow-up question).
  /// Lines a folded result showed stay citable ([SeenLines] keeps them).
  void _foldOldToolResults(
    List<Message> conversation,
    Set<int> toolResults,
    Map<int, String> shownIn, {
    bool all = false,
  }) {
    var size = conversation.fold<int>(0, (n, m) => n + m.content.length);
    if (!all && size <= contextCharBudget) return;
    final target = all ? 0 : contextCharBudget * 7 ~/ 10;
    final limit = all ? conversation.length : conversation.length - _recentKept;
    for (final i in toolResults.toList()..sort()) {
      if (size <= target || i >= limit) break;
      final m = conversation[i];
      if (m.content.startsWith('[已折叠]')) continue;
      final firstLine = m.content.split('\n').first;
      // 0.14: which lines it showed stays; their text does not, and an
      // answer written from memory of it cited the wrong lines.
      final shown = shownIn[i];
      final folded = '[已折叠] 较早的工具结果（${m.content.length} 字）：'
          '${firstLine.length > 120 ? '${firstLine.substring(0, 120)}…' : firstLine}'
          '。${shown == null ? '' : '展示过：$shown。'}'
          '这些行号仍可引用，但原文已不在对话里：要用其中的内容，先重新读取再写。';
      size -= m.content.length - folded.length;
      conversation[i] = m.role == MessageRole.tool
          ? Message.toolResult(m.toolCallId ?? '', folded)
          : Message.user(folded);
    }
  }

  /// Drops a short first paragraph that only narrates the process ("已核实，
  /// 现在输出完整最终答案。"): models write it after a citation re-check even
  /// when told not to. A paragraph with a citation is never dropped.
  static String _dropProcessLeadIn(String body) {
    final cut = body.indexOf('\n\n');
    if (cut < 0) return body;
    final first = body.substring(0, cut).trim();
    if (first.length > 160 ||
        first.startsWith('#') ||
        _citation.hasMatch(first) ||
        _recordCitation.hasMatch(first) ||
        wikiCitationPattern.hasMatch(first) ||
        materialCitationPattern.hasMatch(first) ||
        !_processLeadIn.hasMatch(first)) {
      return body;
    }
    var rest = body.substring(cut).trimLeft();
    // A rule (`---`) under the lead-in goes with it.
    if (rest.startsWith('---')) rest = rest.substring(3).trimLeft();
    return rest.isEmpty ? body : rest;
  }

  static final RegExp _bracketed = RegExp(r'[（(]([^（）()`]+)[)）]');
  static final RegExp _citeSeparator = RegExp(r'[,，、;；\s]+');
  static final RegExp _bareRange = RegExp(r'^L?\d+(?:\s*[-–~]\s*L?\d+)?$');
  static final RegExp _plainCoverage = RegExp(
    r'^\s*coverage\s*[:：]\s*([A-Za-z_]+)\s*$',
    caseSensitive: false,
    multiLine: true,
  );

  /// An answer written as prose instead of the JSON object (0.14 live):
  /// citations in brackets — `（<story>:1-5, 9-12）`, `(record:<id>)` — become
  /// the backticked form the rest of the app reads, and a plain
  /// `coverage: …` line the coverage mark. Brackets holding anything else
  /// are left as they are.
  static String _plainAnswerCites(String body) {
    bool whole(RegExp pattern, String s) {
      final m = pattern.matchAsPrefix(s);
      return m != null && m.end == s.length;
    }

    return body.replaceAllMapped(_bracketed, (m) {
      final refs = <String>[];
      String? story;
      for (final token in m.group(1)!.trim().split(_citeSeparator)) {
        if (token.isEmpty) continue;
        final cite = _citation.matchAsPrefix(token);
        if (cite != null && cite.end == token.length) {
          story = cite.group(1);
          refs.add(token);
        } else if (whole(_recordCitation, token) ||
            whole(wikiCitationPattern, token) ||
            whole(materialCitationPattern, token)) {
          refs.add(token);
        } else if (story != null && _bareRange.hasMatch(token)) {
          refs.add('$story:$token'); // more lines of the story before it
        } else {
          return m.group(0)!;
        }
      }
      return refs.isEmpty
          ? m.group(0)!
          : ' ${refs.map((r) => '`$r`').join(' ')}';
    }).replaceAllMapped(_plainCoverage, (m) => '[COVERAGE: ${m.group(1)}]');
  }

  /// Citations of [body] whose range was shown only in part, each with the
  /// runs inside it that were shown (as citations of their own). A range
  /// shown whole or not at all is left to [_unseenCitations].
  /// [body] with each cited story id that is not one of [read] but is the
  /// file name of exactly one of them written out in full, and what was
  /// written out (`short → full`).
  static (String, List<String>) expandShortStoryIds(
    String body,
    Iterable<String> read,
  ) {
    final known = read.toSet();
    final done = <String>[];
    final out = body.replaceAllMapped(_citation, (m) {
      final id = m.group(1)!;
      if (known.contains(id)) return m.group(0)!;
      final full = [
        for (final s in known)
          if (s.endsWith('/$id')) s,
      ];
      if (full.length != 1) return m.group(0)!;
      final note = '$id → ${full.single}';
      if (!done.contains(note)) done.add(note);
      return '${full.single}${m.group(0)!.substring(id.length)}';
    });
    return (out, done);
  }

  static Map<String, List<String>> _partlySeen(String body, SeenLines seen) {
    final out = <String, List<String>>{};
    void check(String cite, String id, int lo, int hi) {
      if (lo == hi || seen.covers(id, lo, hi)) return;
      final runs = seen.seenRanges(id, lo, hi);
      if (runs.isEmpty) return;
      out[cite] = [
        for (final (a, b) in runs) '$id:${a == b ? '$a' : '$a-$b'}',
      ];
    }

    for (final m in _citation.allMatches(body)) {
      final a = int.parse(m.group(2)!);
      final b = int.tryParse(m.group(3) ?? '') ?? a;
      check(m.group(0)!, m.group(1)!, a <= b ? a : b, a <= b ? b : a);
    }
    for (final m in wikiCitationPattern.allMatches(body)) {
      final (lo, hi) = _wikiRange(m);
      check(m.group(0)!, _wikiPageIdOf(m), lo, hi);
    }
    for (final m in materialCitationPattern.allMatches(body)) {
      final a = int.parse(m[3]!), b = int.tryParse(m[4] ?? '') ?? a;
      check(m[0]!, 'material:${m[1]}@${m[2]}', a <= b ? a : b, a <= b ? b : a);
    }
    return out;
  }

  static int _citationCount(String body) => {
        ..._citation.allMatches(body).map((m) => m.group(0)),
        ..._recordCitation.allMatches(body).map((m) => m.group(0)),
        ...wikiCitationPattern.allMatches(body).map((m) => m.group(0)),
        ...materialCitationPattern.allMatches(body).map((m) => m[0]),
      }.length;

  /// Citations of [body] pointing at lines or records no tool showed in
  /// this conversation.
  static List<String> _unseenCitations(String body, SeenLines seen) {
    final unseen = <String>{};
    for (final m in _citation.allMatches(body)) {
      final storyId = m.group(1)!;
      final a = int.parse(m.group(2)!);
      final b = int.tryParse(m.group(3) ?? '') ?? a;
      final (lo, hi) = a <= b ? (a, b) : (b, a);
      if (!seen.covers(storyId, lo, hi)) unseen.add(m.group(0)!);
    }
    for (final m in _recordCitation.allMatches(body)) {
      if (!seen.hasRecord(m.group(1)!)) unseen.add(m.group(0)!);
    }
    // 0.13: wiki paragraphs are recorded under their page id.
    for (final m in wikiCitationPattern.allMatches(body)) {
      final (lo, hi) = _wikiRange(m);
      if (!seen.covers(_wikiPageIdOf(m), lo, hi)) unseen.add(m.group(0)!);
    }
    for (final m in materialCitationPattern.allMatches(body)) {
      final a = int.parse(m[3]!), b = int.tryParse(m[4] ?? '') ?? a;
      if (!seen.covers(
          'material:${m[1]}@${m[2]}', a <= b ? a : b, a <= b ? b : a,)) {
        unseen.add(m[0]!);
      }
    }
    return unseen.toList()..sort();
  }

  /// The page id of a [wikiCitationPattern] match.
  static String _wikiPageIdOf(RegExpMatch m) =>
      '$wikiIdPrefix${m.group(1)}:${m.group(2)}@${m.group(3)}';

  /// The paragraph range of a [wikiCitationPattern] match.
  static (int, int) _wikiRange(RegExpMatch m) {
    final a = int.parse(m.group(4)!);
    final b = int.tryParse(m.group(5) ?? '') ?? a;
    return a <= b ? (a, b) : (b, a);
  }

  /// Story files cited without line numbers (`` `….txt` ``).
  static List<String> _bareStoryCitations(String body) => {
        for (final m in _bareStoryCitation.allMatches(body)) m.group(1)!,
      }.toList()
        ..sort();
}

/// Words of a lead-in that talks about the answering process.
final RegExp _processLeadIn = RegExp(
  r'核实|核对|重新输出|最终答案|完整答案|信息(已经)?足够|足够(的)?信息|已经掌握|'
  r'(下面|以下|现在)(给出|回答|输出|作答|是答案)|整理(一下)?答案|让我(先|再)?(确认|查|看)|'
  // Talk about the tools themselves (R17b).
  r'\b(search|grep|sql|guide|read_story|find|outline|similar_names|delegate|wiki_search|wiki_read)\b',
);

/// `record:<id>` — a non-story record (R17).
final RegExp _recordCitation = RegExp(r'record:([\w\-]+(?:/[\w\-]+)*)');

/// `record:record:<id>`, which models write when the id is shown as
/// `record:<id>` (0.14).
final RegExp _doubledRecordPrefix = RegExp(r'record:(?:record:)+');

/// A backticked story file with no line number after it.
final RegExp _bareStoryCitation = RegExp(r'`([\w\-/\.\[\]]+\.txt)`');
