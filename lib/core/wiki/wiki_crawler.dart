import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'wiki_models.dart';

/// MediaWiki API crawler that fetches page content from PRTS Wiki
/// and Endfield Wiki.
///
/// Uses `action=query&prop=extracts&explaintext=true` to obtain
/// plain text content directly (no Wikitext parsing needed).
class MediaWikiCrawler {
  final http.Client _httpClient;
  final Duration _requestDelay;

  /// Maximum pages per batch request.
  static const int _batchSize = 50;

  MediaWikiCrawler({
    http.Client? httpClient,
    Duration? requestDelay,
  })  : _httpClient = httpClient ?? http.Client(),
        _requestDelay = requestDelay ?? const Duration(milliseconds: 200);

  /// Fetches only the titles of pages belonging to a category.
  ///
  /// This is extremely lightweight as it fetches no page content, serving
  /// as the first step of our incremental crawler checks.
  Future<List<String>> fetchCategoryTitles({
    required WikiSite site,
    required String categoryName,
  }) async {
    final titles = <String>[];
    String? continueToken;

    do {
      final params = <String, String>{
        'action': 'query',
        'format': 'json',
        'list': 'categorymembers',
        'cmtitle': categoryName,
        'cmlimit': '500', // MediaWiki max for standard queries is 500
      };
      if (continueToken != null) {
        params['cmcontinue'] = continueToken;
      }

      final result = await _queryApi(site, params);
      final query = result['query'] as Map<String, dynamic>?;
      final members = query?['categorymembers'] as List<dynamic>? ?? [];

      for (final member in members) {
        final title = member['title'] as String? ?? '';
        if (title.isNotEmpty) {
          titles.add(title);
        }
      }

      final queryContinue = result['continue'] as Map<String, dynamic>?;
      continueToken = queryContinue?['cmcontinue'] as String?;

      if (continueToken != null) {
        await Future.delayed(_requestDelay);
      }
    } while (continueToken != null);

    return titles;
  }

  /// Fetches all pages under a given category.
  ///
  /// Calls [onProgress] after each batch with updated progress info.
  /// Returns the list of fetched [WikiPage]s.
  Future<List<WikiPage>> crawlCategory({
    required WikiSite site,
    required String categoryName,
    void Function(CrawlProgress)? onProgress,
  }) async {
    final pages = <WikiPage>[];
    String? continueToken;
    var fetched = 0;

    // Report initial progress (total pages unknown upfront).
    onProgress?.call(CrawlProgress(
      currentTitle: categoryName,
    ));

    // Fetch pages in batches.
    do {
      final params = <String, String>{
        'action': 'query',
        'format': 'json',
        'list': 'categorymembers',
        'cmtitle': categoryName,
        'cmlimit': '$_batchSize',
        'prop': 'info',
      };
      if (continueToken != null) {
        params['cmcontinue'] = continueToken;
      }

      final result = await _queryApi(site, params);
      final members = result['query']['categorymembers'] as List<dynamic>? ?? [];

      // Collect page titles from this batch.
      final titles = members
          .map((m) => m['title'] as String)
          .where((t) => t.isNotEmpty)
          .toList();

      if (titles.isNotEmpty) {
        // Fetch content for all titles in one batch request.
        final contentPages = await fetchPageContents(site, titles);

        for (final page in contentPages) {
          pages.add(page);
          fetched++;
          onProgress?.call(CrawlProgress(
            pagesFetched: fetched,
            currentTitle: page.title,
            isComplete: false,
          ));
        }
      }

      // Check for continuation token.
      final queryContinue = result['continue'] as Map<String, dynamic>?;
      continueToken = queryContinue?['cmcontinue'] as String?;

      // Rate limiting delay between requests.
      if (continueToken != null) {
        await Future.delayed(_requestDelay);
      }
    } while (continueToken != null);

    onProgress?.call(CrawlProgress(
      pagesFetched: fetched,
      totalPages: fetched,
      currentTitle: '',
      isComplete: true,
    ));

    return pages;
  }

  /// Fetches content for a list of page titles in one API call.
  Future<List<WikiPage>> fetchPageContents(
    WikiSite site,
    List<String> titles,
  ) async {
    if (titles.isEmpty) return [];

    final pages = <WikiPage>[];

    // Process in sub-batches to avoid URI too long errors.
    for (var i = 0; i < titles.length; i += _batchSize) {
      final batch = titles.sublist(
        i,
        (i + _batchSize > titles.length) ? titles.length : i + _batchSize,
      );

      final result = await _queryApi(site, {
        'action': 'query',
        'format': 'json',
        'titles': batch.join('|'),
        'prop': 'extracts',
        'explaintext': '1',
        'exlimit': 'max',
      });

      final query = result['query'] as Map<String, dynamic>?;
      final pagesJson = query?['pages'] as Map<String, dynamic>? ?? {};

      for (final entry in pagesJson.entries) {
        final pageData = entry.value as Map<String, dynamic>?;
        if (pageData == null) continue;
        // Skip missing/invalid pages.
        if (pageData.containsKey('missing') || pageData['pageid'] == null) continue;

        pages.add(WikiPage(
          pageId: pageData['pageid'] as int,
          title: pageData['title'] as String? ?? '',
          content: (pageData['extract'] as String?) ?? '',
        ));
      }

      // Delay between sub-batches.
      if (i + _batchSize < titles.length) {
        await Future.delayed(_requestDelay);
      }
    }

    return pages;
  }

