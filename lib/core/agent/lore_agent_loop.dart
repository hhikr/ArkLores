/// R17: the story agent — one model, general tools, an append-only
/// conversation.
///
/// General agents given only the knowledge DB answered story questions far
/// better than the R13–R16 planner pipeline (`logs/成熟的agent如何处理/`).
/// What they shared, and what this loop keeps:
/// - the model that reads the text writes the answer (no digests, no
///   separate writer choosing excerpts);
/// - expressive tools: read-only SQL over the whole corpus, whole-chapter
///   reads, grep with context (`lore_tools.dart`);
/// - an append-only message list, so providers serve most of each request
///   from their prompt cache;
/// - no hand-written progress rules — only a turn limit, a context budget
///   (oldest tool results folded) and one citation check at the end.
///
/// Every story question takes this same path (R13), with one prompt.
library;

import 'dart:async';
import 'dart:convert';

import '../gamedata/game_retrieval.dart';
import '../gamedata/multi_game_retrieval.dart';
import '../llm/embedding_client.dart';
import '../llm/llm_client.dart';
import '../wiki/wiki_lookup.dart';
import '../wiki/wiki_page.dart';
import 'lore_agent_prompts.dart';
import 'lore_answer_json.dart';
import 'lore_answer_stages.dart';
import 'lore_tools.dart';
import 'react_event.dart';
import 'story_answer.dart';
import 'tools/agent_tool.dart';
import 'tools/wiki_tools.dart';

/// The messages and seen lines of a conversation, carried into follow-up
/// questions so they continue with the text already read.
class LoreConversation {
  LoreConversation({List<Message>? messages, SeenLines? seen})
      : messages = messages ?? [],
        seen = seen ?? SeenLines();

  /// Everything after the system prompt: questions, tool calls, tool
  /// results and answers.
  final List<Message> messages;
  final SeenLines seen;
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
/// calls; a provider that answers a turn with nothing at all is asked again
/// without streaming ([plain]: some relays break streams or do not stream),
/// then with tools described in the prompt ([textProtocol]: tool calls
/// dropped or malformed). Shared with the sub-agents of the same question,
/// so they start with what worked.
class AgentTransport {
  bool plain = false;
  bool textProtocol = false;
}

class LoreAgentLoop {
  LoreAgentLoop({
    required this.client,
    required this.store,
    this.embeddingClient,
    this.wiki,
    this.maxTurns = 60,
    this.contextCharBudget = 360000,
    this.maxTokens = 8192,
    this.temperature = 0.3,
    this.subtask = false,
    this.subtaskMaxTurns = 20,
    this.review = true,
    this.digest = true,
    this.stageMinEntries = 5,
    this.streamRetryDelay = const Duration(seconds: 2),
    this.onSpan,
    AgentTransport? transport,
  }) : transport = transport ?? AgentTransport();

  /// How turns are sent (see [AgentTransport]); changes when a provider
  /// answers with nothing.
  final AgentTransport transport;

  /// Measurement only: called when a tool run or a local check (citation
  /// text lookup, catalog lookup) finishes, with its name and wall-clock
  /// start and end. Never changes behaviour.
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

  final LLMClient client;
  final GameDataRetrieval store;

  /// Optional story vectors for `find` (R12); keyword-only without.
  final EmbeddingClient? embeddingClient;

  /// 0.13: the games' wikis (`wiki_search`, `wiki_read`, a third kind of
  /// citation); null leaves them out of the tools and the prompt.
  final WikiLookup? wiki;

  /// A sub-agent run by `delegate`: its own conversation, no `delegate`
  /// tool, findings instead of a full answer.
  final bool subtask;

  /// Turn limit of each sub-agent.
  final int subtaskMaxTurns;

  /// R18: a second model reads the main agent's answer as a reader and
  /// raises questions the main agent checks in the text (once per
  /// question).
  final bool review;

  /// R18: whether a long answer is reorganised (see [stageMinEntries]).
  final bool digest;

  /// R18: a JSON answer with at least this many text entries is
  /// reorganised into a few paragraphs, the detailed answer kept below.
  final int stageMinEntries;

  /// Model turns per question; the last one must answer.
  final int maxTurns;

  /// Characters of conversation kept whole; past it the oldest tool results
  /// are folded to a one-line pointer (re-read when needed).
  final int contextCharBudget;
  final int maxTokens;
  final double temperature;

  /// Messages kept whole at the end of the conversation when folding.
  static const int _recentKept = 8;

