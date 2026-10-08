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
export 'reading_text.dart';
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
      'main' => Icons.auto_stories_sharp,
      'sidestory' => Icons.menu_book_sharp,
      'ministory' => Icons.bookmarks_sharp,
      'branchline' => Icons.alt_route_sharp,
      'activity' => Icons.event_note_sharp,
      'memory' => Icons.badge_sharp,
      'roguelike' => Icons.diamond_sharp,
      'sandbox' => Icons.landscape_sharp,
      // 0.12: Endfield's shelves (kinds without the ef/ namespace).
      'discovery' => Icons.travel_explore_sharp,
      'side' => Icons.alt_route_sharp,
      'other' => Icons.assignment_sharp,
      'world' => Icons.public_sharp,
      'unused' => Icons.inventory_2_sharp,
      'archive' => Icons.folder_special_sharp,
      _ => Icons.collections_bookmark_sharp,
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

/// Opens a collection from a list row, without a page that would hold a
/// single row: a collection with one story and nothing else opens the
/// story (an Endfield mission: its description is at the top of the
/// reader), one with one entry opens the entry, one with one kind of entry
/// opens that list; the others open their page.
void openCollectionOf(BuildContext context, LibraryCollection c) {
  if (c.stories == 1 && c.others == 0 && c.firstStory != null) {
    openStory(context, c.firstStory!);
  } else if (c.stories == 0 && c.others == 1 && c.otherEntry != null) {
    pushLibraryPage(
      context,
      (_) => c.otherType == 'operator'
          ? OperatorPage(entryId: c.otherEntry!)
          : EntryPage(entryId: c.otherEntry!),
    );
  } else if (c.stories == 0 && c.otherTypes == 1 && c.otherType != null) {
    pushLibraryPage(
      context,
      (_) => EntryListPage(
        type: c.otherType!,
        collectionId: c.id,
        collectionName: c.name,
        title: c.name,
      ),
    );
  } else {
    openCollection(context, c.id);
  }
}

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
