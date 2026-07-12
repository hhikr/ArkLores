import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'chunker.dart';
import 'embedder.dart';
import 'embedder_provider.dart';
import 'vector_store.dart';
import 'vector_store_provider.dart';
import '../../core/wiki/wiki_crawler.dart';
import '../../core/wiki/wiki_models.dart';

/// Status of the Wiki indexing process.
enum WikiIndexingStatus {
  idle,
  starting,
  fetchingTitles,
  fetchingTouched,
  cleaningUp,
  embedding,
  completed,
  failed,
  retryingFailed,
}

/// State managed by [wikiIndexingProvider].
class WikiIndexingState {
  final WikiIndexingStatus status;
  final double progress;
  final String? error;
  final String? currentSiteName;
  final int totalCount;
  final int processedCount;
  final int skippedCount;
  final int failedChunksCount;
  final String currentItemTitle;

  WikiIndexingState({
    this.status = WikiIndexingStatus.idle,
    this.progress = 0.0,
    this.error,
    this.currentSiteName,
    this.totalCount = 0,
    this.processedCount = 0,
    this.skippedCount = 0,
    this.failedChunksCount = 0,
    this.currentItemTitle = '',
  });

  bool get isIndexing =>
      status != WikiIndexingStatus.idle &&
      status != WikiIndexingStatus.completed &&
      status != WikiIndexingStatus.failed;

  WikiIndexingState copyWith({
    WikiIndexingStatus? status,
    double? progress,
    String? error,
    String? currentSiteName,
    int? totalCount,
    int? processedCount,
    int? skippedCount,
    int? failedChunksCount,
    String? currentItemTitle,
  }) {
    return WikiIndexingState(
      status: status ?? this.status,
      progress: progress ?? this.progress,
      error: error ?? this.error,
      currentSiteName: currentSiteName ?? this.currentSiteName,
      totalCount: totalCount ?? this.totalCount,
      processedCount: processedCount ?? this.processedCount,
      skippedCount: skippedCount ?? this.skippedCount,
      failedChunksCount: failedChunksCount ?? this.failedChunksCount,
      currentItemTitle: currentItemTitle ?? this.currentItemTitle,
    );
  }
}

/// Provider for managing background Wiki indexing and failed chunk retries.
final wikiIndexingProvider =
    StateNotifierProvider<WikiIndexingNotifier, WikiIndexingState>((ref) {
  final vectorStore = ref.watch(vectorStoreProvider);
  final embedder = ref.watch(embedderProvider);
  return WikiIndexingNotifier(
    ref: ref,
    vectorStore: vectorStore,
    embedder: embedder,
  );
});

class WikiIndexingNotifier extends StateNotifier<WikiIndexingState> {
  final Ref _ref;
  final VectorStore _vectorStore;
  final Embedder _embedder;
  final MediaWikiCrawler _crawler;

  WikiIndexingNotifier({
    required Ref ref,
    required VectorStore vectorStore,
    required Embedder embedder,
  })  : _ref = ref,
        _vectorStore = vectorStore,
        _embedder = embedder,
        _crawler = MediaWikiCrawler(),
        super(WikiIndexingState());

