import 'dart:async';

import '../gamedata/game_retrieval.dart';
import '../llm/embedding_client.dart';
import '../llm/llm_client.dart';
import 'react_event.dart';
import 'story_answer.dart';
import 'story_qa_agent.dart';

/// Ask "investigate" mode: a direct answer with cited evidence and
/// counter-evidence. Runs the shared [StoryQaAgent] pipeline with
/// [AnswerStyle.answer] (R13).
class InvestigationAgent {
  InvestigationAgent({
    required LLMClient llmClient,
    GameDataRetrieval? gameDataStore,
    EmbeddingClient? embeddingClient,
  }) : _agent = StoryQaAgent(
          llmClient: llmClient,
          gameDataStore: gameDataStore,
          embeddingClient: embeddingClient,
        );

  final StoryQaAgent _agent;
  Stream<ReActEvent> investigate({
    required String query,
    List<Message> history = const [],
    LLMClient? client,
    LoreConversation? prior,
    void Function(LoreConversation conversation)? onConversation,
    void Function(int iteration, String rawResponse)? onRawLlmResponse,
  }) =>
      _agent.run(
        query: query,
        style: AnswerStyle.answer,
        history: history,
        client: client,
        prior: prior,
        onConversation: onConversation,
        onRawLlmResponse: onRawLlmResponse,
      );
}
