import 'dart:async';

import '../gamedata/game_retrieval.dart';
import '../llm/embedding_client.dart';
import '../llm/llm_client.dart';
import 'react_event.dart';
import 'story_answer.dart';
import 'story_qa_agent.dart';

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
    GameDataRetrieval? gameDataStore,
    EmbeddingClient? embeddingClient,
  }) : _agent = StoryQaAgent(
          llmClient: llmClient,
          gameDataStore: gameDataStore,
          embeddingClient: embeddingClient,
        );

  final StoryQaAgent _agent;
  Stream<ReActEvent> checkClaim({
    required String claim,
    List<Message> history = const [],
    LLMClient? client,
    LoreConversation? prior,
    void Function(LoreConversation conversation)? onConversation,
    void Function(int iteration, String rawResponse)? onRawLlmResponse,
  }) =>
      _agent.run(
        query: claim,
        style: AnswerStyle.factCheck,
        history: history,
        client: client,
        prior: prior,
        onConversation: onConversation,
        onRawLlmResponse: onRawLlmResponse,
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
