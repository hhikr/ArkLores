import '../../rag/embedder.dart';
import '../../rag/vector_store.dart';
import 'agent_tool.dart';

/// Tool to perform semantic search on the knowledge base.
class SearchWikiTool extends AgentTool {
  final Embedder _embedder;
  final VectorStore _vectorStore;
  final String? _profileId;

  SearchWikiTool({
    required Embedder embedder,
    required VectorStore vectorStore,
    String? profileId,
  })  : _embedder = embedder,
        _vectorStore = vectorStore,
        _profileId = profileId;

  @override
  String get name => 'search_wiki';

  @override
  String get description =>
      'Search the Arknights and Endfield knowledge base (Wikis and imported books) '
      'using semantic search. Returns relevant text chunks along with metadata '
      'such as source type, page title, section, source url, and chunk id.';

  @override
  Map<String, dynamic> get parameters => {
        'type': 'object',
        'properties': {
          'query': {
            'type': 'string',
            'description': 'The query text to search for (e.g., character name, event, faction, or lore topic).',
          },
          'top_k': {
            'type': 'integer',
            'description': 'Number of search results to return. Default is 5, max is 10.',
            'default': 5,
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

    try {
      // 1. Generate query embedding
      final queryVector = await _embedder.embed(query);

      // 2. Perform search in VectorStore
      final searchResults = await _vectorStore.search(
        queryVector,
        topK: cleanTopK,
        profileId: _profileId,
      );

      if (searchResults.isEmpty) {
        return 'No matching records found in the database.';
      }

      // 3. Format results as a readable block for LLM
      final buffer = StringBuffer();
      for (var i = 0; i < searchResults.length; i++) {
        final res = searchResults[i];
        final chunk = res.chunk;
        buffer.writeln('=== Result #${i + 1} (Score: ${res.score.toStringAsFixed(4)}) ===');
        buffer.writeln('ID: ${chunk.id}');
        buffer.writeln('Source Type: ${res.sourceType}');
        if (res.sourceType == 'wiki') {
          buffer.writeln('Wiki: ${res.wiki}');
          if (res.sourceUrl != null) {
            buffer.writeln('Source URL: ${res.sourceUrl}');
          }
        } else if (res.sourceType == 'book' && res.bookId != null) {
          buffer.writeln('Book ID: ${res.bookId}');
        }
        buffer.writeln('Title: ${chunk.pageTitle}');
        if (chunk.section.isNotEmpty) {
          buffer.writeln('Section: ${chunk.section}');
        }
        buffer.writeln('Content:\n${chunk.content}');
        buffer.writeln();
      }

      return buffer.toString().trim();
    } catch (e) {
      return 'Error occurred during search: $e';
    }
  }
}
