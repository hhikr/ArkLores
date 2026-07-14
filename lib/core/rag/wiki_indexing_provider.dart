import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'chunker.dart';
import 'embedder.dart';
import 'embedder_provider.dart';
import 'vector_store.dart';
import 'vector_store_provider.dart';
import '../../core/wiki/wiki_crawler.dart';
import '../../core/wiki/wiki_models.dart';
import '../../core/wiki/warfarin_crawler.dart';
import '../../core/wiki/prts_utils.dart' as prts;
import '../../shared/providers/settings_provider.dart';

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
  final profileId =
      ref.watch(embeddingSettingsProvider).activeProfile?.id ?? 'legacy';
  return WikiIndexingNotifier(
    ref: ref,
    vectorStore: vectorStore,
    embedder: embedder,
    profileId: profileId,
  );
});

class WikiIndexingNotifier extends StateNotifier<WikiIndexingState> {
  final Ref _ref;
  final VectorStore _vectorStore;
  final Embedder _embedder;
  final String _profileId;
  final MediaWikiCrawler _crawler;
  bool _cancelled = false;
  int _runGeneration = 0;

  @override
  void dispose() {
    _cancelled = true;
    super.dispose();
  }

  /// Cancels a running indexing operation.
  void cancel() {
    _cancelled = true;
    _runGeneration++;
    state = WikiIndexingState(status: WikiIndexingStatus.idle);
  }

  bool _shouldStop(int runGeneration) {
    return _cancelled || runGeneration != _runGeneration;
  }

  WikiIndexingNotifier({
    required Ref ref,
    required VectorStore vectorStore,
    required Embedder embedder,
    required String profileId,
  })  : _ref = ref,
        _vectorStore = vectorStore,
        _embedder = embedder,
        _profileId = profileId,
        _crawler = MediaWikiCrawler(),
        super(WikiIndexingState());

