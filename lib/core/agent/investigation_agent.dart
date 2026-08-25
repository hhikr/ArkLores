import 'dart:async';

import '../gamedata/gamedata_knowledge_store.dart';
import '../llm/llm_client.dart';
import 'agent_prompts.dart';
import 'planner_loop.dart';
import 'react_loop.dart';
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
    GameDataKnowledgeStore? gameDataStore,
    LLMClient? extractorClient,
  })  : _llmClient = llmClient,
        _extractorClient = extractorClient,
        _toolRegistry = ToolRegistry() {
    _toolRegistry.registerAll([
      SearchLocalLoreTool(gameDataStore: gameDataStore),
      SearchStoryCoverageTool(gameDataStore: gameDataStore),
      GetStoryMapTool(gameDataStore: gameDataStore),
      ReadStoryLinesTool(gameDataStore: gameDataStore),
      CollectSuspectEvidenceTool(gameDataStore: gameDataStore),
    ]);
  }
  final LLMClient _llmClient;
  final LLMClient? _extractorClient;
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
