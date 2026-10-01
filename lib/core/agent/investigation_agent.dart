import 'dart:async';

import '../gamedata/game_retrieval.dart';
import '../llm/llm_client.dart';
import 'agent_prompts.dart';
import 'entity_disambiguator.dart';
import 'planner_loop.dart';
import 'react_event.dart';
import 'tools/collect_suspect_evidence.dart';
import 'tools/get_story_map.dart';
import 'tools/read_story_lines.dart';
import 'tools/search_local_lore.dart';
import 'tools/search_story_coverage.dart';
import 'tools/tool_registry.dart';

/// Story Investigation Agent (R8): cross-chapter causal/mystery questions.
///
/// Runs the planner loop (decision intent + code executor + optional
/// extractor): the model outputs one short intent per call, tools are
/// executed deterministically, and the InvestigationState keeps stage
/// progress + read key points + evidence — so the request context stays
/// bounded and nothing needs truncating.
class InvestigationAgent {
  InvestigationAgent({
    required LLMClient llmClient,
    GameDataRetrieval? gameDataStore,
    LLMClient? extractorClient,
    LLMClient? disambiguatorClient,
  })  : _llmClient = llmClient,
        _extractorClient = extractorClient,
        _disambiguator =
            EntityDisambiguator(llmClient: disambiguatorClient ?? llmClient),
        _toolRegistry = ToolRegistry() {
    // R9: ALL tools share ONE store instance. Each tool defaulting to its own
    // GameDataKnowledgeStore() meant several sqflite connections to the same
    // file; sqflite's singleInstance returns the same underlying connection,
    // and one store's stat-change close() then killed the shared connection
    // mid-investigation (database_closed after repeated SEARCH calls).
    final store = gameDataStore;
    _toolRegistry.registerAll([
      SearchLocalLoreTool(gameDataStore: store),
      SearchStoryCoverageTool(gameDataStore: store),
      GetStoryMapTool(gameDataStore: store),
      ReadStoryLinesTool(gameDataStore: store),
      CollectSuspectEvidenceTool(gameDataStore: store),
    ]);
  }
  final LLMClient _llmClient;
  final LLMClient? _extractorClient;
  final EntityDisambiguator _disambiguator;
  final ToolRegistry _toolRegistry;

  /// Runs an investigation for [query] via the planner loop.
  Stream<ReActEvent> investigate({
    required String query,
    List<Message> history = const [],
    void Function(int iteration, String rawResponse)? onRawLlmResponse,
    void Function(String memoryBlock)? onMemoryChanged,
  }) {
    final systemPrompt = buildAgentPrompt(investigationInstructions);
    final loop = PlannerLoop(
      llmClient: _llmClient,
      toolRegistry: _toolRegistry,
      extractorClient: _extractorClient,
      disambiguator: _disambiguator,
      minimumToolCalls: 3,
      stepMaxTokens: 1024,
    );
    return loop.run(
      systemPrompt: systemPrompt,
      chatHistory: history,
      userQuery: query,
      onRawLlmResponse: onRawLlmResponse,
      onStateChanged: onMemoryChanged,
    );
  }
}
