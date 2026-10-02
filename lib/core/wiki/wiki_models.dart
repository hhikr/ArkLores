/// Supported Wiki sites.
enum WikiSite {
  prts('prts', 'https://prts.wiki/api.php'),
  endfield('endfield', 'https://warfarin.wiki/cn');

  const WikiSite(this.key, this.apiUrl);

  final String key;
  final String apiUrl;

  String get displayName {
    switch (this) {
      case WikiSite.prts:
        return 'PRTS Wiki';
      case WikiSite.endfield:
        return '华法琳Wiki';
    }
  }
}

/// A single Wiki page with its title and extracted text content.
class WikiPage {

  const WikiPage({
    required this.pageId,
    required this.title,
    required this.content,
  });

  factory WikiPage.fromMap(Map<String, dynamic> map) => WikiPage(
        pageId: map['page_id'] as int,
        title: map['title'] as String,
        content: map['content'] as String,
      );
  final int pageId;
  final String title;
  final String content;

  Map<String, dynamic> toMap() => {
        'page_id': pageId,
        'title': title,
        'content': content,
      };
}

/// Progress reported during a crawl operation.
class CrawlProgress {

  const CrawlProgress({
    this.pagesFetched = 0,
    this.totalPages = 0,
    this.currentTitle = '',
    this.isComplete = false,
    this.error,
  });
  final int pagesFetched;
  final int totalPages;
  final String currentTitle;
  final bool isComplete;
  final String? error;

  double get fraction =>
      totalPages > 0 ? (pagesFetched / totalPages).clamp(0.0, 1.0) : 0.0;

  CrawlProgress copyWith({
    int? pagesFetched,
    int? totalPages,
    String? currentTitle,
    bool? isComplete,
    String? error,
  }) =>
      CrawlProgress(
        pagesFetched: pagesFetched ?? this.pagesFetched,
        totalPages: totalPages ?? this.totalPages,
        currentTitle: currentTitle ?? this.currentTitle,
        isComplete: isComplete ?? this.isComplete,
        error: error ?? this.error,
      );
}