  Stream<ReActEvent> run({
    required String query,
    List<Message> history = const [],
    LoreConversation? prior,
    void Function(LoreConversation conversation)? onConversation,
    void Function(int turn, String rawResponse)? onRawLlmResponse,
  }) async* {
    final seen = prior?.seen ?? SeenLines();
    // 0.12: the prompt describes every installed game's library.
    final games = store is MultiGameRetrieval
        ? await (store as MultiGameRetrieval).installedGames()
        : const [Game.arknights];
    final tools = {
      for (final t in [
        ...loreTools(store, seen, embeddingClient: embeddingClient),
        if (wiki != null) ...wikiTools(wiki!, seen),
        if (!subtask) DelegateTool((args) => _runSubtask(args, seen)),
      ])
        t.name: t,
    };
    final toolSpecs = [for (final t in tools.values) t.toJson()];
    // Whether [conversation] is written in the text protocol (a sub-agent
    // may switch [transport] while this conversation still has native
    // calls).
    var converted = false;

    String systemPrompt() {
      final base =
          loreSystemPrompt(subtask: subtask, games: games, wiki: wiki != null);
      return transport.textProtocol
          ? '$base\n\n${loreTextToolProtocol(_toolList(tools.values))}'
          : base;
    }

    final conversation = <Message>[
      if (prior != null)
        ...prior.messages
      else
        ...history,
      Message.user(query),
    ];
    // Indexes (in [conversation]) of tool results that may be folded.
    final toolResults = <int>{
      for (final (i, m) in conversation.indexed)
        if (m.role == MessageRole.tool) i,
    };

    var citationRetried = false;
    var reviewed = false;
    var nudged = false;
    // R18: the answer last sent back for a rewrite (citation recheck or
    // reader review); kept if the rewrite never comes.
    String? rewriteOf;
    var hitTurnLimit = false;
    // Session-record index (one per tool call, see onRawLlmResponse).
    var record = 0;
    var streamRetries = 0;

    for (var turn = 1; turn <= maxTurns; turn++) {
      final lastTurn = turn == maxTurns;
      // (Once: an empty last turn may be sent again another way.)
      if (lastTurn && !hitTurnLimit) {
        hitTurnLimit = true;
        conversation.add(Message.user(
          '已到检索轮数上限，不能再调用工具。请根据目前读到的原文给出最终答案，'
          '并说明还有哪些部分没有查到或没有读完。',
        ),);
      }
      if (transport.textProtocol && !converted) {
        converted = true;
        _convertToTextProtocol(conversation, toolResults);
      }
      _foldOldToolResults(conversation, toolResults);
      yield ReActEvent(
        type: ReActEventType.status,
        content: turn == 1 ? '正在查阅知识库…' : '第 $turn 轮 · 思考中',
      );

      final text = StringBuffer();
      final reasoning = StringBuffer();
      var answerOpen = false;
      // R17c: the main agent answers in JSON, shown as markdown while it
      // streams.
      LoreAnswerStream? jsonAnswer;
      CompletionDelta? done;
      try {
        final messages = [Message.system(systemPrompt()), ...conversation];
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
        await for (final delta in stream) {
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
                    content: '整理答案',
                  );
                }
                answerOpen = true;
                jsonAnswer = LoreAnswerStream();
                // R18: the detailed answer streams under the marker (folded
                // in the app); the reorganised one is written above it.
                live = '$loreDetailsMarker\n\n'
                    '${jsonAnswer.add(text.toString().substring(start.start))}';
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
            } else if (text.length >= 160 &&
                !text.toString().contains('```')) {
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
        if (!transport.textProtocol && _rejectsTools(e)) {
          // The provider has no function calling: switch to plain-text tool
          // calls and ask again.
          transport.textProtocol = true;
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
            content: '连接中断，正在重试（$streamRetries/$_maxStreamRetries）',
          );
          await Future<void>.delayed(streamRetryDelay * streamRetries);
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
                ? '服务商的回复无法读取，改用文本方式调用工具重试'
                : '服务商的回复无法读取，改用非流式请求重试',
          );
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
      // turn — a broken stream, a body that is not a stream, tool calls it
      // could not write. The same turn is sent again without streaming,
      // then with the tools described in the prompt (streamed, then not).
      if (content.trim().isEmpty && calls.isEmpty && _nextTransport()) {
        onRawLlmResponse?.call(
          ++record,
          '（空回复：${_emptyTurnNote(done, reasoning.isNotEmpty)}）',
        );
        yield ReActEvent(
          type: ReActEventType.status,
          content: transport.textProtocol
              ? '服务商没有返回内容，改用文本方式调用工具重试'
              : '服务商没有返回内容，改用非流式请求重试',
        );
        turn--;
        continue;
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
          yield ReActEvent(type: ReActEventType.thought, content: content.trim());
        }
        if (transport.textProtocol) {
          conversation.add(Message.assistant(text.toString()));
        } else {
          conversation.add(Message.assistantToolCalls(
            content,
            calls,
            reasoningContent: reasoning.isEmpty ? null : reasoning.toString(),
          ),);
        }
        // All calls of a turn run at once (sub-agents in parallel); events
        // and tool messages still follow the calls' order.
        final args = [for (final c in calls) decodeToolArguments(c.arguments)];
        final results = [
          for (final (k, call) in calls.indexed)
            _runTool(tools[call.name], call, args[k], tools.keys),
        ];
        final delegates = calls.where((c) => c.name == 'delegate').length;
        for (final (k, call) in calls.indexed) {
          onRawLlmResponse?.call(
            ++record,
            k == 0
                ? '$content\n${jsonEncode([for (final c in calls) c.toJson()])}'
                    .trim()
                : '（第 $turn 轮的第 ${k + 1} 个调用）',
          );
          final label = _describeCall(call.name, args[k]);
          yield ReActEvent(
            type: ReActEventType.toolCall,
            content: label,
            toolName: call.name,
            toolArgs: args[k],
          );
          yield ReActEvent(
            type: ReActEventType.status,
            content: delegates > 1
                ? '第 $turn 轮 · $delegates 个子任务并行查阅中'
                : '第 $turn 轮 · $label',
          );
          final result = await results[k];
          yield ReActEvent(
            type: ReActEventType.toolObservation,
            content: result,
            toolName: call.name,
          );
          toolResults.add(conversation.length);
          conversation.add(
            transport.textProtocol
                ? Message.user('工具结果（${call.name}）：\n$result')
                : Message.toolResult(call.id, result),
          );
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
          !subtask &&
          !loreAnswerJsonStart.hasMatch(content) &&
          _citationCount(content) == 0) {
        if (!nudged && !lastTurn) {
          nudged = true;
          if (answerOpen) {
            yield const ReActEvent(
              type: ReActEventType.finalAnswerReset,
              content: '继续作答',
            );
          }
          conversation
            ..add(Message.assistant(content))
            ..add(Message.user(
              '这不是最终答案。请直接输出完整的最终答案（按要求的格式），不要描述核对过程。',
            ),);
          continue;
        }
        content = rewriteOf;
      }
      final parsedJson = subtask ? null : loreAnswerParsed(content);
      final fromJson = parsedJson?.markdown;
      // A flat or odd citation shape is written back in the nested form, so
      // later turns (rewrite, follow-ups) do not copy it.
      final keep = fromJson == null ? content : normalizeAnswerCites(content);
      var body = (fromJson ?? content).trim().replaceAllMapped(
            RegExp(r'(\.txt\s*[:：]\s*)L(\d+)(\s*[-–~]\s*)?L?(\d+)?'),
            (m) => '${m.group(1)}${m.group(2)}'
                '${m.group(4) == null ? '' : '${m.group(3) ?? '-'}${m.group(4)}'}',
          );
      if (body.isEmpty) {
        if (!nudged && !lastTurn) {
          nudged = true;
          conversation.add(Message.user('请继续：需要查资料就调用工具，否则给出最终答案。'));
          continue;
        }
        yield ReActEvent(
          type: ReActEventType.error,
          content: '模型没有给出答案（${_emptyTurnNote(done, reasoning.isNotEmpty)}）。'
              '${transport.plain && transport.textProtocol ? '已换用非流式请求和文本方式调用工具重试，仍然没有内容。' : ''}',
        );
        return;
      }

      final unseen = _unseenCitations(body, seen);
      final bare = _bareStoryCitations(body);
      // R17c: quoted passages copied from the cited lines (the answer should
      // retell, not quote dialogue); checked once, with the citations.
      final copied = citationRetried || lastTurn || subtask
          ? const <String>[]
          : quotedSourceLines(
              body,
              await _span('cited_text', () => _citedText(body)),
            );
      // Citations written in a shape that cannot be read are lost from the
      // answer: either some items gave no ref, or the model read lines but
      // not one citation came out.
      final unreadable = parsedJson != null &&
          (parsedJson.dropped > 0 ||
              (!seen.isEmpty && _citationCount(body) == 0));
      if ((unseen.isNotEmpty ||
              bare.isNotEmpty ||
              copied.isNotEmpty ||
              unreadable) &&
          !citationRetried &&
          !lastTurn) {
        citationRetried = true;
        rewriteOf = keep;
        yield ReActEvent(
          type: ReActEventType.finalAnswerReset,
          content: unseen.isEmpty && bare.isEmpty && !unreadable
              ? '改写引语'
              : '核对出处',
        );
        conversation
          ..add(Message.assistant(keep))
          ..add(Message.user([
            if (unreadable)
              '答案里有出处的写法无法识别。cite 必须是数组的数组，每个出处自己一对方括号，'
                  '例如 [["<story_id>", <起始行>, <结束行>], ["record", "<记录 id>"]]；'
                  'story_id 与工具输出完全一致（含 .txt），行号是整数。',
            if (unseen.isNotEmpty)
              '下面这些出处不在你本次通过工具实际看到的行或记录里：${unseen.join('、')}。'
                  '请先读取核实（或找到真正的出处），无法核实的内容请删掉。',
            if (bare.isNotEmpty)
              '下面这些出处只有文件名、没有行号：${bare.join('、')}。'
                  '请用 read_story 或带范围的 grep 找到具体行，写明起始行和结束行。',
            if (copied.isNotEmpty)
              '下面这些引号里的文字照搬了原文台词：${copied.map((q) => '“$q”').join('、')}。'
                  '请改用自己的话转述，不要用引号引用台词。',
            '然后重新输出完整的最终答案${fromJson == null ? '' : '（同样的 JSON 格式）'}；'
                '最终答案只写答案本身，不要提核对过程。',
          ].join('\n'),),);
        continue;
      }

      // R18: a reader's review. Its questions go back to the main agent,
      // which checks them in the text and writes the answer again (with
      // its own citation check).
      if (review && !subtask && !reviewed && !lastTurn) {
        reviewed = true;
        yield const ReActEvent(
          type: ReActEventType.status,
          content: '审稿中',
        );
        final issues = await _review(
          query,
          body.replaceAll(_coverageLine, '').trim(),
          (raw) => onRawLlmResponse?.call(++record, '（审稿）$raw'),
        );
        if (issues.isNotEmpty) {
          yield ReActEvent(
            type: ReActEventType.finalAnswerReset,
            content: '审稿提出 ${issues.length} 个问题，正在核实',
          );
          yield ReActEvent(
            type: ReActEventType.thought,
            content: [
              '读者审稿：',
              for (final (i, issue) in issues.indexed) '${i + 1}. $issue',
            ].join('\n'),
          );
          rewriteOf = keep;
          conversation
            ..add(Message.assistant(keep))
            ..add(Message.user(
              loreReviewFollowUp(issues, json: fromJson != null),
            ),);
          citationRetried = false;
          continue;
        }
      }

      body = _dropProcessLeadIn(body);
      final coverageWord = _coverageLine.firstMatch(body)?.group(1);
      final coverage = coverageWord == null ? null : _coverageOf(coverageWord);
      body = body.replaceAll(_coverageLine, '').trim();
      if (unseen.isNotEmpty) {
        body = '$body\n\n> 以下出处未能在本次读到的原文中核实：'
            '${unseen.map((c) => '`$c`').join('、')}';
      }
      if (done?.finishReason == 'length') {
        body = '$body\n\n> 注意：答案达到长度上限，可能不完整。';
      }
      final verified = _citationCount(body) - unseen.length;
      // The model's own text (JSON) stays in the conversation, so a
      // follow-up sees the format it is asked for.
      conversation.add(Message.assistant(fromJson == null ? body : keep));

      // R18: reorganise a long JSON answer into a few paragraphs; the
      // detailed answer stays below the marker.
      final entries = !digest || fromJson == null || subtask || lastTurn
          ? null
          : loreAnswerEntries(content);
      if (entries != null &&
          entries.where((e) => e.isText).length >= stageMinEntries) {
        final checked = [
          for (final e in entries)
            LoreAnswerEntry(
              heading: e.heading,
              text: e.text,
              cites: [
                for (final c in e.cites)
                  if (!unseen.contains(c)) c,
              ],
            ),
        ];
        String? staged;
        await for (final event in _stage(
          checked,
          detail: body,
          conversation: conversation,
          systemPrompt: systemPrompt(),
          tools: transport.textProtocol ? null : toolSpecs,
          onRaw: (raw) => onRawLlmResponse?.call(++record, '（整理）$raw'),
          onStaged: (markdown) => staged = markdown,
        )) {
          yield event;
        }
        if (staged != null) body = '$staged\n\n$loreDetailsMarker\n\n$body';
      }

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
      onConversation?.call(
        LoreConversation(messages: List.of(conversation), seen: seen),
      );
      yield ReActEvent(
        type: ReActEventType.finalAnswerReplace,
        content: '${formatStoryAnswerEnvelope(status)}\n$body',
      );
      yield const ReActEvent(type: ReActEventType.complete);
      return;
    }
  }

