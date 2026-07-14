import '../../rag/vector_store.dart';
import 'agent_tool.dart';

/// Tool to retrieve the full content of a specific chunk by its ID.
class CiteSourceTool extends AgentTool {
  final VectorStore _vectorStore;

  CiteSourceTool({
    required VectorStore vectorStore,
  }) : _vectorStore = vectorStore;

  @override
  String get name => 'cite_source';

  @override
  String get description =>
      'Retrieve the full text content and source metadata of a specific chunk '
      'using its chunk_id. Always use this tool to verify the exact text and '
      'retrieve source details before finalizing a citation or claiming a quote.';

  @override
  Map<String, dynamic> get parameters => {
        'type': 'object',
        'properties': {
          'chunk_id': {
            'type': 'string',
            'description': 'The unique ID (UUID) of the text chunk to retrieve.',
          },
        },
        'required': ['chunk_id'],
      };

  @override
  Future<dynamic> execute(Map<String, dynamic> arguments) async {
    final chunkId = arguments['chunk_id'] as String?;
    if (chunkId == null || chunkId.trim().isEmpty) {
      return 'Error: chunk_id parameter is empty';
    }

    try {
      final chunkMap = await _vectorStore.getChunkById(chunkId);
      if (chunkMap == null) {
        return 'No chunk found with ID: $chunkId';
      }

      final buffer = StringBuffer();
      buffer.writeln('=== Chunk Details ===');
      buffer.writeln('ID: ${chunkMap['id']}');
      buffer.writeln('Source Type: ${chunkMap['source_type']}');
      if (chunkMap['source_type'] == 'wiki') {
        buffer.writeln('Wiki: ${chunkMap['wiki']}');
        if (chunkMap['source_url'] != null) {
          buffer.writeln('Source URL: ${chunkMap['source_url']}');
        }
      } else if (chunkMap['source_type'] == 'book') {
        buffer.writeln('Book ID: ${chunkMap['book_id']}');
      }
      buffer.writeln('Title: ${chunkMap['page_title']}');
      if (chunkMap['section'] != null && (chunkMap['section'] as String).isNotEmpty) {
        buffer.writeln('Section: ${chunkMap['section']}');
      }
      buffer.writeln('Content:\n${chunkMap['content']}');

      return buffer.toString().trim();
    } catch (e) {
      return 'Error occurred during chunk lookup: $e';
    }
  }
}
