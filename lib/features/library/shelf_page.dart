import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/gamedata/game.dart';
import '../../core/gamedata/story_catalog.dart' show releaseMonthOf;
import '../../core/library/library_labels.dart';
import '../../core/library/library_provider.dart';
import '../../core/library/library_queries.dart';
import '../../shared/l10n/l10n.dart';
import '../../shared/providers/theme_provider.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/ef_widgets.dart';
import '../../shared/widgets/search_marks.dart';
import 'library_pages.dart';
import 'library_widgets.dart';

/// The collections of one shelf; the codex shelf lists its entry types.
class ShelfPage extends ConsumerStatefulWidget {
  const ShelfPage({super.key, required this.kind});

  final String kind;

  @override
  ConsumerState<ShelfPage> createState() => _ShelfPageState();
}

class _ShelfPageState extends ConsumerState<ShelfPage> {
  String _filter = '';

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider);
    final label = shelfLabel(context, widget.kind);
    return LibraryScaffold(
      title: label,
      actions: [
        LibrarySearchButton(scope: shelfScope(widget.kind), label: label),
      ],
      body: isCodexShelf(widget.kind) ? _codex(theme) : _collections(theme),
    );
  }

  Widget _codex(AppThemeTokens theme) {
    final game = gameOfId(widget.kind);
    final types = ref.watch(codexTypesProvider(game));
    return types.when(
      loading: () => const LoadingView(),
      error: (_, __) => LibraryMessage(
        icon: Icons.folder_off_sharp,
        title: context.t.libraryEmpty,
      ),
      data: (list) => list.isEmpty
          ? LibraryMessage(
              icon: Icons.folder_open_sharp,
              title: context.t.libraryEmpty,
            )
          : ListView.separated(
              padding: EdgeInsets.fromLTRB(
                16,
                8,
                16,
                24 + MediaQuery.paddingOf(context).bottom,
              ),
              itemCount: list.length,
              separatorBuilder: (_, __) => rowDivider(theme),
              itemBuilder: (context, i) => LibraryRow(
                key: ValueKey('codex-type-${list[i].type}'),
                title: entryTypeNameIn(list[i].type, game),
                subtitle: context.t.libraryCountEntries(list[i].count),
                subtitleLines: 1,
                leading: SizedBox(
                  width: 28,
                  child: Text(
                    (i + 1).toString().padLeft(2, '0'),
                    style: theme.field(color: theme.textMuted, size: 14),
                  ),
                ),
                trailing: Icon(
                  Icons.chevron_right_sharp,
                  color: theme.textMuted,
                ),
                onTap: () => pushLibraryPage(
                  context,
                  (_) => EntryListPage(type: list[i].type, game: game),
                ),
              ),
            ),
    );
  }

  Widget _collections(AppThemeTokens theme) {
    final all = ref.watch(collectionsOfKindProvider(widget.kind));
    return all.when(
      loading: () => const LoadingView(),
      error: (_, __) => LibraryMessage(
        icon: Icons.folder_off_sharp,
        title: context.t.libraryEmpty,
      ),
      data: (list) {
        final q = _filter.trim().toLowerCase();
        final shown = q.isEmpty
            ? list
            : [
                for (final c in list)
                  if (c.name.toLowerCase().contains(q)) c,
              ];
        // Release-ordered shelves get a year heading. Collections that say
        // where they are (an Endfield mission's region) are listed by that
        // place, the places in the order they first come up; the others are
        // in game order and need no heading.
        final byYear = list.any((c) => c.startTime != null);
        final byGroup = !byYear && list.any((c) => c.group != null);
        final ordered = byGroup ? _byGroup(shown) : shown;
        String? headingOf(LibraryCollection c) => byYear
            ? releaseMonthOf(c.startTime)?.substring(0, 4) ?? '—'
            : byGroup
                ? c.group ?? context.t.shelfOther
                : null;
        final counts = <String, int>{};
        for (final c in ordered) {
          final h = headingOf(c);
          if (h != null) counts[h] = (counts[h] ?? 0) + 1;
        }
        final rows = <Widget>[];
        String? heading;
        for (final (i, c) in ordered.indexed) {
          final h = headingOf(c);
          if (h != null && (i == 0 || h != heading)) {
            heading = h;
            rows.add(
              GroupHeading(
                title: h,
                key: ValueKey('shelf-heading-$h'),
                count: counts[h],
              ),
            );
          }
          rows
            ..add(rowDivider(theme))
            ..add(_collectionRow(theme, c));
        }
        if (rows.isNotEmpty) rows.add(rowDivider(theme));
        return Column(
          children: [
            if (list.length > 12)
              FilterField(
                hint: context.t.libraryFilterHint,
                onChanged: (v) => setState(() => _filter = v),
              ),
            Expanded(
              child: shown.isEmpty
                  ? LibraryMessage(
                      icon: Icons.search_off_sharp,
                      title: context.t.libraryNoResults,
                      action: SearchFurtherButton(
                        query: _filter,
                        scope: shelfScope(widget.kind),
                        label: shelfLabel(context, widget.kind),
                      ),
                    )
                  : SearchMarks(
                      words: searchWords(_filter),
                      child: ListView(
                        padding: EdgeInsets.fromLTRB(
                          16,
                          4,
                          16,
                          24 + MediaQuery.paddingOf(context).bottom,
                        ),
                        children: rows,
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }

  /// [list] with the collections of one group together, the groups in the
  /// order they first come up (game order inside a group); collections
  /// without a group last.
  List<LibraryCollection> _byGroup(List<LibraryCollection> list) {
    final groups = <String?, List<LibraryCollection>>{};
    for (final c in list) {
      (groups[c.group] ??= []).add(c);
    }
    return [
      for (final e in groups.entries)
        if (e.key != null) ...e.value,
      ...?groups[null],
    ];
  }

  Widget _collectionRow(AppThemeTokens theme, LibraryCollection c) {
    final month = releaseMonthOf(c.startTime);
    final parts = [
      if (c.stories > 0) context.t.libraryCountStories(c.stories),
      if (c.others > 0) context.t.libraryCountEntries(c.others),
      if (month != null) monthLabel(month),
    ];
    // A collection that introduces itself (a mission) says what it is about.
    final intro = c.intro;
    return LibraryRow(
      key: ValueKey('collection-${c.id}'),
      title: c.name,
      subtitle: intro ?? parts.join(' / '),
      subtitleLines: intro == null ? 1 : 2,
      trailing: Icon(Icons.chevron_right_sharp, color: theme.textMuted),
      onTap: () => openCollectionOf(context, c),
    );
  }
}
