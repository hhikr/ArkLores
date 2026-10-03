import 'dart:async';

import '../gamedata/game_retrieval.dart';
import '../llm/embedding_client.dart';
import '../llm/llm_client.dart';
import 'react_event.dart';
import 'story_answer.dart';
import 'story_qa_agent.dart';

/// Ask "summarize" mode: overview, timeline and key moments, each cited.
/// Runs the shared [StoryQaAgent] pipeline with [AnswerStyle.summary] (R13).
class SummaryAgent {
  SummaryAgent({
    required LLMClient llmClient,
    GameDataRetrieval? gameDataStore,
    EmbeddingClient? embeddingClient,
  }) : _agent = StoryQaAgent(
          llmClient: llmClient,
          gameDataStore: gameDataStore,
          embeddingClient: embeddingClient,
        );

  final StoryQaAgent _agent;

  /// Yields the pipeline's [ReActEvent]s; [onRawLlmResponse] receives every
  /// raw model response (session recording).
  Stream<ReActEvent> generateSummary({
    required String query,
    List<Message> history = const [],
    LLMClient? client,
    LoreConversation? prior,
    void Function(LoreConversation conversation)? onConversation,
    void Function(int iteration, String rawResponse)? onRawLlmResponse,
  }) =>
      _agent.run(
        query: query,
        style: AnswerStyle.summary,
        history: history,
        client: client,
        prior: prior,
        onConversation: onConversation,
        onRawLlmResponse: onRawLlmResponse,
      );
}
