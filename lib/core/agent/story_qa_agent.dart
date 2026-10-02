import 'dart:async';

import '../gamedata/game_retrieval.dart';
import '../llm/embedding_client.dart';
import '../llm/llm_client.dart';
import 'agent_prompts.dart';
import 'entity_disambiguator.dart';
import 'evidence_notebook.dart' show ReadPage;
import 'planner_loop.dart';
import 'react_event.dart';
import 'story_answer.dart';
import 'tools/agent_tool.dart';
import 'tools/collect_entity_evidence.dart';
import 'tools/get_story_map.dart';
import 'tools/get_story_outline.dart';
import 'tools/read_story_lines.dart';
import 'tools/search_local_lore.dart';
import 'tools/search_story_coverage.dart';
import 'tools/search_story_lines.dart';
import 'tools/tool_registry.dart';

/// The one story QA pipeline (R13): investigation, summary and fact check
/// all run the same [PlannerLoop] with the same tools, evidence notebook and
/// citation checks; [AnswerStyle] only changes the writer's output format.
///
/// Roles: the planner, extractor and disambiguator are mechanical and run on
/// [auxClient] (reasoning off in the app); the writer runs on [llmClient].
class StoryQaAgent {
  StoryQaAgent({
    required LLMClient llmClient,
    LLMClient? auxClient,
    LLMClient? plannerClient,
    LLMClient? extractorClient,
    LLMClient? disambiguatorClient,
    GameDataRetrieval? gameDataStore,
    EmbeddingClient? embeddingClient,
    AgentTool? searchTool,
  })  : _llmClient = llmClient,
        _plannerClient = plannerClient ?? auxClient ?? llmClient,
        _extractorClient = extractorClient ?? auxClient ?? llmClient,
        _disambiguator = EntityDisambiguator(
          llmClient: disambiguatorClient ?? auxClient ?? llmClient,
        ),
        _storyCatalogLookup = gameDataStore?.storyCatalogEntries,
        _toolRegistry = ToolRegistry() {
    // R9: ALL tools share ONE store instance (separate stores closed each
    // other's shared sqflite connection).
    final store = gameDataStore;
    _toolRegistry.registerAll([
      searchTool ?? SearchLocalLoreTool(gameDataStore: store),
      SearchStoryCoverageTool(gameDataStore: store),
      SearchStoryLinesTool(
        gameDataStore: store,
        embeddingClient: embeddingClient,
      ),
      GetStoryMapTool(gameDataStore: store),
      GetStoryOutlineTool(gameDataStore: store),
      ReadStoryLinesTool(gameDataStore: store),
      CollectEntityEvidenceTool(gameDataStore: store),
    ]);
  }

  final StoryCatalogLookup? _storyCatalogLookup;
  final LLMClient _llmClient;
  final LLMClient _plannerClient;
  final LLMClient _extractorClient;
  final EntityDisambiguator _disambiguator;
  final ToolRegistry _toolRegistry;

  /// Answers [query] in [style].
  Stream<ReActEvent> run({
    required String query,
    required AnswerStyle style,
    List<Message> history = const [],
    List<ReadPage> priorPages = const [],
    void Function(int iteration, String rawResponse)? onRawLlmResponse,
    void Function(String memoryBlock)? onMemoryChanged,
  }) {
    final task = switch (style) {
      AnswerStyle.answer => plannerTaskAnswer,
      AnswerStyle.summary => plannerTaskSummary,
      AnswerStyle.factCheck => plannerTaskFactCheck,
    };
    final loop = PlannerLoop(
      llmClient: _plannerClient,
      writerClient: _llmClient,
      toolRegistry: _toolRegistry,
      extractorClient: _extractorClient,
      disambiguator: _disambiguator,
      minimumToolCalls: 1,
      // R12: ceiling, not cost — reasoning models need room before the
      // one-line intent (completeWithHeadroom escalates when truncated).
      stepMaxTokens: 4096,
      // R12 cost control: useful reads happen early; a spent budget still
      // ends through the writer with what was read.
      maxToolSteps: 24,
      storyCatalogLookup: _storyCatalogLookup,
    );
    return loop.run(
      // The planner gets the trust rules + protocol only; the answer format
      // belongs to the writer.
      systemPrompt: '$knowledgeBaseRules\n\n$storyPlannerInstructions\n\n$task',
      chatHistory: history,
      priorPages: priorPages,
      userQuery: query,
      style: style,
      onRawLlmResponse: onRawLlmResponse,
      onStateChanged: onMemoryChanged,
    );
  }
}
