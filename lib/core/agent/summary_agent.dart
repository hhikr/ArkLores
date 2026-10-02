import 'dart:async';

import '../gamedata/game_retrieval.dart';
import '../llm/embedding_client.dart';
import '../llm/llm_client.dart';
import 'evidence_notebook.dart' show ReadPage;
import 'react_event.dart';
import 'story_answer.dart';
import 'story_qa_agent.dart';

/// Ask "summarize" mode: overview, timeline and key moments, each cited.
/// Runs the shared [StoryQaAgent] pipeline with [AnswerStyle.summary] (R13;
/// before R13 this was a separate ReAct workflow).
class SummaryAgent {
  SummaryAgent({
    required LLMClient llmClient,
    LLMClient? auxClient,
    GameDataRetrieval? gameDataStore,
    EmbeddingClient? embeddingClient,
  }) : _agent = StoryQaAgent(
          llmClient: llmClient,
          auxClient: auxClient,
          gameDataStore: gameDataStore,
          embeddingClient: embeddingClient,
        );

  final StoryQaAgent _agent;

  /// Yields the pipeline's [ReActEvent]s; [onRawLlmResponse] receives every
  /// raw planner response (session recording).
  Stream<ReActEvent> generateSummary({
    required String query,
    List<Message> history = const [],
    List<ReadPage> priorPages = const [],
    void Function(int iteration, String rawResponse)? onRawLlmResponse,
    void Function(String memoryBlock)? onMemoryChanged,
  }) =>
      _agent.run(
        query: query,
        style: AnswerStyle.summary,
        history: history,
        priorPages: priorPages,
        onRawLlmResponse: onRawLlmResponse,
        onMemoryChanged: onMemoryChanged,
      );
}
