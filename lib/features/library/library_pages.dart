/// The library's pages (one file each) and how they are opened: a shelf,
/// a collection, an entry (a story opens in the reader), the search.
library;

import 'package:flutter/material.dart';

import '../../core/gamedata/game.dart';
import '../../core/library/library_labels.dart';
import '../../core/library/library_queries.dart';
import '../../shared/l10n/l10n.dart';
import '../../shared/widgets/smooth_page_route.dart';
import 'collection_page.dart';
import 'entry_list_page.dart';
import 'entry_page.dart';
import 'library_search_page.dart';
import 'library_widgets.dart';
import 'operator_page.dart';
import 'shelf_page.dart';

export 'collection_page.dart';
export 'entry_list_page.dart';
export 'entry_page.dart';
export 'library_search_page.dart';
export 'operator_page.dart';
export 'shelf_page.dart';

// ─── Shelves ───────────────────────────────────────────────────────

/// [game]'s name in the interface language.
String gameLabel(BuildContext context, Game game) => switch (game) {
      Game.arknights => context.t.gameArknights,
      Game.endfield => context.t.gameEndfield,
    };

/// A shelf's name: an Endfield shelf by its kind without the id namespace,
/// with Endfield's own names where its shelves differ.
String shelfLabel(BuildContext context, String kind) {
  if (gameOfId(kind) == Game.endfield) {
    final bare = kind.substring(endfieldIdPrefix.length);
    return endfieldShelfNames[bare] ?? _arknightsShelfLabel(context, bare);
  }
  return _arknightsShelfLabel(context, kind);
}

String _arknightsShelfLabel(BuildContext context, String kind) =>
    switch (kind) {
      'main' => context.t.shelfMain,
      'sidestory' => context.t.shelfSideStory,
      'ministory' => context.t.shelfMiniStory,
      'branchline' => context.t.shelfBranchline,
      'activity' => context.t.shelfActivity,
      'memory' => context.t.shelfMemory,
      'roguelike' => context.t.shelfRoguelike,
      'sandbox' => context.t.shelfSandbox,
      // A kind of a later build the interface has no name for.
      final other when other != codexShelf => context.t.shelfOther,
      _ => context.t.shelfCodex,
    };

IconData shelfIcon(String kind) => _shelfIcon(gameOfId(kind) == Game.endfield
    ? kind.substring(endfieldIdPrefix.length)
    : kind,);

IconData _shelfIcon(String kind) => switch (kind) {
      'main' => Icons.auto_stories_rounded,
      'sidestory' => Icons.menu_book_rounded,
      'ministory' => Icons.bookmarks_rounded,
      'branchline' => Icons.alt_route_rounded,
      'activity' => Icons.event_note_rounded,
      'memory' => Icons.badge_rounded,
      'roguelike' => Icons.diamond_rounded,
      'sandbox' => Icons.landscape_rounded,
      // 0.12: Endfield's shelves (kinds without the ef/ namespace).
      'discovery' => Icons.travel_explore_rounded,
      'side' => Icons.alt_route_rounded,
      'other' => Icons.assignment_rounded,
      'world' => Icons.public_rounded,
      'archive' => Icons.folder_special_rounded,
      _ => Icons.collections_bookmark_rounded,
    };

void pushLibraryPage(BuildContext context, WidgetBuilder builder) =>
    Navigator.of(context).push(smoothPageRoute<void>(builder: builder));

/// The operator shelf lists the operators; every other shelf its
/// collections (the codex its entry types).
void openShelf(BuildContext context, String kind) => pushLibraryPage(
      context,
      (_) => kind == operatorShelfOf(gameOfId(kind))
          ? EntryListPage(
              type: 'operator',
              title: shelfLabel(context, kind),
              game: gameOfId(kind),
            )
          : ShelfPage(kind: kind),
    );

void openCollection(BuildContext context, String id) =>
    pushLibraryPage(context, (_) => CollectionPage(collectionId: id));

void openEntry(BuildContext context, LibraryEntry entry) {
  final story = entry.rawId;
  if (entry.isStory && story != null) {
    openStory(context, story);
    return;
  }
  pushLibraryPage(
    context,
    (_) => entry.type == 'operator'
        ? OperatorPage(entryId: entry.id)
        : EntryPage(entryId: entry.id),
  );
}

/// The search, limited to [scope] (named [label]: the page it was opened
/// from) until the reader widens it.
void openSearch(
  BuildContext context, {
  LibraryScope scope = everywhere,
  String? label,
  String query = '',
}) =>
    pushLibraryPage(
      context,
      (_) => LibrarySearchPage(
        scope: scope,
        scopeLabel: label,
        initialQuery: query,
      ),
    );