  /// Runs the incremental indexing process for a given [WikiSite].
  Future<void> indexWiki(WikiSite site, List<String> categories) async {
    if (state.isIndexing) return;

    _cancelled = false;
    final runGeneration = ++_runGeneration;

    if (site == WikiSite.endfield) {
      await _indexEndfield(site);
      return;
    }

    state = WikiIndexingState(
      status: WikiIndexingStatus.starting,
      currentSiteName: site.displayName,
    );

    try {
      // Step 1: Fetch all page titles belonging to these categories
      state = state.copyWith(status: WikiIndexingStatus.fetchingTitles);
      final allUniqueTitles = <String>{};
      final operatorTitles = <String>{};
      final storyTitles = <String>{};
      for (final category in categories) {
        if (_shouldStop(runGeneration)) return;
        final titles = await _crawler.fetchCategoryTitles(
          site: site,
          categoryName: category,
        );
        if (_shouldStop(runGeneration)) return;
        if (category == 'Category:干员') {
          operatorTitles.addAll(titles);
          allUniqueTitles.addAll(titles);
        } else if (category == 'Category:剧情' ||
            category == 'Category:主线剧情' ||
            category == 'Category:活动剧情' ||
            category == 'Category:干员密录') {
          storyTitles.addAll(titles);
          allUniqueTitles.addAll(titles);
        }
        // Other categories (e.g. 敌方, 物品, etc.) are intentionally skipped
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
      final localMetadata = await _vectorStore.getWikiPagesMetadata(
        site.key,
        profileId: _profileId,
      );
      if (_shouldStop(runGeneration)) return;
      var cleanedCount = 0;
      for (final localTitle in localMetadata.keys) {
        if (_shouldStop(runGeneration)) return;
        if (!allUniqueTitles.contains(localTitle)) {
          await _vectorStore.deleteWikiPage(
            site.key,
            localTitle,
            profileId: _profileId,
          );
          await _deleteRawWikiPage(site.key, localTitle);
          cleanedCount++;
        }
      }
      if (cleanedCount > 0) {
        debugPrint(
            '[IndexWiki] Cleaned up $cleanedCount obsolete pages for ${site.key}');
      }

      // Step 3: Identify which pages need to be crawled and embedded.
      // MediaWiki `touched` changes on cache/template refreshes and is too noisy
      // for seeded data, so existing healthy pages are treated as up-to-date.
      final titleList = allUniqueTitles.toList();
      final pagesToUpdate = <String>[];
      var skippedCount = 0;

      for (final title in titleList) {
        if (_shouldStop(runGeneration)) return;
        final localPage = localMetadata[title];

        if (localPage == null) {
          // New page
          pagesToUpdate.add(title);
        } else if (localPage.hasFailures) {
          // Existed but contains failed chunk embeddings
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

      // Process pages in batches of 10 to limit memory consumption and avoid locking SQLite too long
      const crawlBatchSize = 10;
      for (var i = 0; i < pagesToUpdate.length; i += crawlBatchSize) {
        if (_shouldStop(runGeneration)) return;
        final batch = pagesToUpdate.sublist(
          i,
          i + crawlBatchSize > pagesToUpdate.length
              ? pagesToUpdate.length
              : i + crawlBatchSize,
        );

        final opBatch = <String>[];
        final storyBatch = <String>[]; // Story-only pages (主线/活动/干员密录)
        for (final title in batch) {
          if (site == WikiSite.prts && operatorTitles.contains(title)) {
            opBatch.add(title);
          } else {
            storyBatch.add(title);
          }
        }

        final wikiPages = <WikiPage>[];

        // 1. Fetch story pages via raw wikitext
        if (storyBatch.isNotEmpty) {
          final storyWikitexts =
              await _crawler.fetchRawWikitexts(site, storyBatch);
          if (_shouldStop(runGeneration)) return;
          for (final title in storyBatch) {
            final page = storyWikitexts[title];
            if (page != null) {
              wikiPages.add(page);
            }
          }
        }

        // 2. Fetch and assemble operator pages via raw wikitext
        if (opBatch.isNotEmpty) {
          final allOpTitlesToFetch = <String>[];
          for (final opTitle in opBatch) {
            allOpTitlesToFetch.add(opTitle);
            allOpTitlesToFetch.add('$opTitle/语音记录');
            allOpTitlesToFetch.add('${opTitle}的信物');
          }

          // Phase 1: Fetch operator main pages, voice lines, and token descriptions
          final wikitexts =
              await _crawler.fetchRawWikitexts(site, allOpTitlesToFetch);
          if (_shouldStop(runGeneration)) return;

          // Phase 1.5: Parse operator records to discover story page names
          final recordStoryTitles = <String>{};
          for (final opTitle in opBatch) {
            final mainPage = wikitexts[opTitle];
            if (mainPage == null) continue;
            final miluTemplates =
                parseAllTemplates(mainPage.content, '干员密录/list');
            for (final m in miluTemplates) {
              for (int j = 1; j <= 20; j++) {
                final rawPage = m['storyTxt$j'] ?? '';
                if (rawPage.isEmpty) break;
                final resolved =
                    rawPage.replaceAll('{{FULLPAGENAME}}', opTitle).trim();
                if (resolved.isNotEmpty) {
                  recordStoryTitles.add(resolved);
                }
              }
            }
          }

          // Phase 2: Fetch operator record story pages
          final recordStoryWikitexts = <String, String>{};
          if (recordStoryTitles.isNotEmpty) {
            final recordPages = await _crawler.fetchRawWikitexts(
                site, recordStoryTitles.toList());
            if (_shouldStop(runGeneration)) return;
            for (final entry in recordPages.entries) {
              if (entry.value.content.isNotEmpty) {
                recordStoryWikitexts[entry.value.title] = entry.value.content;
              }
            }
          }

          for (final opTitle in opBatch) {
            final mainPage = wikitexts[opTitle];
            final voicePage = wikitexts['$opTitle/语音记录'];
            final tokenPage = wikitexts['${opTitle}的信物'];

            if (mainPage != null) {
              final assembledContent = assembleOperatorMarkdown(
                opTitle,
                mainPage.content,
                voicePage?.content ?? '',
                tokenPage?.content ?? '',
                recordStoryWikitexts: recordStoryWikitexts,
              );

              wikiPages.add(WikiPage(
                pageId: mainPage.pageId,
                title: opTitle,
                content: assembledContent,
              ));
            }
          }
        }

        for (final page in wikiPages) {
          if (_shouldStop(runGeneration)) return;
          state = state.copyWith(currentItemTitle: page.title);

          // We delete the existing page chunks before writing new ones to prevent leftovers
          await _vectorStore.deleteWikiPage(
            site.key,
            page.title,
            profileId: _profileId,
          );
          await _deleteRawWikiPage(site.key, page.title);

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
            finalContent = cleanStoryContent(page.content);
          }

          await _saveRawWikiPage(site.key, page.title, finalContent);

          final chunks =
              chunker.chunkByHeadings(finalContent, pageTitle: page.title);
          if (chunks.isNotEmpty) {
            final texts = chunks.map((c) => c.content).toList();
            final embedResult = await _embedder.embedBatch(texts);
            if (_shouldStop(runGeneration)) return;

            if (embedResult.vectors.isNotEmpty) {
              await _ref
                  .read(embeddingSettingsProvider.notifier)
                  .updateActiveProfileDimension(_embedder.detectedDimension);
              await _vectorStore.insertChunks(
                chunks,
                embedResult.vectors,
                sourceType: 'wiki',
                sourceUrl: site == WikiSite.prts
                    ? 'https://prts.wiki/w/${Uri.encodeComponent(page.title)}'
                    : 'https://warfarin.wiki/cn/${Uri.encodeComponent(page.title)}',
                wiki: site.key,
                profileId: _profileId,
              );
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
      if (_shouldStop(runGeneration)) return;
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
      final failedChunks = await _vectorStore.getFailedChunks(
        profileId: _profileId,
      );
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
          final embedding =
              j < embedResult.vectors.length ? embedResult.vectors[j] : null;

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
  static String cleanStoryContent(String rawContent) =>
      prts.cleanStoryContent(rawContent);

  /// Parses all occurrences of a template in a mediawiki wikitext.
  static List<Map<String, String>> parseAllTemplates(
    String wikitext,
    String templateName, {
    bool exactMatch = true,
  }) =>
      prts.parseAllTemplates(wikitext, templateName, exactMatch: exactMatch);

  /// Parses the first occurrence of a template, falling back to empty map if not found.
  static Map<String, String> parseTemplate(
          String wikitext, String templateName) =>
      prts.parseTemplate(wikitext, templateName);

  /// Cleans wikitext/HTML styling markup to obtain pure readable text.
  static String cleanFormattedText(String text) =>
      prts.cleanFormattedText(text);

  /// Assembles operator raw wikitexts (main page, voice, token) into a unified markdown.
  static String assembleOperatorMarkdown(
    String operatorName,
    String mainWikitext,
    String voiceWikitext,
    String tokenWikitext, {
    Map<String, String>? recordStoryWikitexts,
  }) =>
      prts.assembleOperatorMarkdown(
        operatorName,
        mainWikitext,
        voiceWikitext,
        tokenWikitext,
        recordStoryWikitexts: recordStoryWikitexts,
      );

  /// Synchronizes data incrementally from warfarin.wiki for Endfield.
  Future<void> _indexEndfield(WikiSite site) async {
    state = WikiIndexingState(
      status: WikiIndexingStatus.starting,
      currentSiteName: site.displayName,
    );

    final warfarinCrawler = WarfarinWikiCrawler();

    try {
      await _runIndexEndfield(site, warfarinCrawler)
          .timeout(const Duration(minutes: 30));
    } on TimeoutException {
      if (!_cancelled) {
        debugPrint('[IndexEndfield] Timeout after 30 minutes');
        state = state.copyWith(
          status: WikiIndexingStatus.failed,
          error: '索引进度超时，请检查网络连接后重试',
        );
      }
    } catch (e) {
      if (!_cancelled) {
        debugPrint('[IndexEndfield] Error: $e');
        state = state.copyWith(
          status: WikiIndexingStatus.failed,
          error: e.toString(),
        );
      }
    } finally {
      warfarinCrawler.dispose();
      _cancelled = false;
    }
  }

  /// The actual indexing body for Endfield, extracted for timeout wrapping.
  Future<void> _runIndexEndfield(
      WikiSite site, WarfarinWikiCrawler warfarinCrawler) async {
    // Step 1: Fetch all directories with fine progress
    state = state.copyWith(
      status: WikiIndexingStatus.fetchingTitles,
      currentItemTitle: '正在获取干员列表...',
    );

    final List<WarfarinListingItem> opItems;
    final List<WarfarinListingItem> loreItems;
    final List<WarfarinListingItem> missionItems;

    try {
      opItems = await warfarinCrawler.fetchOperatorListings();
      if (_cancelled) return;
      state = state.copyWith(currentItemTitle: '正在获取资料列表...');
      loreItems = await warfarinCrawler.fetchLoreListings();
      if (_cancelled) return;
      state = state.copyWith(currentItemTitle: '正在获取任务列表...');
      missionItems = await warfarinCrawler.fetchMissionListings();
      if (_cancelled) return;
    } catch (e) {
      throw Exception('Failed to fetch data lists from Warfarin Wiki: $e');
    }

    final Map<String, _EndfieldTask> allTasks = {};
    for (final item in opItems) {
      allTasks[item.name.isNotEmpty ? item.name : item.slug] = _EndfieldTask(
        slug: item.slug,
        displayName: item.name.isNotEmpty ? item.name : item.slug,
        type: _EndfieldType.operator,
      );
    }
    for (final item in loreItems) {
      allTasks[item.name.isNotEmpty ? item.name : item.slug] = _EndfieldTask(
        slug: item.slug,
        displayName: item.name.isNotEmpty ? item.name : item.slug,
        type: _EndfieldType.lore,
      );
    }
    for (final item in missionItems) {
      allTasks[item.name.isNotEmpty ? item.name : item.slug] = _EndfieldTask(
        slug: item.slug,
        displayName: item.name.isNotEmpty ? item.name : item.slug,
        type: _EndfieldType.mission,
      );
    }

    if (allTasks.isEmpty) {
      if (_cancelled) return;
      state = state.copyWith(
        status: WikiIndexingStatus.failed,
        error: '华法琳 Wiki 目录解析为空，无法索引，可能是数据结构变化',
      );
      return;
    }

    state = state.copyWith(
      currentItemTitle:
          '已发现 干员 ${opItems.length} / 资料 ${loreItems.length} / 任务 ${missionItems.length}',
    );

    // Step 2: Clean up obsolete pages in local DB
    state = state.copyWith(status: WikiIndexingStatus.cleaningUp);
    final localMetadata = await _vectorStore.getWikiPagesMetadata(
      site.key,
      profileId: _profileId,
    );
    var cleanedCount = 0;
    for (final localTitle in localMetadata.keys) {
      if (!allTasks.containsKey(localTitle)) {
        await _vectorStore.deleteWikiPage(
          site.key,
          localTitle,
          profileId: _profileId,
        );
        await _deleteRawWikiPage(site.key, localTitle);
        cleanedCount++;
      }
    }
    if (cleanedCount > 0) {
      debugPrint('[IndexEndfield] Cleaned up $cleanedCount obsolete pages');
    }
    if (_cancelled) return;

    // Step 3: Incremental Sync Checks & Embedding
    state = state.copyWith(
      status: WikiIndexingStatus.embedding,
      totalCount: allTasks.length,
      processedCount: 0,
      skippedCount: 0,
    );

    final chunker = const Chunker();
    var processed = 0;
    var skipped = 0;
    var emptyFormatted = 0;
    var fetchFailed = 0;

    for (final title in allTasks.keys) {
      if (_cancelled) return;
      final task = allTasks[title]!;
      final typePrefix = task.type == _EndfieldType.operator
          ? '干员'
          : task.type == _EndfieldType.lore
              ? '资料'
              : '任务';

      // Check local status first
      final localPage = localMetadata[title];
      if (localPage != null && !localPage.hasFailures) {
        skipped++;
        processed++;
        state = state.copyWith(
          skippedCount: skipped,
          processedCount: processed,
          progress: (processed / allTasks.length).clamp(0.0, 1.0),
          currentItemTitle: '跳过 $typePrefix/${task.displayName}',
        );
        continue;
      }

      // Fetch detail only for new pages or pages with failed embeddings.
      state = state.copyWith(
        currentItemTitle: '下载 $typePrefix/${task.displayName}',
      );

      Map<String, dynamic>? detail;
      try {
        if (task.type == _EndfieldType.operator) {
          detail = await warfarinCrawler.fetchOperatorDetail(task.slug);
        } else if (task.type == _EndfieldType.lore) {
          detail = await warfarinCrawler.fetchLoreDetail(task.slug);
        } else {
          detail = await warfarinCrawler.fetchMissionDetail(task.slug);
        }
      } catch (e) {
        debugPrint('Failed to fetch details for $title: $e');
        fetchFailed++;
        processed++;
        state = state.copyWith(
          processedCount: processed,
          progress: (processed / allTasks.length).clamp(0.0, 1.0),
        );
        continue;
      }

      // Compare with local metadata
      final isNew = localPage == null;

      state = state.copyWith(
        currentItemTitle: '转换 $typePrefix/${task.displayName}',
      );

      // Format to Markdown
      String markdown = '';
      if (task.type == _EndfieldType.operator) {
        markdown = warfarinCrawler.formatOperatorToMarkdown(detail);
      } else if (task.type == _EndfieldType.lore) {
        markdown = warfarinCrawler.formatLoreToMarkdown(detail);
      } else {
        markdown = warfarinCrawler.formatMissionToMarkdown(detail);
      }

      if (markdown.isEmpty) {
        emptyFormatted++;
        processed++;
        state = state.copyWith(
          processedCount: processed,
          progress: (processed / allTasks.length).clamp(0.0, 1.0),
        );
        continue;
      }

      // Delete old chunks if exists
      if (!isNew) {
        await _vectorStore.deleteWikiPage(
          site.key,
          title,
          profileId: _profileId,
        );
        await _deleteRawWikiPage(site.key, title);
      }

      await _saveRawWikiPage(site.key, title, markdown);

      state = state.copyWith(
        currentItemTitle: '分块 $typePrefix/${task.displayName}',
      );

      // Chunker -> Embed -> Store
      final chunks = chunker.chunkByHeadings(markdown, pageTitle: title);
      if (chunks.isNotEmpty) {
        state = state.copyWith(
          currentItemTitle:
              '向量 $typePrefix/${task.displayName} ($processed/${allTasks.length})',
        );
        final texts = chunks.map((c) => c.content).toList();
        final embedResult = await _embedder.embedBatch(texts);

        if (embedResult.vectors.isNotEmpty) {
          await _ref
              .read(embeddingSettingsProvider.notifier)
              .updateActiveProfileDimension(_embedder.detectedDimension);
          await _vectorStore.insertChunks(
            chunks,
            embedResult.vectors,
            sourceType: 'wiki',
            sourceUrl: _getEndfieldSourceUrl(task),
            wiki: site.key,
            profileId: _profileId,
          );
        }
      }

      processed++;
      state = state.copyWith(
        processedCount: processed,
        progress: (processed / allTasks.length).clamp(0.0, 1.0),
      );

      // Rate limit delay to respect the server guidelines
      await Future.delayed(warfarinCrawler.requestDelay);
    }

    if (_cancelled) return;
    _ref.invalidate(vectorStoreStatsProvider);

    final statusNotes = <String>[];
    if (emptyFormatted > 0) {
      statusNotes.add('$emptyFormatted 个条目格式化为空');
    }
    if (fetchFailed > 0) {
      statusNotes.add('$fetchFailed 个条目下载失败');
    }
    final note = statusNotes.isNotEmpty ? '（${statusNotes.join("，")}）' : '';

    state = state.copyWith(
      status: WikiIndexingStatus.completed,
      progress: 1.0,
      currentItemTitle: note,
    );
  }

  String _getEndfieldSourceUrl(_EndfieldTask task) {
    final path = task.type == _EndfieldType.operator
        ? 'operators'
        : task.type == _EndfieldType.lore
            ? 'lore'
            : 'missions';
    return 'https://warfarin.wiki/cn/$path/${Uri.encodeComponent(task.slug)}';
  }

  Future<Directory> _getWikiCacheDirectory() async {
    if (Platform.isAndroid) {
      final extDir = await getExternalStorageDirectory();
      if (extDir != null) return extDir;
    }
    return await getApplicationDocumentsDirectory();
  }

  Future<void> _saveRawWikiPage(
      String wiki, String title, String content) async {
    try {
      final dir = await _getWikiCacheDirectory();
      final sanitizedTitle = title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final file = File('${dir.path}/wiki_cache/$wiki/$sanitizedTitle.md');
      await file.parent.create(recursive: true);
      await file.writeAsString(content);
      debugPrint('[WikiIndexing] Saved raw page to ${file.path}');
    } catch (e) {
      debugPrint('[WikiIndexing] Failed to save raw page: $e');
    }
  }

  Future<void> _deleteRawWikiPage(String wiki, String title) async {
    try {
      final dir = await _getWikiCacheDirectory();
      final sanitizedTitle = title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final file = File('${dir.path}/wiki_cache/$wiki/$sanitizedTitle.md');
      if (await file.exists()) {
        await file.delete();
        debugPrint('[WikiIndexing] Deleted raw page file: ${file.path}');
      }
    } catch (e) {
      debugPrint('[WikiIndexing] Failed to delete raw page: $e');
    }
  }
}

enum _EndfieldType { operator, lore, mission }

class _EndfieldTask {
  final String slug;
  final String displayName;
  final _EndfieldType type;

  _EndfieldTask({
    required this.slug,
    this.displayName = '',
    required this.type,
  });
}
