import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/rag/vector_store_provider.dart';
import '../../../shared/widgets/citation_card.dart';

/// A wrapper around [CitationCard] that lazily loads the chunk details
/// from the SQLite [VectorStore] using the chunk's UUID.
class LazyCitationCard extends ConsumerWidget {
  final String chunkId;
  final int? index;

  const LazyCitationCard({
    super.key,
    required this.chunkId,
    this.index,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vectorStore = ref.watch(vectorStoreProvider);

    return FutureBuilder<Map<String, dynamic>?>(
      future: vectorStore.getChunkById(chunkId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox(
            height: 48,
            child: Center(
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }

        if (snapshot.hasError || !snapshot.hasData || snapshot.data == null) {
          return const SizedBox.shrink(); // Hide if not found or error
        }

        final chunkData = snapshot.data!;
        final sourceType = chunkData['source_type'] == 'book'
            ? CitationSourceType.book
            : CitationSourceType.wiki;

        final rawTitle = chunkData['page_title'] as String? ?? 'Untitled';
        final title = index != null ? '[$index] $rawTitle' : rawTitle;
        final content = chunkData['content'] as String? ?? '';
        final sourceUrl = chunkData['source_url'] as String?;
        
        String? sourceDetail;
        if (sourceType == CitationSourceType.wiki) {
          final wikiName = chunkData['wiki'] == 'prts' ? 'PRTS Wiki' : 'Endfield Wiki';
          sourceDetail = '$wikiName · ${chunkData['section'] ?? ''}';
        } else {
          sourceDetail = chunkData['section'] as String?;
        }

        return CitationCard(
          title: title,
          content: content,
          sourceType: sourceType,
          sourceUrl: sourceUrl,
          sourceDetail: sourceDetail,
        );
      },
    );
  }
}
