import 'dart:async';

import '../gamedata/game_retrieval.dart';
import '../llm/embedding_client.dart';
import '../llm/llm_client.dart';
import '../llm/usage_meter.dart';
import '../wiki/wiki_lookup.dart';
import 'answer_options.dart';
import 'lore_agent_loop.dart';
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
  /// [options] turns the reader's review and the digest on or off.
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
    return LoreAgentLoop(
      client: client ?? _llmClient,
      // The first searches are written by the plain client: the "深度思考"
      // one would think over a list of search words.
      planClient: _llmClient,
      store: store,
      embeddingClient: _embeddingClient,
      wiki: options.wiki ? _wiki : null,
      review: options.review,
      digest: options.digest,
      delegate: options.delegate,
      onSpan: _usage?.addSpan,
    ).run(
      query: query,
      history: history,
      prior: prior,
      onConversation: onConversation,
      onRawLlmResponse: onRawLlmResponse,
    );
  }
}
