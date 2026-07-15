import '../gamedata/gamedata_knowledge_store.dart';
import '../llm/llm_client.dart';
import 'agent_prompts.dart';
import 'react_loop.dart';
import 'tools/agent_tool.dart';
import 'tools/search_local_lore.dart';
import 'tools/tool_registry.dart';

enum CharacterResolutionStatus { resolved, ambiguous, notFound, unavailable }

class CharacterResolution {
  final CharacterResolutionStatus status;
  final GameDataEntityCandidate? character;
  final List<GameDataEntityCandidate> candidates;

  const CharacterResolution(this.status,
      {this.character, this.candidates = const []});
}

class RoleplayAgent {
  final LLMClient _llmClient;
  final GameDataKnowledgeStore _store;
  final AgentTool _searchTool;

  RoleplayAgent({
    required LLMClient llmClient,
    GameDataKnowledgeStore? gameDataStore,
    AgentTool? searchTool,
  })  : _llmClient = llmClient,
        _store = gameDataStore ?? GameDataKnowledgeStore(),
        _searchTool =
            searchTool ?? SearchLocalLoreTool(gameDataStore: gameDataStore);

  Future<CharacterResolution> resolveCharacter(String query) async {
    if (!await _store.isAvailable) {
      return const CharacterResolution(CharacterResolutionStatus.unavailable);
    }
    final candidates = await _store.findEntityCandidates(query);
    final exact = candidates
        .where((candidate) =>
            candidate.matchType == 'name_exact' ||
            candidate.matchType == 'canonical_alias_exact' ||
            candidate.matchType == 'alias_exact')
        .toList(growable: false);
    if (exact.length == 1) {
      return CharacterResolution(CharacterResolutionStatus.resolved,
          character: exact.single);
    }
    if (exact.length > 1) {
      return CharacterResolution(CharacterResolutionStatus.ambiguous,
          candidates: exact);
    }
    if (candidates.length == 1) {
      return CharacterResolution(CharacterResolutionStatus.resolved,
          character: candidates.single);
    }
    return CharacterResolution(
      candidates.isEmpty
          ? CharacterResolutionStatus.notFound
          : CharacterResolutionStatus.ambiguous,
      candidates: candidates,
    );
  }

  Stream<ReActEvent> reply({
    required GameDataEntityCandidate character,
    required String userMessage,
    String scene = '',
    List<Message> history = const [],
    bool isFirstTurn = false,
  }) {
    final registry = ToolRegistry()
      ..register(_CharacterBoundSearchTool(_searchTool, character.entityId));
    final loop = ReActLoop(
      llmClient: _llmClient,
      toolRegistry: registry,
      maxIterations: isFirstTurn ? 7 : 5,
      minimumToolCalls: 1,
      stepMaxTokens: 4096,
    );
    final context = '''
Canonical character: ${character.name}
Stable entity_id: ${character.entityId}
Entity type: ${character.entityType}
GameData source path: ${character.sourcePath ?? 'not provided'}
User scene (session context, NOT GameData evidence): ${scene.trim().isEmpty ? 'none' : scene.trim()}

Every search_local_lore call must pass entity_id="${character.entityId}".
${isFirstTurn ? 'This is the first turn. Build broad character memory by retrieving profile/voice/operator record/module material and story participation before answering. Use separate targeted calls as needed.' : 'Retrieve GameData relevant to the new message before answering; retain prior conversation only as generated session context.'}
''';
    return loop.run(
      systemPrompt: '${buildAgentPrompt(roleplayInstructions)}\n\n$context',
      chatHistory: history,
      userQuery: userMessage,
      agentName: 'Roleplay:${character.entityId}',
    );
  }
}

class _CharacterBoundSearchTool extends AgentTool {
  final AgentTool delegate;
  final String entityId;

  _CharacterBoundSearchTool(this.delegate, this.entityId);

  @override
  String get name => delegate.name;

  @override
  String get description =>
      '${delegate.description} This roleplay session is locked to entity_id=$entityId.';

  @override
  Map<String, dynamic> get parameters => delegate.parameters;

  @override
  Future<dynamic> execute(Map<String, dynamic> arguments) {
    return delegate.execute({
      ...arguments,
      'entity_id': entityId,
      'search_mode': arguments['search_mode'] ?? 'roleplay',
    });
  }
}
