import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/wiki/bookmark_service.dart';

/// Notifier that manages the bookmark list and an in-memory URL set for
/// fast `isBookmarked` lookups.
///
/// State is loaded asynchronously from [BookmarkService] on first access.
class BookmarkNotifier extends AsyncNotifier<List<Bookmark>> {
  /// In-memory set of bookmarked URLs for O(1) lookups.
  final Set<String> _bookmarkedUrls = {};

  @override
  Future<List<Bookmark>> build() async {
    final bookmarks = await BookmarkService().getAll();
    _bookmarkedUrls.addAll(bookmarks.map((b) => b.url));
    return bookmarks;
  }

  /// Returns `true` if the given [url] is bookmarked.
  bool isBookmarked(String url) => _bookmarkedUrls.contains(url);

  /// Toggles the bookmark for the given page.
  ///
  /// If already bookmarked, removes it. Otherwise creates a new entry.
  Future<void> toggle({
    required String title,
    required String url,
    required String site,
  }) async {
    final service = BookmarkService();

    if (_bookmarkedUrls.contains(url)) {
      // Remove existing bookmark.
      await service.deleteByUrl(url);
      _bookmarkedUrls.remove(url);
      state = AsyncData(
        state.value!.where((b) => b.url != url).toList(),
      );
    } else {
      // Add new bookmark.
      final bookmark = Bookmark.create(
        title: title,
        url: url,
        site: site,
      );
      await service.insert(bookmark);
      _bookmarkedUrls.add(url);
      state = AsyncData([bookmark, ...state.value!]);
    }
  }

  /// Removes a bookmark by its [id].
  Future<void> remove(String id) async {
    await BookmarkService().delete(id);
    // Find the URL before removing from state.
    final entry = state.value!.firstWhere(
      (b) => b.id == id,
      orElse: () => throw StateError('Bookmark $id not found'),
    );
    _bookmarkedUrls.remove(entry.url);
    state = AsyncData(state.value!.where((b) => b.id != id).toList());
  }
}

/// Global provider for the bookmark state.
final bookmarkProvider =
    AsyncNotifierProvider<BookmarkNotifier, List<Bookmark>>(
  BookmarkNotifier.new,
);
