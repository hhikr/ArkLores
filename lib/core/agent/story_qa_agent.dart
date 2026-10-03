import 'dart:async';

import '../gamedata/game_retrieval.dart';
import '../llm/embedding_client.dart';
import '../llm/llm_client.dart';
import 'lore_agent_loop.dart';
import 'react_event.dart';
import 'story_answer.dart';

export 'lore_agent_loop.dart' show LoreConversation;

/// The one story QA pipeline (R13; R17 tool agent): answers, summaries and
/// fact checks all run the same [LoreAgentLoop] with the same tools and
/// citation checks; [AnswerStyle] only changes the output format.
class StoryQaAgent {
  StoryQaAgent({
    required LLMClient llmClient,
    GameDataRetrieval? gameDataStore,
    EmbeddingClient? embeddingClient,
  })  : _llmClient = llmClient,
        _store = gameDataStore,
        _embeddingClient = embeddingClient;

  final LLMClient _llmClient;
  final GameDataRetrieval? _store;
  final EmbeddingClient? _embeddingClient;

  /// Answers [query] in [style]. [prior] continues an earlier answer's
  /// conversation (follow-ups); [onConversation] receives this one's.
  /// [client] replaces the default client for this question (the "深度思考"
  /// switch).
  Stream<ReActEvent> run({
    required String query,
    required AnswerStyle style,
    List<Message> history = const [],
    LLMClient? client,
    LoreConversation? prior,
    void Function(LoreConversation conversation)? onConversation,
    void Function(int iteration, String rawResponse)? onRawLlmResponse,
  }) {
    final store = _store;
    if (store == null) {
      // Nothing to search: say so without spending a model call.
      const note = '本地知识库不可用，请先在“知识库”页安装中文 GameData 知识库。';
      final body = style == AnswerStyle.factCheck
          ? normalizeFactCheckBody(
              note,
              nothingRead: true,
              hasValidCitation: false,
            )
          : note;
      return Stream.fromIterable([
        ReActEvent(
          type: ReActEventType.finalAnswerReplace,
          content: '${formatStoryAnswerEnvelope(StoryAnswerStatus.notCovered)}'
              '\n$body',
        ),
        const ReActEvent(type: ReActEventType.complete),
      ]);
    }
    return LoreAgentLoop(
      client: client ?? _llmClient,
      store: store,
      embeddingClient: _embeddingClient,
    ).run(
      query: query,
      style: style,
      history: history,
      prior: prior,
      onConversation: onConversation,
      onRawLlmResponse: onRawLlmResponse,
    );
  }
}