  /// Runs the incremental indexing process for a given [WikiSite].
  Future<void> indexWiki(WikiSite site, List<String> categories) async {
    if (state.isIndexing) return;

    state = WikiIndexingState(
      status: WikiIndexingStatus.starting,
      currentSiteName: site.displayName,
    );

    try {
      // Step 1: Fetch all page titles belonging to these categories
      state = state.copyWith(status: WikiIndexingStatus.fetchingTitles);
      final allUniqueTitles = <String>{};
      for (final category in categories) {
        final titles = await _crawler.fetchCategoryTitles(
          site: site,
          categoryName: category,
        );
        allUniqueTitles.addAll(titles);
      }

      if (allUniqueTitles.isEmpty) {
        state = state.copyWith(
          status: WikiIndexingStatus.completed,
          progress: 1.0,
        );
        _ref.invalidate(vectorStoreStatsProvider);
        return;
      }

      // Step 2: Clean up obsolete pages in local DB
      state = state.copyWith(status: WikiIndexingStatus.cleaningUp);
      final localMetadata = await _vectorStore.getWikiPagesMetadata(site.key);
      var cleanedCount = 0;
      for (final localTitle in localMetadata.keys) {
        if (!allUniqueTitles.contains(localTitle)) {
          await _vectorStore.deleteWikiPage(site.key, localTitle);
          cleanedCount++;
        }
      }
      if (cleanedCount > 0) {
        debugPrint('[IndexWiki] Cleaned up $cleanedCount obsolete pages for ${site.key}');
      }

      // Step 3: Fetch last touched timestamps for all remote pages
      state = state.copyWith(status: WikiIndexingStatus.fetchingTouched);
      final titleList = allUniqueTitles.toList();
      final touchedMetadata = await _crawler.fetchPagesLastTouched(site, titleList);

      // Step 4: Identify which pages need to be crawled and embedded
      final pagesToUpdate = <String>[];
      var skippedCount = 0;

      for (final title in titleList) {
        final remoteTouched = touchedMetadata[title] ?? 0;
        final localPage = localMetadata[title];

        if (localPage == null) {
          // New page
          pagesToUpdate.add(title);
        } else if (localPage.hasFailures) {
          // Existed but contains failed chunk embeddings
          pagesToUpdate.add(title);
        } else if (remoteTouched > localPage.updatedAt) {
          // Page modified online
          pagesToUpdate.add(title);
        } else {
          // Up-to-date
          skippedCount++;
        }
      }

      state = state.copyWith(
        totalCount: pagesToUpdate.length,
        skippedCount: skippedCount,
      );

      if (pagesToUpdate.isEmpty) {
        state = state.copyWith(
          status: WikiIndexingStatus.completed,
          progress: 1.0,
        );
        _ref.invalidate(vectorStoreStatsProvider);
        return;
      }

      // Step 5: Fetch content, chunk, embed, and store
      state = state.copyWith(status: WikiIndexingStatus.embedding);
      final chunker = const Chunker();
      var processed = 0;
      var totalNewChunks = 0;

      // Process pages in batches of 10 to limit memory consumption and avoid locking SQLite too long
      const crawlBatchSize = 10;
      for (var i = 0; i < pagesToUpdate.length; i += crawlBatchSize) {
        final batch = pagesToUpdate.sublist(
          i,
          i + crawlBatchSize > pagesToUpdate.length
              ? pagesToUpdate.length
              : i + crawlBatchSize,
        );

        final wikiPages = await _crawler.fetchPageContents(site, batch);

        for (final page in wikiPages) {
          state = state.copyWith(currentItemTitle: page.title);

          // We delete the existing page chunks before writing new ones to prevent leftovers
          await _vectorStore.deleteWikiPage(site.key, page.title);

          // Skip indexing index/list pages to avoid unneeded vectors and massive noise
          final isListOrNav = page.title.contains('一览') ||
              page.title.contains('列表') ||
              page.title.contains('导航') ||
              page.title.contains('Category:');
          if (isListOrNav) {
            processed++;
            state = state.copyWith(
              processedCount: processed,
              progress: (processed / pagesToUpdate.length).clamp(0.0, 1.0),
            );
            continue;
          }

          var finalContent = page.content;
          final isStoryPage = page.content.contains('剧情模拟器');
          if (isStoryPage) {
            finalContent = _cleanStoryContent(page.content);
          }

          final chunks = chunker.chunkByHeadings(finalContent, pageTitle: page.title);
          if (chunks.isNotEmpty) {
            final texts = chunks.map((c) => c.content).toList();
            final embedResult = await _embedder.embedBatch(texts);

            if (embedResult.vectors.isNotEmpty) {
              await _vectorStore.insertChunks(
                chunks,
                embedResult.vectors,
                sourceType: 'wiki',
                sourceUrl: site == WikiSite.prts
                    ? 'https://prts.wiki/w/${Uri.encodeComponent(page.title)}'
                    : 'https://wiki.endfield.moe/w/${Uri.encodeComponent(page.title)}',
                wiki: site.key,
              );
              totalNewChunks += embedResult.vectors.length;
            }
          }

          processed++;
          state = state.copyWith(
            processedCount: processed,
            progress: (processed / pagesToUpdate.length).clamp(0.0, 1.0),
          );

          // Yield to event loop to keep the UI interactive between pages
          await Future.delayed(Duration.zero);
        }
      }

      _ref.invalidate(vectorStoreStatsProvider);

      state = state.copyWith(
        status: WikiIndexingStatus.completed,
        progress: 1.0,
      );
    } catch (e) {
      debugPrint('[IndexWiki] Error: $e');
      state = state.copyWith(
        status: WikiIndexingStatus.failed,
        error: e.toString(),
      );
    }
  }

