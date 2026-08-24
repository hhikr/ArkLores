import 'dart:async';

import '../gamedata/gamedata_knowledge_store.dart';
import '../llm/llm_client.dart';
import 'agent_prompts.dart';
import 'investigation_verdict.dart';
import 'react_loop.dart';
import 'tools/collect_suspect_evidence.dart';
import 'tools/find_detail_echoes.dart';
import 'tools/get_story_map.dart';
import 'tools/read_story_lines.dart';
import 'tools/search_local_lore.dart';
import 'tools/search_story_coverage.dart';
import 'tools/tool_registry.dart';

/// Story Investigation Agent (P1, R3): cross-chapter causal/mystery questions.
///
/// Runs the staged protocol S0–S8 with a fixed budget (12 iterations, 4096
/// step tokens, at least 4 completed tool calls) and a code-level verdict
/// transform ([validateInvestigationVerdict]) that gates culprit conclusions
/// on the S6 evidence threshold and validates line-level provenance.
class InvestigationAgent {
  InvestigationAgent({
    required LLMClient llmClient,
    GameDataKnowledgeStore? gameDataStore,
  })  : _llmClient = llmClient,
        _toolRegistry = ToolRegistry() {
    _toolRegistry.registerAll([
      SearchLocalLoreTool(gameDataStore: gameDataStore),
      SearchStoryCoverageTool(gameDataStore: gameDataStore),
      GetStoryMapTool(gameDataStore: gameDataStore),
      ReadStoryLinesTool(gameDataStore: gameDataStore),
      FindDetailEchoesTool(gameDataStore: gameDataStore),
      CollectSuspectEvidenceTool(gameDataStore: gameDataStore),
    ]);
  }
  final LLMClient _llmClient;
  final ToolRegistry _toolRegistry;

  /// Runs an investigation for [query].
  Stream<ReActEvent> investigate({
    required String query,
    List<Message> history = const [],
  }) {
    final systemPrompt = buildAgentPrompt(investigationInstructions);
    final loop = ReActLoop(
      llmClient: _llmClient,
      toolRegistry: _toolRegistry,
      minimumToolCalls: 4,
      stepMaxTokens: 4096,
      maxObservationHistory: 8,
    );
    return loop.run(
      systemPrompt: systemPrompt,
      chatHistory: history,
      userQuery: query,
      agentName: 'Investigation',
      finalAnswerTransform: validateInvestigationVerdict,
    );
  }
}
