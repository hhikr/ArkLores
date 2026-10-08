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

  /// The group chip chosen (null: all groups, under their headings).
  String? _group;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider);
    final game = widget.game ?? gameOfId(widget.collectionId ?? '');
    final title = widget.title ??
        [
          if (widget.collectionName != null) widget.collectionName!,
          entryTypeNameIn(widget.type, game),
        ].join(' · ');
    final flat = widget.flat || widget.groups != null;
    // A long list of grouped entries is shown by group: chips on top pick
    // one group in place, and the whole list carries the group headings.
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
    final other = context.t.shelfOther;
    final menu = groupData?.valueOrNull == null
        ? null
        : _groupMenu(widget.type, groupData!.valueOrNull!, other: other);
    if (!flat && groupData!.isLoading) {
      return LibraryScaffold(
        title: title,
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final chosen = menu?.where((g) => g.label == _group).firstOrNull;
    final key = (
      type: widget.type,
      collectionId: widget.collectionId,
      query: _query,
      groups: groupsKey(widget.groups ?? chosen?.raws),
      game: game,
    );
    final entries = ref.watch(entriesOfTypeProvider(key));
    // Headings in the whole list: the entries by group, in the menu's order.
    List<Object> rows(List<LibraryEntry> list) {
      if (menu == null || chosen != null) return list;
      final order = [for (final g in menu) g.label];
      final byLabel = <String, List<LibraryEntry>>{};
      for (final e in list) {
        (byLabel[groupLabel(widget.type, e.group) ?? other] ??= []).add(e);
      }
      return [
        for (final label in order)
          if (byLabel[label] != null) ...[label, ...byLabel[label]!],
      ];
    }
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
          if (menu != null) _groupChips(theme, menu),
          Expanded(
            child: entries.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, __) => LibraryMessage(
                icon: Icons.folder_off_sharp,
                title: context.t.libraryEmpty,
              ),
              data: (list) {
                if (list.isEmpty) {
                  return LibraryMessage(
                    icon: Icons.search_off_sharp,
                    title: context.t.libraryNoResults,
                    action: _query.trim().isEmpty
                        ? null
                        : SearchFurtherButton(
                            query: _query,
                            scope: scope,
                            label: title,
                          ),
                  );
                }
                final items = rows(list);
                return ListView.builder(
                  padding: const EdgeInsets.only(bottom: 24),
                  itemCount: items.length,
                  itemBuilder: (context, i) {
                    final item = items[i];
                    if (item is String) {
                      return GroupHeading(
                        key: ValueKey('group-heading-$item'),
                        title: item,
                      );
                    }
                    final e = item as LibraryEntry;
                    return Column(
                      children: [
                        EntryRow(entry: e, onTap: () => openEntry(context, e)),
                        rowDivider(theme),
                      ],
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// The groups as chips: one picks a group in place, again shows all.
  Widget _groupChips(
    AppThemeTokens theme,
    List<({String label, List<String?> raws, int count})> menu,
  ) {
    final total = menu.fold<int>(0, (n, g) => n + g.count);
    Widget chip(String? label, String text, int count) {
      final on = _group == label;
      return Padding(
        padding: const EdgeInsets.only(right: 6),
        child: ChoiceChip(
          key: ValueKey('group-${label ?? 'all'}'),
          label: Text('$text  $count'),
          selected: on,
          showCheckmark: false,
          labelStyle: theme.bodyFont.copyWith(
            fontSize: 12.5,
            color: on ? theme.onAccent : theme.textPrimary,
            fontWeight: on ? FontWeight.w700 : FontWeight.w500,
          ),
          selectedColor: theme.accentPrimary,
          backgroundColor: theme.cardSurface,
          side: BorderSide(color: on ? theme.accentPrimary : theme.cardBorder),
          onSelected: (_) => setState(() => _group = label),
        ),
      );
    }

    // A handful of chips: all built, scrolled sideways when they overflow.
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 4),
      child: Row(
        children: [
          chip(null, context.t.libraryAllEntries, total),
          for (final g in menu) chip(g.label, g.label, g.count),
        ],
      ),
    );
  }
}
