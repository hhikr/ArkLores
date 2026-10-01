import 'dart:async';

import '../gamedata/game_retrieval.dart';
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
    GameDataRetrieval? gameDataStore,
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
  /// [onRawLlmResponse] receives the full raw LLM response of every
  /// iteration (session recording).
  Stream<ReActEvent> generateSummary({
    required String query,
    List<Message> history = const [],
    void Function(int iteration, String rawResponse)? onRawLlmResponse,
    void Function(String memoryBlock)? onMemoryChanged,
  }) {
    final systemPrompt = buildAgentPrompt(summaryInstructions);

    final loop = ReActLoop(
      llmClient: _llmClient,
      toolRegistry: _toolRegistry,
      // Reasoning providers need room for hidden reasoning plus a long
      // final answer; 2048/4096 caused mid-answer truncation errors.
      stepMaxTokens: 8192,
    );

    return loop.run(
      systemPrompt: systemPrompt,
      chatHistory: history,
      userQuery: query,
      finalAnswerTransform: validateCoverageReport,
      onRawLlmResponse: onRawLlmResponse,
      onMemoryChanged: onMemoryChanged,
    );
  }
}
