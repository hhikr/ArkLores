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
/// Every story question takes this same path (R13); [AnswerStyle] changes
/// only the output format.
library;

import 'dart:async';
import 'dart:convert';

import '../gamedata/game_retrieval.dart';
import '../llm/embedding_client.dart';
import '../llm/llm_client.dart';
import 'lore_agent_prompts.dart';
import 'lore_tools.dart';
import 'react_event.dart';
import 'story_answer.dart';
import 'tools/agent_tool.dart';

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
    RegExp(r'\[COVERAGE:\s*(full|gaps)\s*\]', caseSensitive: false);

/// A plain-text tool call (providers without function calling).
final RegExp _textToolCall = RegExp(r'```tool\s*([\s\S]*?)```');

class LoreAgentLoop {
  LoreAgentLoop({
    required this.client,
    required this.store,
    this.embeddingClient,
    this.maxTurns = 60,
    this.contextCharBudget = 360000,
    this.maxTokens = 8192,
    this.temperature = 0.3,
    this.subtask = false,
    this.subtaskMaxTurns = 20,
  });

  final LLMClient client;
  final GameDataRetrieval store;

  /// Optional story vectors for `find` (R12); keyword-only without.
  final EmbeddingClient? embeddingClient;

  /// A sub-agent run by `delegate`: its own conversation, no `delegate`
  /// tool, findings instead of a full answer.
  final bool subtask;

