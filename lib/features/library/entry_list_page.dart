import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/gamedata/game.dart';
import '../../core/library/library_labels.dart';
import '../../core/library/library_provider.dart';
import '../../core/library/library_queries.dart';
import '../../shared/l10n/l10n.dart';
import '../../shared/providers/theme_provider.dart';
import '../../shared/theme/app_theme.dart';
import 'library_pages.dart';
import 'library_widgets.dart';

// ─── Entry lists and one entry ────────────────────────────────────

/// The entries of one type, in a collection or in the codex, with a filter.
class EntryListPage extends ConsumerStatefulWidget {
  const EntryListPage({
    super.key,
    required this.type,
    this.collectionId,
    this.collectionName,
    this.title,
    this.groups,
    this.flat = false,
    this.game,
  });

  final String type;

  /// The game whose codex this is (without a collection); a collection's
  /// list is in its collection's game.
  final Game? game;
  final String? collectionId;
  final String? collectionName;

  /// Replaces the default title (the type's name).
  final String? title;

  /// Only the entries of these groups (a null element is "no group"): one
  /// entry of the menu a long, grouped list opens with.
  final List<String?>? groups;

  /// The whole list at once, without the group menu.
  final bool flat;

  @override
  ConsumerState<EntryListPage> createState() => _EntryListPageState();
}

/// The groups of a long list as the reader names them (several game codes
/// may share a name); null when a menu would not help: one heading, or a
/// short list. Groups without a name go last, under [other].
List<({String label, List<String?> raws, int count})>? _groupMenu(
  String type,
  List<({String? group, int count})> groups, {
  required String other,
}) {
  final total = groups.fold<int>(0, (n, g) => n + g.count);
  if (total < 30) return null;
  final byLabel = <String, ({List<String?> raws, int count})>{};
  for (final g in groups) {
    final label = groupLabel(type, g.group) ?? other;
    final prev = byLabel[label];
    byLabel[label] = (
      raws: [...?prev?.raws, g.group],
      count: (prev?.count ?? 0) + g.count,
    );
  }
  if (byLabel.length < 2) return null;
  final labels = byLabel.keys.toList()
    ..sort((a, b) => a == other
        ? 1
        : b == other
            ? -1
            : 0,);
  return [
    for (final l in labels)
      (label: l, raws: byLabel[l]!.raws, count: byLabel[l]!.count),
  ];
}

class _EntryListPageState extends ConsumerState<EntryListPage> {
  String _query = '';
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider);
    final game = widget.game ?? gameOfId(widget.collectionId ?? '');
    final key = (
      type: widget.type,
      collectionId: widget.collectionId,
      query: _query,
      groups: groupsKey(widget.groups),
      game: game,
    );
    final title = widget.title ??
        [
          if (widget.collectionName != null) widget.collectionName!,
          entryTypeName(widget.type),
        ].join(' · ');
    final flat =
        widget.flat || widget.groups != null || _query.trim().isNotEmpty;
    // A long list of grouped entries opens as a menu of its groups.
    final groupData = flat
        ? null
        : ref.watch(
            entryGroupsProvider(
              (
                type: widget.type,
                collectionId: widget.collectionId,
                game: game
              ),
            ),
          );
    final menu = groupData?.valueOrNull == null
        ? null
        : _groupMenu(
            widget.type,
            groupData!.valueOrNull!,
            other: context.t.shelfOther,
          );
    if (!flat && groupData!.isLoading) {
      return LibraryScaffold(
        title: title,
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final entries = ref.watch(entriesOfTypeProvider(key));
    // The operator shelf is this list of operators; its search also finds
    // their record stories.
    final scope = widget.type == 'operator' && widget.collectionId == null
        ? shelfScope(operatorShelfOf(game))
        : listScope(collectionId: widget.collectionId, type: widget.type);
    return LibraryScaffold(
      title: title,
      actions: [LibrarySearchButton(scope: scope, label: title)],
      body: Column(
        children: [
          FilterField(
            hint: context.t.libraryFilterHint,
            onChanged: (v) {
              _debounce?.cancel();
              _debounce = Timer(
                const Duration(milliseconds: 250),
                () => setState(() => _query = v),
              );
            },
          ),
          Expanded(
            child: menu != null
                ? _menuList(theme, title, menu)
                : entries.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (_, __) => LibraryMessage(
                      icon: Icons.folder_off_rounded,
                      title: context.t.libraryEmpty,
                    ),
                    data: (list) => list.isEmpty
                        ? LibraryMessage(
                            icon: Icons.search_off_rounded,
                            title: context.t.libraryNoResults,
                            action: _query.trim().isEmpty
                                ? null
                                : SearchFurtherButton(
                                    query: _query,
                                    scope: scope,
                                    label: title,
                                  ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.only(bottom: 24),
                            itemCount: list.length,
                            separatorBuilder: (_, __) => rowDivider(theme),
                            itemBuilder: (context, i) => EntryRow(
                              entry: list[i],
                              onTap: () => openEntry(context, list[i]),
                            ),
                          ),
                  ),
          ),
        ],
      ),
    );
  }

  /// The first level: the groups, then everything.
  Widget _menuList(
    AppThemeTokens theme,
    String title,
    List<({String label, List<String?> raws, int count})> menu,
  ) {
    final total = menu.fold<int>(0, (n, g) => n + g.count);
    void open(String label, List<String?>? raws) => pushLibraryPage(
          context,
          (_) => EntryListPage(
            type: widget.type,
            collectionId: widget.collectionId,
            collectionName: widget.collectionName,
            title: '$title · $label',
            groups: raws,
            flat: true,
          ),
        );
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        for (final g in menu) ...[
          LibraryRow(
            key: ValueKey('group-${g.label}'),
            title: g.label,
            subtitle: context.t.libraryCountEntries(g.count),
            subtitleLines: 1,
            leading: Icon(Icons.folder_outlined, color: theme.accentText),
            trailing: Icon(Icons.chevron_right_rounded, color: theme.textMuted),
            onTap: () => open(g.label, g.raws),
          ),
          rowDivider(theme),
        ],
        LibraryRow(
          key: const ValueKey('group-all'),
          title: context.t.libraryAllEntries,
          subtitle: context.t.libraryCountEntries(total),
          subtitleLines: 1,
          leading: Icon(Icons.list_rounded, color: theme.textSecondary),
          trailing: Icon(Icons.chevron_right_rounded, color: theme.textMuted),
          onTap: () => open(context.t.libraryAllEntries, null),
        ),
      ],
    );
  }
}
