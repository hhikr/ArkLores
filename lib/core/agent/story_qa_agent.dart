import 'dart:async';

import '../gamedata/game_retrieval.dart';
import '../llm/embedding_client.dart';
import '../llm/llm_client.dart';
import '../llm/usage_meter.dart';
import '../wiki/wiki_lookup.dart';
import 'answer_options.dart';
import 'lore_agent_loop.dart';
import 'lore_agent_prompts.dart' show loreReviewFollowUp;
import 'react_event.dart';
import 'story_answer.dart';

export 'lore_agent_loop.dart' show LoreConversation;

/// The one story QA pipeline (R13; R17 tool agent): answers, summaries and
/// fact checks all run the same [LoreAgentLoop] with the same prompt, tools
/// and citation checks.
class StoryQaAgent {
  StoryQaAgent({
    required LLMClient llmClient,
    GameDataRetrieval? gameDataStore,
    EmbeddingClient? embeddingClient,
    WikiLookup? wiki,
    UsageMeter? usage,
  })  : _llmClient = llmClient,
        _store = gameDataStore,
        _embeddingClient = embeddingClient,
        _wiki = wiki,
        _usage = usage;

  /// 0.13: the games' wikis, used when the "Wiki" option is on.
  final WikiLookup? _wiki;

  /// Where tool runs and local checks report their wall-clock spans.
  final UsageMeter? _usage;
  final LLMClient _llmClient;
  final GameDataRetrieval? _store;
  final EmbeddingClient? _embeddingClient;

  /// Answers [query]. [prior] continues an earlier answer's conversation
  /// (follow-ups); [onConversation] receives this one's. [client] replaces
  /// the default client for this question (the "深度思考" switch);
  /// [options] turns the wikis and the sub-agents on or off.
  Stream<ReActEvent> run({
    required String query,
    List<Message> history = const [],
    LLMClient? client,
    AnswerOptions options = const AnswerOptions(),
    LoreConversation? prior,
    void Function(LoreConversation conversation)? onConversation,
    void Function(int iteration, String rawResponse)? onRawLlmResponse,
  }) {
    final store = _store;
    if (store == null) {
      // Nothing to search: say so without spending a model call.
      const note = '本地知识库不可用，请先在“知识库”页安装中文 GameData 知识库。';
      return Stream.fromIterable([
        ReActEvent(
          type: ReActEventType.finalAnswerReplace,
          content: '${formatStoryAnswerEnvelope(StoryAnswerStatus.notCovered)}'
              '\n$note',
        ),
        const ReActEvent(type: ReActEventType.complete),
      ]);
    }
    return _loop(store, client, options).run(
      query: query,
      history: history,
      prior: prior,
      onConversation: onConversation,
      onRawLlmResponse: onRawLlmResponse,
    );
  }

  LoreAgentLoop _loop(
    GameDataRetrieval store,
    LLMClient? client,
    AnswerOptions options, {
    bool preSearch = true,
  }) =>
      LoreAgentLoop(
        client: client ?? _llmClient,
        // The first searches are written by the plain client: the "深度思考"
        // one would think over a list of search words.
        planClient: _llmClient,
        store: store,
        embeddingClient: _embeddingClient,
        wiki: options.wiki ? _wiki : null,
        delegate: options.delegate,
        preSearch: preSearch,
        onSpan: _usage?.addSpan,
      );

  /// What a review that raised no question answers with.
  static const String reviewClearNote = '复核没有提出疑问，上面的回答保持不变。';

  /// "复核" (0.14: asked for under a finished answer): a second model reads
  /// [answer] — the last answer of [prior] — as a reader. Its questions go
  /// back to the main agent as a follow-up of that conversation, which
  /// checks them in the text and answers again (the usual tools and
  /// citation check). With no question the answer is [reviewClearNote] and
  /// the conversation stays as it was.
  Stream<ReActEvent> review({
    required LoreConversation prior,
    required String answer,
    LLMClient? client,
    AnswerOptions options = const AnswerOptions(),
    void Function(LoreConversation conversation)? onConversation,
    void Function(int iteration, String rawResponse)? onRawLlmResponse,
  }) async* {
    final store = _store;
    if (store == null) {
      yield const ReActEvent(type: ReActEventType.error, content: '本地知识库不可用');
      return;
    }
    // The follow-up continues from the review's own record.
    void Function(int, String)? shifted;
    if (onRawLlmResponse != null) {
      shifted = (iteration, raw) => onRawLlmResponse(iteration + 1, raw);
    }
    // No searches written ahead: the reader's questions say what to look up.
    final loop = _loop(store, client, options, preSearch: false);
    yield const ReActEvent(type: ReActEventType.status, content: '审稿中');
    final issues = await loop.review(
      prior.question,
      answer,
      onRaw: (raw) => onRawLlmResponse?.call(1, '（审稿）$raw'),
    );
    if (issues.isEmpty) {
      onConversation?.call(prior);
      yield const ReActEvent(
        type: ReActEventType.finalAnswerReplace,
        content: reviewClearNote,
      );
      yield const ReActEvent(type: ReActEventType.complete);
      return;
    }
    yield ReActEvent(
      type: ReActEventType.thought,
      content: [
        '读者审稿：',
        for (final (i, issue) in issues.indexed) '${i + 1}. $issue',
      ].join('\n'),
    );
    yield* loop.run(
      query: loreReviewFollowUp(issues, json: prior.entries.isNotEmpty),
      prior: prior,
      asQuestion: prior.question,
      onConversation: onConversation,
      onRawLlmResponse: shifted,
    );
  }

  /// "提要" (0.14: asked for under a finished answer): the last answer of
  /// [conversation] reorganised into a few paragraphs above [detail], its
  /// text. See [LoreAgentLoop.digest].
  Stream<ReActEvent> digest({
    required LoreConversation conversation,
    required String detail,
    void Function(String raw)? onRaw,
  }) {
    final store = _store;
    if (store == null) {
      return Stream.value(
        const ReActEvent(type: ReActEventType.error, content: '本地知识库不可用'),
      );
    }
    return _loop(store, null, const AnswerOptions()).digest(
      conversation.entries,
      question: conversation.question,
      detail: detail,
      onRaw: onRaw,
    );
  }
}