  /// Turn limit of each sub-agent.
  final int subtaskMaxTurns;

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
    required AnswerStyle style,
    List<Message> history = const [],
    LoreConversation? prior,
    void Function(LoreConversation conversation)? onConversation,
    void Function(int turn, String rawResponse)? onRawLlmResponse,
  }) async* {
    final seen = prior?.seen ?? SeenLines();
    final tools = {
      for (final t in [
        ...loreTools(store, seen, embeddingClient: embeddingClient),
        if (!subtask) DelegateTool((args) => _runSubtask(args, seen)),
      ])
        t.name: t,
    };
    final toolSpecs = [for (final t in tools.values) t.toJson()];
    var textProtocol = false;

    String systemPrompt() {
      final base = loreSystemPrompt(style, subtask: subtask);
      return textProtocol
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
    var nudged = false;
    var hitTurnLimit = false;
    // Session-record index (one per tool call, see onRawLlmResponse).
    var record = 0;

    for (var turn = 1; turn <= maxTurns; turn++) {
      final lastTurn = turn == maxTurns;
      if (lastTurn) {
        hitTurnLimit = true;
        conversation.add(Message.user(
          '已到检索轮数上限，不能再调用工具。请根据目前读到的原文给出最终答案，'
          '并说明还有哪些部分没有查到或没有读完。',
        ),);
      }
      _foldOldToolResults(conversation, toolResults);
      yield ReActEvent(
        type: ReActEventType.status,
        content: turn == 1 ? '正在查阅知识库…' : '第 $turn 轮 · 思考中',
      );

      final text = StringBuffer();
      final reasoning = StringBuffer();
      var answerOpen = false;
      CompletionDelta? done;
      try {
        final messages = [Message.system(systemPrompt()), ...conversation];
        final stream = client.streamTurn(
          messages,
          tools: textProtocol ? null : toolSpecs,
          toolChoice: lastTurn && !textProtocol ? 'none' : null,
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
            // Narration before a tool call is short; longer text with no
            // tool block is the answer, streamed as it comes.
            if (answerOpen) {
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
        if (!textProtocol && _rejectsTools(e)) {
          // The provider has no function calling: switch to plain-text tool
          // calls and ask again.
          textProtocol = true;
          _convertToTextProtocol(conversation, toolResults);
          turn--;
          continue;
        }
        yield ReActEvent(type: ReActEventType.error, content: e.message);
        return;
      } catch (e) {
        yield ReActEvent(type: ReActEventType.error, content: '$e');
        return;
      }

      var content = text.toString();
      var calls = done?.toolCalls ?? const <ToolCall>[];
      if (calls.isEmpty) {
        final parsed = _parseTextToolCalls(content);
        if (parsed.isNotEmpty) {
          calls = parsed;
          content = content.replaceAll(_textToolCall, '').trim();
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
          yield ReActEvent(type: ReActEventType.thought, content: content.trim());
        }
        if (textProtocol) {
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
            _runTool(tools[call.name], call, args[k]),
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
            textProtocol
                ? Message.user('工具结果（${call.name}）：\n$result')
                : Message.toolResult(call.id, result),
          );
        }
        continue;
      }

      // A final answer. `story_id:L12-L40` is written without the L, the
      // form the citation display reads.
      var body = content.trim().replaceAllMapped(
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
        yield const ReActEvent(
          type: ReActEventType.error,
          content: '模型没有给出答案。',
        );
        return;
      }

      final unseen = _unseenCitations(body, seen);
      final bare = _bareStoryCitations(body);
      if ((unseen.isNotEmpty || bare.isNotEmpty) &&
          !citationRetried &&
          !lastTurn) {
        citationRetried = true;
        yield const ReActEvent(
          type: ReActEventType.finalAnswerReset,
          content: '核对出处',
        );
        conversation
          ..add(Message.assistant(body))
          ..add(Message.user([
            if (unseen.isNotEmpty)
              '下面这些出处不在你本次通过工具实际看到的行或记录里：${unseen.join('、')}。'
                  '请先读取核实（或找到真正的出处），无法核实的内容请删掉。',
            if (bare.isNotEmpty)
              '下面这些出处只有文件名、没有行号：${bare.join('、')}。'
                  '请用 read_story 或带范围的 grep 找到具体行，写成 story_id:起始行-结束行。',
            '然后重新输出完整的最终答案；最终答案只写答案本身，不要提核对过程。',
          ].join('\n'),),);
        continue;
      }

      body = _dropProcessLeadIn(body);
      final coverage =
          _coverageLine.firstMatch(body)?.group(1)?.toLowerCase();
      body = body.replaceAll(_coverageLine, '').trim();
      if (unseen.isNotEmpty) {
        body = '$body\n\n> 以下出处未能在本次读到的原文中核实：'
            '${unseen.map((c) => '`$c`').join('、')}';
      }
      if (done?.finishReason == 'length') {
        body = '$body\n\n> 注意：答案达到长度上限，可能不完整。';
      }
      final verified = _citationCount(body) - unseen.length;
      if (style == AnswerStyle.factCheck) {
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
      conversation.add(Message.assistant(body));
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
      maxTurns: subtaskMaxTurns,
      contextCharBudget: contextCharBudget,
      maxTokens: maxTokens,
      temperature: temperature,
      subtask: true,
    )
        .run(
          query: task,
          style: AnswerStyle.answer,
          prior: LoreConversation(seen: childSeen),
        )
        .toList();
    final error = events.where((e) => e.type == ReActEventType.error);
    if (error.isNotEmpty) return '子任务出错：${error.first.content}';
    parentSeen.addAll(childSeen);
    final findings = finalAnswerOf(events)
        .replaceFirst(storyAnswerEnvelopePattern, '')
        .trim();
    return '子任务结果（出处已核对，可直接引用）：\n$findings';
  }

  Future<String> _runTool(
    AgentTool? tool,
    ToolCall call,
    Map<String, dynamic> args,
  ) async {
    if (tool == null) {
      return '没有名为 ${call.name} 的工具。可用：sql、grep、read_story、find、outline、similar_names'
          '${subtask ? '' : '、delegate'}。';
    }
    if (args.isEmpty && call.arguments.trim().isNotEmpty) {
      return '参数不是合法的 JSON：${call.arguments}';
    }
    try {
      return '${await tool.execute(args)}';
    } catch (e) {
      return '工具出错：$e';
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
      'delegate' => '子任务：${arg('task').length > 40 ? '${arg('task').substring(0, 40)}…' : arg('task')}',
      _ => name,
    };
  }

  static String _toolList(Iterable<AgentTool> tools) => [
        for (final t in tools)
          '- ${t.name}：${t.description} 参数：${jsonEncode(t.parameters['properties'])}',
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
      final args = decoded['arguments'];
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
        !_processLeadIn.hasMatch(first)) {
      return body;
    }
    var rest = body.substring(cut).trimLeft();
    // A rule (`---`) under the lead-in goes with it.
    if (rest.startsWith('---')) rest = rest.substring(3).trimLeft();
    return rest.isEmpty ? body : rest;
  }

  static int _citationCount(String body) => {
        ..._citation.allMatches(body).map((m) => m.group(0)),
        ..._recordCitation.allMatches(body).map((m) => m.group(0)),
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
    return unseen.toList()..sort();
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
  r'\b(grep|sql|read_story|find|outline|similar_names|delegate)\b',
);

/// `record:<id>` — a non-story record (R17).
final RegExp _recordCitation = RegExp(r'record:([\w\-]+)');

/// A backticked story file with no line number after it.
final RegExp _bareStoryCitation = RegExp(r'`([\w\-/\.\[\]]+\.txt)`');
