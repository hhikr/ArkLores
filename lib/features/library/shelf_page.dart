import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/gamedata/story_catalog.dart' show releaseMonthOf;
import '../../core/library/library_labels.dart';
import '../../core/library/library_provider.dart';
import '../../core/library/library_queries.dart';
import '../../shared/l10n/l10n.dart';
import '../../shared/providers/theme_provider.dart';
import '../../shared/theme/app_theme.dart';
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
      body: widget.kind == codexShelf
          ? _codex(theme)
          : _collections(theme),
    );
  }

  Widget _codex(AppThemeTokens theme) {
    final types = ref.watch(codexTypesProvider);
    return types.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => LibraryMessage(
        icon: Icons.folder_off_rounded,
        title: context.t.libraryEmpty,
      ),
      data: (list) => list.isEmpty
          ? LibraryMessage(
              icon: Icons.folder_open_rounded,
              title: context.t.libraryEmpty,
            )
          : ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: list.length,
              separatorBuilder: (_, __) => rowDivider(theme),
              itemBuilder: (context, i) => LibraryRow(
                key: ValueKey('codex-type-${list[i].type}'),
                title: entryTypeName(list[i].type),
                subtitle: context.t.libraryCountEntries(list[i].count),
                subtitleLines: 1,
                leading: Icon(Icons.folder_outlined, color: theme.accentText),
                trailing: Icon(
                  Icons.chevron_right_rounded,
                  color: theme.textMuted,
                ),
                onTap: () => pushLibraryPage(
                  context,
                  (_) => EntryListPage(type: list[i].type),
                ),
              ),
            ),
    );
  }

  Widget _collections(AppThemeTokens theme) {
    final all = ref.watch(collectionsOfKindProvider(widget.kind));
    return all.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => LibraryMessage(
        icon: Icons.folder_off_rounded,
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
        // Release-ordered shelves get a year heading; the others are in game
        // order and need none.
        final byYear = list.any((c) => c.startTime != null);
        final rows = <Widget>[];
        String? year;
        for (final c in shown) {
          if (byYear) {
            final y = releaseMonthOf(c.startTime)?.substring(0, 4);
            if (y != year) {
              year = y;
              rows.add(
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                  child: Text(
                    y ?? '—',
                    style: theme.bodyFont.copyWith(
                      color: theme.textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                    ),
                  ),
                ),
              );
            }
          }
          rows
            ..add(_collectionRow(theme, c))
            ..add(rowDivider(theme));
        }
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
                      icon: Icons.search_off_rounded,
                      title: context.t.libraryNoResults,
                      action: SearchFurtherButton(
                        query: _filter,
                        scope: shelfScope(widget.kind),
                        label: shelfLabel(context, widget.kind),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.only(bottom: 24),
                      children: rows,
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _collectionRow(AppThemeTokens theme, LibraryCollection c) {
    final month = releaseMonthOf(c.startTime);
    final parts = [
      if (c.stories > 0) context.t.libraryCountStories(c.stories),
      if (c.others > 0) context.t.libraryCountEntries(c.others),
      if (month != null) month,
    ];
    return LibraryRow(
      key: ValueKey('collection-${c.id}'),
      title: c.name,
      subtitle: parts.join(' · '),
      subtitleLines: 1,
      trailing: Icon(Icons.chevron_right_rounded, color: theme.textMuted),
      onTap: () => openCollection(context, c.id),
    );
  }
}
