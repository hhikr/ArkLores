import 'dart:async';

import '../gamedata/game_retrieval.dart';
import '../llm/embedding_client.dart';
import '../llm/llm_client.dart';
import 'evidence_notebook.dart' show ReadPage;
import 'react_event.dart';
import 'story_answer.dart';
import 'story_qa_agent.dart';

/// Ask "investigate" mode: a direct answer with cited evidence,
/// counter-evidence and confidence. Runs the shared [StoryQaAgent] pipeline
/// with [AnswerStyle.answer] (R13).
class InvestigationAgent {
  InvestigationAgent({
    required LLMClient llmClient,
    GameDataRetrieval? gameDataStore,
    LLMClient? extractorClient,
    LLMClient? disambiguatorClient,
    LLMClient? plannerClient,
    LLMClient? planClient,
    EmbeddingClient? embeddingClient,
  }) : _agent = StoryQaAgent(
          llmClient: llmClient,
          plannerClient: plannerClient,
          planClient: planClient,
          extractorClient: extractorClient,
          disambiguatorClient: disambiguatorClient,
          gameDataStore: gameDataStore,
          embeddingClient: embeddingClient,
        );

  final StoryQaAgent _agent;

  Stream<ReActEvent> investigate({
    required String query,
    List<Message> history = const [],
    List<ReadPage> priorPages = const [],
    LLMClient? writerClient,
    void Function(int iteration, String rawResponse)? onRawLlmResponse,
    void Function(String memoryBlock)? onMemoryChanged,
    bool useToolAgent = false,
    LoreConversation? prior,
    void Function(LoreConversation conversation)? onConversation,
  }) =>
      _agent.run(
        query: query,
        style: AnswerStyle.answer,
        history: history,
        priorPages: priorPages,
        writerClient: writerClient,
        onRawLlmResponse: onRawLlmResponse,
        onMemoryChanged: onMemoryChanged,
        useToolAgent: useToolAgent,
        prior: prior,
        onConversation: onConversation,
      );
}
