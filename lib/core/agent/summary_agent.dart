import 'dart:async';
import '../llm/llm_client.dart';
import '../rag/embedder.dart';
import '../rag/vector_store.dart';
import 'agent_prompts.dart';
import 'react_loop.dart';
import 'tools/search_wiki.dart';
import 'tools/cite_source.dart';
import 'tools/tool_registry.dart';

/// Class representing the Summary Agent.
///
/// Sets up the tool registry and runs the ReAct loop using the summary prompts.
class SummaryAgent {
  final LLMClient _llmClient;
  final ToolRegistry _toolRegistry;

  SummaryAgent({
    required LLMClient llmClient,
    required Embedder embedder,
    required VectorStore vectorStore,
    String? profileId,
  }) : _llmClient = llmClient,
       _toolRegistry = ToolRegistry() {
    // Register the tools needed by the Summary Agent
    _toolRegistry.register(SearchWikiTool(
      embedder: embedder,
      vectorStore: vectorStore,
      profileId: profileId,
    ));
    _toolRegistry.register(CiteSourceTool(
      vectorStore: vectorStore,
    ));
  }

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
      maxIterations: 4, // Max iterations for summary task
    );

    return loop.run(
      systemPrompt: systemPrompt,
      chatHistory: history,
      userQuery: query,
    );
  }
}
