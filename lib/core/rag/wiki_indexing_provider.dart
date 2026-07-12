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
      final operatorTitles = <String>{};
      for (final category in categories) {
        final titles = await _crawler.fetchCategoryTitles(
          site: site,
          categoryName: category,
        );
        if (category == 'Category:干员') {
          operatorTitles.addAll(titles);
        }
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

        final opBatch = <String>[];
        final normalBatch = <String>[];
        for (final title in batch) {
          if (site == WikiSite.prts && operatorTitles.contains(title)) {
            opBatch.add(title);
          } else {
            normalBatch.add(title);
          }
        }

        final wikiPages = <WikiPage>[];

        // 1. Fetch normal pages via standard prop=extracts
        if (normalBatch.isNotEmpty) {
          final normalPages = await _crawler.fetchPageContents(site, normalBatch);
          wikiPages.addAll(normalPages);
        }

        // 2. Fetch and assemble operator pages via raw wikitext
        if (opBatch.isNotEmpty) {
          final allOpTitlesToFetch = <String>[];
          for (final opTitle in opBatch) {
            allOpTitlesToFetch.add(opTitle);
            allOpTitlesToFetch.add('$opTitle/语音记录');
            allOpTitlesToFetch.add('${opTitle}的信物');
          }

          final wikitexts = await _crawler.fetchRawWikitexts(site, allOpTitlesToFetch);

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
            finalContent = cleanStoryContent(page.content);
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
  static String cleanStoryContent(String rawContent) {
    var content = rawContent;

    // 1. Truncate at [Image] or [image] tag to discard huge list of media URL lines.
    // We use a RegExp to match only standalone '[Image]' or '[image]' lines to prevent
    // false positives on mid-story picture macros like [image="..."] or [Image(...)].
    final match = RegExp(r'\n\[[Ii]mage\](?:\r?\n|$)').firstMatch(content);
    if (match != null) {
      content = content.substring(0, match.start);
    }

    // 2. Extract and keep character names inside [name="..."] tags before stripping brackets
    content = content.replaceAllMapped(
      RegExp(r'\[name="([^"]+)"\]\s*'),
      (match) => '${match.group(1)}：',
    );

    // 3. Remove HTML comments
    content = content.replaceAll(RegExp(r'<!--[\s\S]*?-->'), '');

    // 4. Remove plot navigator templates (e.g. {{Navigator/plot|...}})
    content = content.replaceAll(RegExp(r'\{\{[Nn]avigator/[^}]*\}\}'), '');
    content = content.replaceAll(RegExp(r'\{\{[Pp]lot[^}]*\}\}'), '');

    // 5. Remove story simulator headers / starts
    content = content.replaceAll(RegExp(r'\{\{剧情模拟器[^}]*'), '');

    // 6. Remove game scripting macro instructions (typically enclosed in square brackets)
    content = content.replaceAll(RegExp(r'\[[A-Za-z0-9_]+(?:\([^)]*\))?\]'), '');
    content = content.replaceAll(RegExp(r'\[[A-Za-z_]+=[^\]]*\]'), '');

    // 7. Remove any other square bracket command lines
    content = content.replaceAll(RegExp(r'\[[A-Za-z0-9_]+.*?\]'), '');

    // 8. Split, trim, and filter out structural template residues
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

  /// Parses all occurrences of a template in a mediawiki wikitext.
  ///
  /// Returns a list of maps, where each map contains the key-value parameters
  /// parsed from one template call. Supports nested curly/square brackets.
  static List<Map<String, String>> parseAllTemplates(String wikitext, String templateName) {
    final results = <Map<String, String>>[];
    final startKey = '{{$templateName';
    
    int searchOffset = 0;
    while (true) {
      int startIdx = wikitext.indexOf(startKey, searchOffset);
      if (startIdx == -1) {
        startIdx = wikitext.toLowerCase().indexOf(startKey.toLowerCase(), searchOffset);
        if (startIdx == -1) break;
      }
      
      // Find matching closing }}
      int depth = 0;
      int endIdx = -1;
      for (int i = startIdx; i < wikitext.length - 1; i++) {
        if (wikitext[i] == '{' && wikitext[i+1] == '{') {
          depth++;
          i++;
        } else if (wikitext[i] == '}' && wikitext[i+1] == '}') {
          depth--;
          if (depth == 0) {
            endIdx = i + 2;
            break;
          }
          i++;
        }
      }
      
      if (endIdx == -1) {
        // malformed template, move past startKey to prevent infinite loop
        searchOffset = startIdx + startKey.length;
        continue;
      }
      
      final body = wikitext.substring(startIdx + startKey.length, endIdx - 2);
      final params = <String, String>{};
      final parts = <String>[];
      int currentStart = 0;
      int bracketDepth = 0;
      int squareBracketDepth = 0;
      for (int i = 0; i < body.length; i++) {
        final c = body[i];
        if (c == '{' && i < body.length - 1 && body[i+1] == '{') {
          bracketDepth++;
          i++;
        } else if (c == '}' && i < body.length - 1 && body[i+1] == '}') {
          bracketDepth--;
          i++;
        } else if (c == '[' && i < body.length - 1 && body[i+1] == '[') {
          squareBracketDepth++;
          i++;
        } else if (c == ']' && i < body.length - 1 && body[i+1] == ']') {
          squareBracketDepth--;
          i++;
        } else if (c == '|' && bracketDepth == 0 && squareBracketDepth == 0) {
          parts.add(body.substring(currentStart, i));
          currentStart = i + 1;
        }
      }
      parts.add(body.substring(currentStart));
      
      for (final part in parts) {
        final eqIdx = part.indexOf('=');
        if (eqIdx != -1) {
          final name = part.substring(0, eqIdx).trim();
          final val = part.substring(eqIdx + 1).trim();
          if (name.isNotEmpty) {
            params[name] = val;
          }
        }
      }
      
      results.add(params);
      searchOffset = endIdx;
    }
    
    return results;
  }

  /// Parses the first occurrence of a template, falling back to empty map if not found.
  static Map<String, String> parseTemplate(String wikitext, String templateName) {
    final list = parseAllTemplates(wikitext, templateName);
    return list.isEmpty ? <String, String>{} : list.first;
  }

  /// Cleans wikitext/HTML styling markup to obtain pure readable text.
  static String cleanFormattedText(String text) {
    var clean = text;
    // 1. Remove {{color|#XXXXXX|...}}
    clean = clean.replaceAllMapped(
      RegExp(r'\{\{[Cc]olor\|#[0-9A-Fa-f]{6}\|([^}]+)\}\}'),
      (m) => m.group(1)!,
    );
    // 2. Remove {{术语|...|...}}
    clean = clean.replaceAllMapped(
      RegExp(r'\{\{术语\|[^|]*\|([^}]+)\}\}'),
      (m) => m.group(1)!,
    );
    // 3. Remove {{popup|内容=...}}
    clean = clean.replaceAll(RegExp(r'\{\{popup\|内容=[^}]*\}\}'), '');
    // 4. Remove html-like tags
    clean = clean.replaceAll(RegExp(r'<[^>]*>'), '');
    // 5. Remove double brackets [[...]]
    clean = clean.replaceAllMapped(
      RegExp(r'\[\[(?:[^|\]]*\|)?([^\]]+)\]\]'),
      (m) => m.group(1)!,
    );
    // 6. Remove remaining simple templates
    clean = clean.replaceAll(RegExp(r'\{\{[^{}]*\}\}'), '');
    return clean.trim();
  }

  /// Assembles operator raw wikitexts (main page, voice, token) into a unified markdown.
  static String assembleOperatorMarkdown(
    String operatorName,
    String mainWikitext,
    String voiceWikitext,
    String tokenWikitext,
  ) {
    final sb = StringBuffer();
    sb.writeln('# $operatorName\n');

    // --- 1. Parse Operator Archives ---
    final archivesSet = parseTemplate(mainWikitext, '人员档案set');
    final archives = parseTemplate(mainWikitext, '人员档案');

    sb.writeln('## 个人档案');
    final basicFields = {
      '性别': '性别',
      '战斗经验': '战斗经验',
      '出身地': '出身地',
      '生日': '生日',
      '种族': '种族',
      '身高': '身高',
      '矿石病感染情况': '矿石病感染情况',
      '物理强度': '物理强度',
      '战场机动': '战场机动',
      '生理耐受': '生理耐受',
      '战术规划': '战术规划',
      '战斗技巧': '战斗技巧',
      '源石技艺适应性': '源石技艺适应性',
      '体细胞与源石融合率': '体细胞与源石融合率',
      '血液源石结晶密度': '血液源石结晶密度',
    };

    for (final entry in basicFields.entries) {
      final val = archivesSet[entry.key];
      if (val != null && val.trim().isNotEmpty) {
        sb.writeln('- ${entry.value}：${val.trim()}');
      }
    }
    sb.writeln('');

    // Iterate archives 1..15
    for (int i = 1; i <= 15; i++) {
      final title = archives['档案$i'];
      final text = archives['档案${i}文本'];
      if (title != null && title.trim().isNotEmpty && text != null && text.trim().isNotEmpty) {
        sb.writeln('### ${title.trim()}');
        sb.writeln('${text.trim()}\n');
      }
    }

    // --- 2. Parse Talents ---
    final talentTemplates = parseAllTemplates(mainWikitext, '天赋列表3');
    if (talentTemplates.isNotEmpty) {
      sb.writeln('## 天赋设定');
      for (final t in talentTemplates) {
        final name = t['天赋1'] ?? '';
        final category = t['天赋'] ?? '';
        if (name.isNotEmpty) {
          sb.writeln('### $category：$name');
          for (int j = 1; j <= 10; j++) {
            final cond = t['天赋$j条件'] ?? '';
            final eff = t['天赋$j效果'] ?? '';
            if (eff.isNotEmpty) {
              final condStr = cond.isNotEmpty ? '（$cond）' : '';
              sb.writeln('- 效果$condStr：${cleanFormattedText(eff)}');
            }
          }
          sb.writeln('');
        }
      }
    }

    // --- 3. Parse Skills ---
    final skillTemplates = parseAllTemplates(mainWikitext, '技能');
    if (skillTemplates.isNotEmpty) {
      sb.writeln('## 技能设定');
      for (final s in skillTemplates) {
        final name = s['技能名'] ?? '';
        if (name.isNotEmpty) {
          sb.writeln('### 技能：$name');
          final type1 = s['技能类型1'] ?? '';
          final type2 = s['技能类型2'] ?? '';
          if (type1.isNotEmpty || type2.isNotEmpty) {
            sb.writeln('- 类型：$type1 / $type2');
          }
          final desc7 = s['技能7描述'] ?? '';
          final descM3 = s['技能专精3描述'] ?? '';
          if (desc7.isNotEmpty) {
            sb.writeln('- 7级效果：${cleanFormattedText(desc7)}');
          }
          if (descM3.isNotEmpty) {
            sb.writeln('- 专精3效果：${cleanFormattedText(descM3)}');
          }
          sb.writeln('');
        }
      }
    }

    // --- 4. Parse RIIC/Base Skills ---
    final baseTemplates = parseAllTemplates(mainWikitext, '后勤技能');
    if (baseTemplates.isNotEmpty) {
      sb.writeln('## 后勤技能');
      for (final b in baseTemplates) {
        for (int j = 1; j <= 5; j++) {
          for (int k = 1; k <= 5; k++) {
            final name = b['后勤技能$j-$k'];
            final phase = b['后勤技能$j-${k}阶段'] ?? '';
            if (name != null && name.trim().isNotEmpty) {
              final phaseStr = phase.isNotEmpty ? '（$phase）' : '';
              sb.writeln('- 后勤技能$phaseStr：${name.trim()}');
            }
          }
        }
      }
      sb.writeln('');
    }

    // --- 5. Parse Modules ---
    final moduleTemplates = parseAllTemplates(mainWikitext, '模组');
    if (moduleTemplates.isNotEmpty) {
      sb.writeln('## 模组设定');
      for (final m in moduleTemplates) {
        final name = m['名称'] ?? '';
        final info = m['基础信息'] ?? '';
        if (name.isNotEmpty) {
          sb.writeln('### 模组：$name');
          if (info.isNotEmpty) {
            final cleanInfo = cleanFormattedText(info.replaceAll('<br>', '\n').replaceAll('<br/>', '\n'));
            sb.writeln('$cleanInfo\n');
          }
        }
      }
    }

    // --- 6. Parse Paradox Simulation ---
    final paradoxTemplates = parseAllTemplates(mainWikitext, '悖论模拟');
    if (paradoxTemplates.isNotEmpty) {
      sb.writeln('## 悖论模拟');
      for (final p in paradoxTemplates) {
        final name = p['name'] ?? '';
        final desc = p['description'] ?? '';
        if (name.isNotEmpty) {
          sb.writeln('### 悖论模拟：$name');
          if (desc.isNotEmpty) {
            sb.writeln('${cleanFormattedText(desc)}\n');
          }
        }
      }
    }

    // --- 7. Parse Operator Records List ---
    final miluTemplates = parseAllTemplates(mainWikitext, '干员密录/list');
    if (miluTemplates.isNotEmpty) {
      sb.writeln('## 干员密录一览');
      for (final m in miluTemplates) {
        final name = m['storySetName'] ?? '';
        final intro = m['storyIntro1'] ?? '';
        final page = m['storyTxt1'] ?? '';
        if (name.isNotEmpty) {
          final resolvedPage = page.replaceAll('{{FULLPAGENAME}}', operatorName).trim();
          sb.writeln('### 干员密录：$name');
          if (intro.isNotEmpty) {
            sb.writeln('- 介绍：${cleanFormattedText(intro)}');
          }
          if (resolvedPage.isNotEmpty) {
            sb.writeln('- 剧情页面：$resolvedPage');
          }
          sb.writeln('');
        }
      }
    }

    // --- 8. Parse Token Description ---
    if (tokenWikitext.isNotEmpty) {
      final tokenInfo = parseTemplate(tokenWikitext, '道具信息');
      final desc = tokenInfo['描述'];
      final usage = tokenInfo['用途'];
      final source = tokenInfo['获得方式'];

      if ((desc != null && desc.trim().isNotEmpty) ||
          (usage != null && usage.trim().isNotEmpty) ||
          (source != null && source.trim().isNotEmpty)) {
        sb.writeln('## 信物描述');
        if (desc != null && desc.trim().isNotEmpty) {
          var cleanDesc = desc.trim();
          if (cleanDesc.startsWith('"') && cleanDesc.endsWith('"')) {
            cleanDesc = cleanDesc.substring(1, cleanDesc.length - 1);
          } else if (cleanDesc.startsWith('“') && cleanDesc.endsWith('”')) {
            cleanDesc = cleanDesc.substring(1, cleanDesc.length - 1);
          }
          sb.writeln('信物文案：“$cleanDesc”');
        }
        if (usage != null && usage.trim().isNotEmpty) {
          sb.writeln('- 用途：${usage.trim()}');
        }
        if (source != null && source.trim().isNotEmpty) {
          sb.writeln('- 获得方式：${source.trim()}');
        }
        sb.writeln('');
      }
    }

    // --- 9. Parse Voice Records ---
    if (voiceWikitext.isNotEmpty) {
      final voiceTable = parseTemplate(voiceWikitext, 'VoiceTable');
      final voiceList = <String>[];

      // Iterate voice lines 1..100
      for (int i = 1; i <= 100; i++) {
        final title = voiceTable['标题$i'];
        final rawDialogue = voiceTable['台词$i'];
        if (title != null && title.trim().isNotEmpty && rawDialogue != null && rawDialogue.trim().isNotEmpty) {
          // Extract Chinese dialogue from {{VoiceData/word|中文|...}}
          final match = RegExp(r'\{\{VoiceData/word\|中文\|([^}]+)\}\}').firstMatch(rawDialogue);
          if (match != null) {
            final cnDialogue = match.group(1)!.trim();
            voiceList.add('- ${title.trim()}：$cnDialogue');
          } else {
            // Fallback
            if (!rawDialogue.contains('{{VoiceData/word')) {
              voiceList.add('- ${title.trim()}：${rawDialogue.trim()}');
            }
          }
        }
      }

      if (voiceList.isNotEmpty) {
        sb.writeln('## 语音记录');
        for (final voice in voiceList) {
          sb.writeln(voice);
        }
        sb.writeln('');
      }
    }

    return sb.toString().trim();
  }
}
