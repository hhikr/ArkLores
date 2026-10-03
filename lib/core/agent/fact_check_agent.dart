import 'dart:async';

import '../gamedata/game_retrieval.dart';
import '../llm/embedding_client.dart';
import '../llm/llm_client.dart';
import 'evidence_notebook.dart' show ReadPage;
import 'react_event.dart';
import 'story_answer.dart';
import 'story_qa_agent.dart';
import 'tools/agent_tool.dart';

enum FactCheckVerdict { supported, refuted, uncertain, unavailable }

extension FactCheckVerdictWireValue on FactCheckVerdict {
  String get wireValue => name;
}

/// Ask "verify" mode: a `[FACT_CHECK_VERDICT:…]` line, claim breakdown and
/// cited evidence. Runs the shared [StoryQaAgent] pipeline with
/// [AnswerStyle.factCheck] (R13); a definite verdict without cited read text
/// is downgraded by code (`normalizeFactCheckBody`).
class FactCheckAgent {
  FactCheckAgent({
    required LLMClient llmClient,
    LLMClient? auxClient,
    LLMClient? planClient,
    GameDataRetrieval? gameDataStore,
    EmbeddingClient? embeddingClient,
    AgentTool? searchTool,
  }) : _agent = StoryQaAgent(
          llmClient: llmClient,
          auxClient: auxClient,
          planClient: planClient,
          gameDataStore: gameDataStore,
          embeddingClient: embeddingClient,
          searchTool: searchTool,
        );

  final StoryQaAgent _agent;

  Stream<ReActEvent> checkClaim({
    required String claim,
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
        query: claim,
        style: AnswerStyle.factCheck,
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

FactCheckVerdict? parseFactCheckVerdict(String content) {
  final match = RegExp(
    r'\[FACT_CHECK_VERDICT:(supported|refuted|uncertain|unavailable)\]',
    caseSensitive: false,
  ).firstMatch(content);
  final value = match?.group(1)?.toLowerCase();
  if (value == null) return null;
  return FactCheckVerdict.values.firstWhere((item) => item.name == value);
}
