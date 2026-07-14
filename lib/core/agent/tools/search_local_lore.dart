import 'search_wiki.dart';

/// Source-neutral local lore search tool.
///
/// v0.4 uses the v0.3 local Wiki/Book vector store as a compatibility backing
/// store. v0.4.5 can replace this implementation with GameData structured
/// lookup + FTS + vector fallback without changing agent workflows.
class SearchLocalLoreTool extends SearchWikiTool {
  SearchLocalLoreTool({
    required super.embedder,
    required super.vectorStore,
    super.profileId,
  });

  @override
  String get name => 'search_local_lore';

  @override
  String get description =>
      'Search the local ArkLores knowledge base. Prefer GameData/game text '
      'when available, then specified Wiki, then user-imported books. The '
      'current v0.4 compatibility implementation searches the local v0.3 '
      'Wiki/Book database with title, keyword, and vector fallback. Returns '
      'source_type, retrieval_type, source path or URL when available, and '
      'chunk id for citations.';
}
