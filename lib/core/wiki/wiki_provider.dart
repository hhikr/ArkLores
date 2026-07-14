import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'wiki_crawler.dart';
import 'wiki_models.dart';

/// Provider for a singleton [MediaWikiCrawler] instance.
final wikiCrawlerProvider = Provider<MediaWikiCrawler>((ref) {
  final crawler = MediaWikiCrawler();
  ref.onDispose(() => crawler.dispose());
  return crawler;
});

/// State holder for an ongoing or completed crawl operation.
class CrawlState {
  final List<WikiPage> pages;
  final CrawlProgress progress;
  final bool isRunning;
  final String? error;

  const CrawlState({
    this.pages = const [],
    this.progress = const CrawlProgress(),
    this.isRunning = false,
    this.error,
  });

  CrawlState copyWith({
    List<WikiPage>? pages,
    CrawlProgress? progress,
    bool? isRunning,
    String? error,
  }) =>
      CrawlState(
        pages: pages ?? this.pages,
        progress: progress ?? this.progress,
        isRunning: isRunning ?? this.isRunning,
        error: error,
      );
}

/// Notifier that manages wiki crawl operations.
class CrawlNotifier extends StateNotifier<CrawlState> {
  final MediaWikiCrawler _crawler;

  CrawlNotifier(this._crawler) : super(const CrawlState());

  /// Crawls all pages under the given category on [site].
  Future<List<WikiPage>> crawlCategory({
    required WikiSite site,
    required String categoryName,
  }) async {
    if (state.isRunning) return state.pages;

    state = state.copyWith(isRunning: true, error: null);

    try {
      final pages = await _crawler.crawlCategory(
        site: site,
        categoryName: categoryName,
        onProgress: (progress) {
          state = state.copyWith(
            progress: progress,
            pages: [...state.pages, ...(progress.isComplete ? [] : [])],
          );
        },
      );

      state = CrawlState(
        pages: pages,
        progress: CrawlProgress(
          pagesFetched: pages.length,
          totalPages: pages.length,
          isComplete: true,
        ),
      );

      return pages;
    } catch (e) {
      state = state.copyWith(
        isRunning: false,
        error: e.toString(),
      );
      rethrow;
    }
  }

  /// Resets the crawl state.
  void reset() {
    state = const CrawlState();
  }
}

/// Provider for wiki crawl state and operations.
final crawlProvider = StateNotifierProvider<CrawlNotifier, CrawlState>((ref) {
  final crawler = ref.watch(wikiCrawlerProvider);
  return CrawlNotifier(crawler);
});

/// Shortcut provider that exposes crawl progress fraction for UI binding.
final crawlProgressFractionProvider = Provider<double>((ref) {
  final state = ref.watch(crawlProvider);
  return state.progress.fraction;
});
