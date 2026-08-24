import 'dart:async';

import '../gamedata/gamedata_knowledge_store.dart';
import '../llm/llm_client.dart';
import 'agent_prompts.dart';
import 'react_loop.dart';
import 'story_coverage_transform.dart';
import 'tools/get_story_map.dart';
import 'tools/read_story_lines.dart';
import 'tools/search_local_lore.dart';
import 'tools/search_story_coverage.dart';
import 'tools/tool_registry.dart';

/// Class representing the Summary Agent.
///
/// Sets up the tool registry and runs the ReAct loop using the summary
/// prompts. Since R1 (AI retrieval P0), the registry also includes the
/// deterministic story coverage tools (`search_story_coverage`,
/// `get_story_map`, `read_story_lines`) for narrative questions, and the
/// final answer is checked by [validateCoverageReport] so the model cannot
/// fabricate the read/mapped/skipped coverage line.
class SummaryAgent {
  SummaryAgent({
    required LLMClient llmClient,
    GameDataKnowledgeStore? gameDataStore,
  })  : _llmClient = llmClient,
        _toolRegistry = ToolRegistry() {
    _toolRegistry.registerAll([
      SearchLocalLoreTool(gameDataStore: gameDataStore),
      SearchStoryCoverageTool(gameDataStore: gameDataStore),
      GetStoryMapTool(gameDataStore: gameDataStore),
      ReadStoryLinesTool(gameDataStore: gameDataStore),
    ]);
  }
  final LLMClient _llmClient;
  final ToolRegistry _toolRegistry;

  /// Runs the Summary Agent for a user query.
  ///
  /// Yields [ReActEvent]s streaming from the underlying ReAct Loop.
  Stream<ReActEvent> generateSummary({
    required String query,
    List<Message> history = const [],
  }) {
    final systemPrompt = buildAgentPrompt(summaryInstructions);

    final loop = ReActLoop(
      llmClient: _llmClient,
      toolRegistry: _toolRegistry,
    );

    return loop.run(
      systemPrompt: systemPrompt,
      chatHistory: history,
      userQuery: query,
      agentName: 'Summary',
      finalAnswerTransform: validateCoverageReport,
    );
  }
}
