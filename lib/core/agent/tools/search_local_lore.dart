import '../../gamedata/gamedata_knowledge_store.dart';
import 'agent_tool.dart';
import 'search_wiki.dart';

/// Source-neutral local lore search tool.
class SearchLocalLoreTool extends SearchWikiTool {
  final GameDataKnowledgeStore? _gameDataStore;

  SearchLocalLoreTool({
    required super.embedder,
    required super.vectorStore,
    super.profileId,
    GameDataKnowledgeStore? gameDataStore,
  }) : _gameDataStore = gameDataStore ?? GameDataKnowledgeStore();

  @override
  String get name => 'search_local_lore';

  @override
  String get description =>
      'Search the local ArkLores knowledge base. Prefer GameData/game original '
      'text when installed, then specified Wiki, then user-imported books. '
      'Supports optional content_type and entity_id filters. Returns source '
      'kind, content_type, source_path, raw_id, and chunk/record id for citations.';

  @override
  Map<String, dynamic> get parameters => {
        'type': 'object',
        'properties': {
          'query': {
            'type': 'string',
            'description':
                'The query text to search for (e.g., character name, event, faction, or lore topic).',
          },
          'top_k': {
            'type': 'integer',
            'description':
                'Number of search results to return. Default is 5, max is 10.',
            'default': 5,
          },
          'content_type': {
            'type': 'string',
            'description':
                'Optional GameData content type filter, e.g. operator_voice, enemy_profile, roguelike_topic.',
          },
          'entity_id': {
            'type': 'string',
            'description':
                'Optional GameData entity id filter, e.g. char_002_amiya.',
          },
        },
        'required': ['query'],
      };

  @override
  Future<dynamic> execute(Map<String, dynamic> arguments) async {
    final query = arguments['query'] as String?;
    if (query == null || query.trim().isEmpty) {
      return 'Error: query parameter is empty';
    }

    final topK = (arguments['top_k'] as num?)?.toInt() ?? 5;
    final cleanTopK = topK.clamp(1, 10);
    final contentType = arguments['content_type'] as String?;
    final entityId = arguments['entity_id'] as String?;

    final store = _gameDataStore;
    if (store != null && await store.isAvailable) {
      final results = await store.search(
        query: query,
        topK: cleanTopK,
        contentType: contentType,
        entityId: entityId,
      );
      if (results.isNotEmpty) {
        return _formatGameDataResults(results);
      }
      final fallback = await super.execute(arguments);
      if (fallback is ToolExecutionResult) {
        return ToolExecutionResult(
          observation:
              'No confident GameData result found for "$query". Falling back to Wiki/Book compatibility search.\n\n${fallback.observation}',
          debugLog: fallback.debugLog,
        );
      }
      return 'No confident GameData result found for "$query". Falling back to Wiki/Book compatibility search.\n\n$fallback';
    }

    final fallback = await super.execute(arguments);
    if (fallback is ToolExecutionResult) {
      return ToolExecutionResult(
        observation:
            'Local GameData knowledge DB is not installed. Falling back to Wiki/Book compatibility search.\n\n${fallback.observation}',
        debugLog: fallback.debugLog,
      );
    }
    return 'Local GameData knowledge DB is not installed. Falling back to Wiki/Book compatibility search.\n\n$fallback';
  }

  ToolExecutionResult _formatGameDataResults(
    List<GameDataSearchResult> results,
  ) {
    final buffer = StringBuffer();
    for (var i = 0; i < results.length; i++) {
      final result = results[i];
      buffer.writeln(
        '=== Result #${i + 1} (Score: ${result.score.toStringAsFixed(4)}) ===',
      );
      buffer.writeln('Source Kind: ${result.sourceKind}');
      buffer.writeln('Source Type: ${result.sourceType}');
      buffer.writeln('Retrieval Type: ${result.retrievalType}');
      buffer.writeln('ID: ${result.id}');
      if (result.contentCategory != null) {
        buffer.writeln('Content Category: ${result.contentCategory}');
      }
      if (result.contentSubtype != null) {
        buffer.writeln('Content Subtype: ${result.contentSubtype}');
      }
      if (result.contentType != null) {
        buffer.writeln('Content Type: ${result.contentType}');
      }
      if (result.entityId != null) {
        buffer.writeln('Entity ID: ${result.entityId}');
      }
      if (result.storyId != null) {
        buffer.writeln('Story ID: ${result.storyId}');
      }
      buffer.writeln('Title: ${result.title}');
      if (result.section != null && result.section!.isNotEmpty) {
        buffer.writeln('Section: ${result.section}');
      }
      if (result.sourcePath != null) {
        buffer.writeln('Source Path: ${result.sourcePath}');
      }
      if (result.rawId != null) {
        buffer.writeln('Raw ID: ${result.rawId}');
      }
      if (result.lineStart != null || result.lineEnd != null) {
        buffer.writeln(
            'Lines: ${result.lineStart ?? '?'}-${result.lineEnd ?? '?'}');
      }
      buffer.writeln('Trust: GameData / game original text (highest).');
      buffer.writeln('Content:\n${result.content}');
      buffer.writeln();
    }
    return ToolExecutionResult(observation: buffer.toString().trim());
  }
}