  /// Retries embedding for all local chunks marked with 'zero_vector'.
  Future<void> retryFailedEmbeddings() async {
    if (state.isIndexing) return;

    state = WikiIndexingState(status: WikiIndexingStatus.retryingFailed);

    try {
      final failedChunks = await _vectorStore.getFailedChunks();
      if (failedChunks.isEmpty) {
        state = state.copyWith(
          status: WikiIndexingStatus.completed,
          progress: 1.0,
        );
        _ref.invalidate(vectorStoreStatsProvider);
        return;
      }

      state = state.copyWith(totalCount: failedChunks.length);
      var processed = 0;
      var successCount = 0;

      // Process in groups of 20
      const batchSize = 20;
      for (var offset = 0; offset < failedChunks.length; offset += batchSize) {
        final end = (offset + batchSize).clamp(0, failedChunks.length);
        final batch = failedChunks.sublist(offset, end);

        final texts = batch.map((row) => row['content'] as String).toList();
        final embedResult = await _embedder.embedBatch(texts);

        for (var j = 0; j < batch.length; j++) {
          final row = batch[j];
          final id = row['id'] as String;
          final embedding = j < embedResult.vectors.length ? embedResult.vectors[j] : null;

          // Check if we got a valid non-zero embedding
          if (embedding != null && !_vectorStore.isZeroVector(embedding)) {
            await _vectorStore.updateChunkEmbedding(id, embedding);
            successCount++;
          }
          processed++;
        }

        state = state.copyWith(
          processedCount: processed,
          progress: (processed / failedChunks.length).clamp(0.0, 1.0),
        );

        await Future.delayed(Duration.zero);
      }

      _ref.invalidate(vectorStoreStatsProvider);

      state = state.copyWith(
        status: WikiIndexingStatus.completed,
        progress: 1.0,
        failedChunksCount: failedChunks.length - successCount,
      );
    } catch (e) {
      debugPrint('[RetryFailed] Error: $e');
      state = state.copyWith(
        status: WikiIndexingStatus.failed,
        error: e.toString(),
      );
    }
  }

  /// Resets the indexing state back to idle.
  void reset() {
    state = WikiIndexingState();
  }

  /// Cleans wikitext script macros and templates from Arknights story pages.
  ///
  /// Removes [Character(...)], [Background(...)], [PlayMusic(...)], HTML comments,
  /// and navigation templates, keeping only actual dialogues and narrations.
  String _cleanStoryContent(String rawContent) {
    var content = rawContent;

    // 1. Remove HTML comments
    content = content.replaceAll(RegExp(r'<!--[\s\S]*?-->'), '');

    // 2. Remove plot navigator templates (e.g. {{Navigator/plot|...}})
    content = content.replaceAll(RegExp(r'\{\{[Nn]avigator/[^}]*\}\}'), '');
    content = content.replaceAll(RegExp(r'\{\{[Pp]lot[^}]*\}\}'), '');

    // 3. Remove story simulator headers / starts
    content = content.replaceAll(RegExp(r'\{\{剧情模拟器[^}]*'), '');

    // 4. Remove game scripting macro instructions (typically enclosed in square brackets)
    // Matches patterns like [Character(name="...", ...)], [Background(...)], [Delay(...)], [name="..."]
    content = content.replaceAll(RegExp(r'\[[A-Za-z0-9_]+(?:\([^)]*\))?\]'), '');
    content = content.replaceAll(RegExp(r'\[[A-Za-z_]+=[^\]]*\]'), '');

    // 5. Remove any other square bracket command lines
    content = content.replaceAll(RegExp(r'\[[A-Za-z0-9_]+.*?\]'), '');

    // 6. Split, trim, and filter out structural template residues
    final lines = content.split('\n');
    final cleanLines = lines
        .map((line) => line.trim())
        .where((line) =>
            line.isNotEmpty &&
            !line.startsWith('{{') &&
            !line.startsWith('}}') &&
            line != '|' &&
            !line.startsWith('|背景=') &&
            !line.startsWith('|立绘=') &&
            !line.startsWith('|音频='))
        .toList();

    return cleanLines.join('\n');
  }
}