  /// Fetches raw wikitext for a list of page titles in one API call.
  ///
  /// Returns a Map of page title -> WikiPage (containing pageId, title, content).
  /// Skips missing pages.
  Future<Map<String, WikiPage>> fetchRawWikitexts(
    WikiSite site,
    List<String> titles,
  ) async {
    if (titles.isEmpty) return {};

    final result = <String, WikiPage>{};

    // Process in sub-batches to avoid URI too long errors.
    for (var i = 0; i < titles.length; i += _batchSize) {
      final batch = titles.sublist(
        i,
        (i + _batchSize > titles.length) ? titles.length : i + _batchSize,
      );

      final response = await _queryApi(site, {
        'action': 'query',
        'format': 'json',
        'titles': batch.join('|'),
        'prop': 'revisions',
        'rvprop': 'content',
        'rvslots': 'main',
      });

      final query = response['query'] as Map<String, dynamic>?;
      final pagesJson = query?['pages'] as Map<String, dynamic>? ?? {};

      for (final entry in pagesJson.entries) {
        final pageData = entry.value as Map<String, dynamic>?;
        if (pageData == null) continue;
        if (pageData.containsKey('missing') || pageData['pageid'] == null) continue;

        final title = pageData['title'] as String? ?? '';
        final pageId = pageData['pageid'] as int;
        final revisions = pageData['revisions'] as List<dynamic>?;
        if (title.isNotEmpty && revisions != null && revisions.isNotEmpty) {
          final wikitext = revisions[0]['slots']?['main']?['*'] as String? ?? '';
          result[title] = WikiPage(
            pageId: pageId,
            title: title,
            content: wikitext,
          );
        }
      }

      // Delay between sub-batches.
      if (i + _batchSize < titles.length) {
        await Future.delayed(_requestDelay);
      }
    }

    return result;
  }

  /// Fetches the last modification (touched) timestamps for a list of page titles.
  ///
  /// Splits into batches of [_batchSize] to avoid URL length limitations.
  /// Returns a map of title -> last touched timestamp (seconds).
  Future<Map<String, int>> fetchPagesLastTouched(
    WikiSite site,
    List<String> titles,
  ) async {
    if (titles.isEmpty) return {};

    final result = <String, int>{};

    for (var i = 0; i < titles.length; i += _batchSize) {
      final batch = titles.sublist(
        i,
        (i + _batchSize > titles.length) ? titles.length : i + _batchSize,
      );

      final response = await _queryApi(site, {
        'action': 'query',
        'format': 'json',
        'titles': batch.join('|'),
        'prop': 'info',
      });

      final query = response['query'] as Map<String, dynamic>?;
      final pagesJson = query?['pages'] as Map<String, dynamic>? ?? {};

      for (final entry in pagesJson.entries) {
        final pageData = entry.value as Map<String, dynamic>?;
        if (pageData == null) continue;
        if (pageData['missing'] == true) continue;

        final title = pageData['title'] as String? ?? '';
        final touchedStr = pageData['touched'] as String? ?? '';

        if (title.isNotEmpty && touchedStr.isNotEmpty) {
          try {
            final parsedDate = DateTime.parse(touchedStr);
            result[title] = parsedDate.millisecondsSinceEpoch ~/ 1000;
          } catch (_) {
            // Fallback to 0 if parsing fails.
            result[title] = 0;
          }
        }
      }

      // Rate limiting delay.
      if (i + _batchSize < titles.length) {
        await Future.delayed(_requestDelay);
      }
    }

    return result;
  }

  /// Fetches a list of top-level category names for the given wiki site.
  Future<List<String>> fetchTopCategories(WikiSite site) async {
    final result = await _queryApi(site, {
      'action': 'query',
      'format': 'json',
      'list': 'allpages',
      'apnamespace': '14', // Category namespace
      'aplimit': 'max',
      'apfilterredir': 'nonredirects',
    });

    final pages = result['query']['allpages'] as List<dynamic>? ?? [];
    return pages
        .map((p) => p['title'] as String)
        .where((t) => t.startsWith('Category:'))
        .toList();
  }

  /// Sends a GET request to the wiki's API endpoint.
  Future<Map<String, dynamic>> _queryApi(
    WikiSite site,
    Map<String, String> params,
  ) async {
    final uri = Uri.parse(site.apiUrl).replace(queryParameters: params);

    final response = await _httpClient.get(
      uri,
      headers: {
        'User-Agent': 'ArkLores/0.3 (https://github.com/hhikr/ArkLores)',
      },
    ).timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      throw CrawlerException(
        'API request failed for ${site.displayName}',
        statusCode: response.statusCode,
        uri: uri.toString(),
      );
    }

    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// Releases HTTP client resources.
  void dispose() {
    _httpClient.close();
  }
}

/// Exception thrown by [MediaWikiCrawler].
class CrawlerException implements Exception {
  final String message;
  final int? statusCode;
  final String? uri;

  const CrawlerException(this.message, {this.statusCode, this.uri});

  @override
  String toString() =>
      'CrawlerException: $message${statusCode != null ? ' ($statusCode)' : ''}';
}