  /// R18: the reviewer's questions about [answer] (empty when it has none
  /// or the call fails — a failed review never blocks the answer).
  Future<List<String>> _review(
    String query,
    String answer,
    void Function(String raw) onRaw,
  ) async {
    try {
      final ids = <String>{
        for (final m in _citation.allMatches(answer)) m.group(1)!,
      };
      final catalog =
          ids.isEmpty
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
          Message.system(loreReviewPrompt),
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

  /// R18: one more turn of the main conversation (no tools) that groups
  /// [entries] into a few paragraphs. Streams the paragraphs above the
  /// detailed answer ([detail]) as they are written; [onStaged] gets the
  /// final markdown with merged citations, or nothing on any failure (only
  /// the detailed answer is shown then). The request and reply are not
  /// kept in [conversation]: a follow-up continues after the detailed JSON
  /// answer, the format it is asked to write.
  Stream<ReActEvent> _stage(
    List<LoreAnswerEntry> entries, {
    required String detail,
    required List<Message> conversation,
    required String systemPrompt,
    required List<Map<String, dynamic>>? tools,
    required void Function(String raw) onRaw,
    required void Function(String markdown) onStaged,
  }) async* {
    final count = entries.where((e) => e.isText).length;
    yield const ReActEvent(type: ReActEventType.status, content: '整理答案');
    final prompt = Message.user(loreStagePrompt(numberedEntries(entries)));
    final text = StringBuffer();
    var shown = 0;
    try {
      final messages = [Message.system(systemPrompt), ...conversation, prompt];
      final stream = transport.plain
          ? _plainTurn(messages, tools)
          : client.streamTurn(
              messages,
              tools: tools,
              toolChoice: tools == null ? null : 'none',
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
  /// saw counts as seen here, so its checked citations can be reused.
  Future<String> _runSubtask(
    Map<String, dynamic> args,
    SeenLines parentSeen,
  ) async {
    final task = delegateTaskText(args);
    if (task.trim().isEmpty) return '错误：task 为空';
    final childSeen = SeenLines();
    final events = await LoreAgentLoop(
      client: client,
      store: store,
      embeddingClient: embeddingClient,
      wiki: wiki,
      maxTurns: subtaskMaxTurns,
      contextCharBudget: contextCharBudget,
      maxTokens: maxTokens,
      temperature: temperature,
      subtask: true,
      onSpan: onSpan,
      transport: transport,
    )
        .run(
          query: task,
          prior: LoreConversation(seen: childSeen),
        )
        .toList();
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

  Future<String> _runTool(
    AgentTool? tool,
    ToolCall call,
    Map<String, dynamic> args,
    Iterable<String> available,
  ) async {
    if (tool == null) {
      return '没有名为 ${call.name} 的工具。可用：${available.join('、')}。';
    }
    if (args.isEmpty && call.arguments.trim().isNotEmpty) {
      final empty = _isEmptyJsonObject(call.arguments);
      return empty
          ? '缺少参数：${call.name} 需要的参数见工具说明。'
          : '参数不是合法的 JSON：${call.arguments}';
    }
    try {
      return '${await _span('tool:${call.name}', () => tool.execute(args))}';
    } catch (e) {
      return '工具出错：$e';
    }
  }

  /// A failure of the connection itself (no HTTP status): a timeout, a
  /// reset socket, a client closed by the system.
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

  static bool _isConnectionDrop(LLMException e) =>
      e.statusCode == null &&
      (e.message.contains('timed out') ||
          e.message.contains('Network error') ||
          e.message.contains('Connection'));

  static bool _isEmptyJsonObject(String raw) {
    try {
      final v = jsonDecode(raw);
      return v is Map && v.isEmpty;
    } on FormatException {
      return false;
    }
  }

  /// Short description of a call, for the step list and status line.
  static String _describeCall(String name, Map<String, dynamic> args) {
    String arg(String key) => '${args[key] ?? ''}'.trim();
    return switch (name) {
      'sql' => '查询数据库',
      'grep' => '搜索“${arg('pattern')}”'
          '${arg('collection').isNotEmpty ? '（${arg('collection')}）' : args['story_ids'] is List ? '（${(args['story_ids'] as List).length} 个故事）' : '（全库）'}',
      'read_story' => '阅读 ${arg('story_id').split('/').last}'
          '${arg('start').isEmpty ? '' : ' L${arg('start')} 起'}',
      'outline' => '查看故事集 ${arg('collection')}',
      'similar_names' => '查找与“${arg('name')}”相近的名字',
      'wiki_search' => '在 Wiki 上搜索“${arg('query')}”',
      'wiki_read' => '阅读 Wiki 页面 ${arg('page')}',
      'delegate' => '子任务：${arg('task').length > 40 ? '${arg('task').substring(0, 40)}…' : arg('task')}',
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
  /// text protocol mid-question).
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
      final args = decoded['arguments'] ?? decoded['parameters'] ?? decoded['args'];
      calls.add(ToolCall(
        id: 'text_$i',
        name: name,
        arguments: jsonEncode(args is Map ? args : const {}),
      ),);
    }
    return calls;
  }

  /// Folds the oldest tool results to a pointer while the conversation is
  /// over [contextCharBudget] (the recent [_recentKept] messages stay whole).
  void _foldOldToolResults(List<Message> conversation, Set<int> toolResults) {
    var size = conversation.fold<int>(0, (n, m) => n + m.content.length);
    if (size <= contextCharBudget) return;
    final target = contextCharBudget * 7 ~/ 10;
    final limit = conversation.length - _recentKept;
    for (final i in toolResults.toList()..sort()) {
      if (size <= target || i >= limit) break;
      final m = conversation[i];
      if (m.content.startsWith('[已折叠]')) continue;
      final firstLine = m.content.split('\n').first;
      final folded = '[已折叠] 较早的工具结果（${m.content.length} 字）：'
          '${firstLine.length > 120 ? '${firstLine.substring(0, 120)}…' : firstLine}'
          '。需要其中内容时请重新调用工具。';
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
        !_processLeadIn.hasMatch(first)) {
      return body;
    }
    var rest = body.substring(cut).trimLeft();
    // A rule (`---`) under the lead-in goes with it.
    if (rest.startsWith('---')) rest = rest.substring(3).trimLeft();
    return rest.isEmpty ? body : rest;
  }

  /// Text of the story lines [body] cites (R17c quote check).
  Future<String> _citedText(String body) async {
    final out = StringBuffer();
    for (final m in _citation.allMatches(body)) {
      final a = int.parse(m.group(2)!);
      final b = int.tryParse(m.group(3) ?? '') ?? a;
      final (lo, hi) = a <= b ? (a, b) : (b, a);
      try {
        final page = await store.readStoryLines(
          storyId: m.group(1)!,
          startLine: lo,
          endLine: hi,
          maxLines: (hi - lo + 1).clamp(1, 500),
        );
        for (final line in page.lines) {
          out.writeln(line.content);
        }
      } catch (_) {
        // A citation that cannot be read is reported by the citation check.
      }
    }
    // 0.13: cited wiki paragraphs (the version the agent read is kept).
    final wiki = this.wiki;
    if (wiki != null) {
      for (final m in wikiCitationPattern.allMatches(body)) {
        final page = await wiki.snapshot(_wikiPageIdOf(m));
        if (page == null) continue;
        final (lo, hi) = _wikiRange(m);
        for (final (_, block) in page.range(lo, hi)) {
          out.writeln(block.text);
        }
      }
    }
    return out.toString();
  }

  static int _citationCount(String body) => {
        ..._citation.allMatches(body).map((m) => m.group(0)),
        ..._recordCitation.allMatches(body).map((m) => m.group(0)),
        ...wikiCitationPattern.allMatches(body).map((m) => m.group(0)),
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
  r'\b(grep|sql|read_story|find|outline|similar_names|delegate|wiki_search|wiki_read)\b',
);

/// `record:<id>` — a non-story record (R17).
final RegExp _recordCitation = RegExp(r'record:([\w\-]+(?:/[\w\-]+)*)');

/// A backticked story file with no line number after it.
final RegExp _bareStoryCitation = RegExp(r'`([\w\-/\.\[\]]+\.txt)`');
