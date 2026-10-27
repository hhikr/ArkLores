import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/gamedata/game.dart';
import '../../core/library/library_labels.dart';
import '../../core/library/library_provider.dart';
import '../../core/library/library_queries.dart';
import '../../shared/l10n/l10n.dart';
import '../../shared/providers/settings_provider.dart';
import '../../shared/providers/theme_provider.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/ef_widgets.dart';
import '../../shared/widgets/industrial_ui.dart';
import '../../shared/widgets/page_frame.dart';
import 'library_pages.dart';
import 'library_widgets.dart';

// ─── One operator ─────────────────────────────────────────────────

/// An operator's page: everything the knowledge base holds about it in one
/// place — record sets (密录), modules, skins, paradox simulation stages and
/// the profile text.
class OperatorPage extends ConsumerWidget {
  const OperatorPage({super.key, required this.entryId});

  final String entryId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    final entry = ref.watch(entryProvider(entryId));
    final e = entry.valueOrNull;
    if (e == null) {
      return LibraryScaffold(
        title: '',
        body: entry.isLoading
            ? const LoadingView()
            : LibraryMessage(
                icon: Icons.folder_off_sharp,
                title: context.t.libraryEmpty,
              ),
      );
    }
    final records = ref.watch(operatorMemoriesProvider(e.id)).valueOrNull ??
        const <LibraryCollection>[];
    final owned = ref.watch(operatorOwnedProvider(e.id)).valueOrNull ??
        const <LibraryEntry>[];
    final blocks = ref.watch(entryTextsProvider(e)).valueOrNull ??
        const <EntryTextBlock>[];
    final samePerson = ref.watch(samePersonProvider(e.id)).valueOrNull ??
        const <LibraryEntry>[];

    // The collections below it by kind (in kind order: missions, Baker,
    // Dijiang), each kind in game order.
    final kinds = <String, List<LibraryCollection>>{};
    for (final c in records) {
      final kind = _bareKind(c.kind);
      // Missions of any shelf are one group (an operator's mission may be on
      // the main story shelf too).
      (kinds[ownedCollectionKinds.contains(kind) ? kind : 'memory'] ??= [])
          .add(c);
    }
    final kindOrder = ['memory', ...ownedCollectionKinds];
    final sortedKinds = Map.fromEntries(
      kinds.entries.toList()
        ..sort(
          (a, b) =>
              kindOrder.indexOf(a.key).compareTo(kindOrder.indexOf(b.key)),
        ),
    );
    kinds
      ..clear()
      ..addAll(sortedKinds);

    // Owned entries by type, in the order the query returns them.
    final byType = <String, List<LibraryEntry>>{};
    for (final o in owned) {
      (byType[o.type] ??= []).add(o);
    }

    Widget header(String title, String code) =>
        IndustrialSectionHeader(theme: theme, title: title, code: code);

    return LibraryScaffold(
      title: e.name.isEmpty ? e.id : e.name,
      scrollUnder: true,
      hides: true,
      actions: [
        LibrarySearchButton(
          scope: ownerScope(e.id),
          label: e.name.isEmpty ? e.id : e.name,
        ),
      ],
      // One selection over the page: the profile's rows are separate items
      // of a lazy list.
      body: SelectionArea(
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding:
                  pagePadding(context, const EdgeInsets.fromLTRB(16, 0, 16, 32)),
              sliver: SliverMainAxisGroup(
                slivers: [
                  SliverList.list(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(0, 16, 0, 4),
                        child: _headerCard(context, theme, e, records, byType),
                      ),
                      // The profile (archive) leads: it is what the page is about. Each
                      // of its parts folds (open or not as Settings say); it is built
                      // only as far as it is on screen.
                      if (blocks.isNotEmpty) ...[
                        header(context.t.libraryOperatorProfile, 'profile'),
                        const SizedBox(height: 4),
                      ],
                    ],
                  ),
                  for (final b in blocks)
                    EntryPage.textSliver(
                      theme,
                      e,
                      b,
                      ref.watch(nicknameProvider),
                      padding: EdgeInsets.zero,
                    ),
                  SliverList.list(
                    children: [
                      if (samePerson.isNotEmpty) ...[
                        header(
                          bindingName('same_person', outgoing: true),
                          'same_person',
                        ),
                        for (final o in samePerson) ...[
                          LibraryRow(
                            key: ValueKey('operator-same-${o.id}'),
                            title: o.name.isEmpty ? o.id : o.name,
                            subtitle: codeCaption(o),
                            subtitleLines: 1,
                            trailing: Icon(
                              Icons.chevron_right_sharp,
                              color: theme.textMuted,
                            ),
                            onTap: () => openEntry(context, o),
                          ),
                          rowDivider(theme),
                        ],
                      ],
                      // What hangs below the operator, by kind: Arknights' record sets
                      // (密录); Endfield's operator missions (under the name of their
                      // series), Baker topics and Dijiang interactions. A row with one
                      // story opens it.
                      for (final kind in kinds.entries) ...[
                        header(
                          _kindLabel(context, kind.key),
                          'records-${kind.key}',
                        ),
                        for (final (i, c) in kind.value.indexed) ...[
                          if (c.group != null &&
                              (i == 0 || kind.value[i - 1].group != c.group))
                            GroupHeading(
                              key: ValueKey('operator-series-${c.group}'),
                              title: c.group!,
                            ),
                          LibraryRow(
                            key: ValueKey('operator-record-${c.id}'),
                            title: c.name,
                            subtitle: c.intro ??
                                context.t.libraryCountStories(c.stories),
                            subtitleLines: c.intro == null ? 1 : 2,
                            trailing: Icon(
                              Icons.chevron_right_sharp,
                              color: theme.textMuted,
                            ),
                            onTap: () => openCollectionOf(context, c),
                          ),
                          rowDivider(theme),
                        ],
                      ],
                      for (final group in byType.entries) ...[
                        header(entryTypeName(group.key), group.key),
                        for (final o in group.value) ...[
                          LibraryRow(
                            key: ValueKey('operator-owned-${o.id}'),
                            title: o.name.isEmpty ? o.id : o.name,
                            subtitle: _ownedCaption(o),
                            subtitleLines: 1,
                            trailing: Icon(
                              Icons.chevron_right_sharp,
                              color: theme.textMuted,
                            ),
                            onTap: () => openEntry(context, o),
                          ),
                          rowDivider(theme),
                        ],
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// A collection kind without the game's namespace.
  static String _bareKind(String kind) => kind.startsWith(endfieldIdPrefix)
      ? kind.substring(endfieldIdPrefix.length)
      : kind;

  /// The heading of one kind of what hangs below an operator.
  String _kindLabel(BuildContext context, String kind) =>
      gameOfId(entryId) == Game.endfield
          ? endfieldOwnedNames[kind] ?? endfieldOperatorMissions
          : context.t.libraryOperatorRecords;

  /// The line under a module / skin / paradox simulation: a module's type
  /// mark, a skin's series.
  static String? _ownedCaption(LibraryEntry o) {
    if (o.type == 'module') {
      final code = o.code ?? '';
      return code.isNotEmpty && code.length <= 3 ? '$code 型' : null;
    }
    return groupLabel(o.type, o.group);
  }

  Widget _headerCard(
    BuildContext context,
    AppThemeTokens theme,
    LibraryEntry e,
    List<LibraryCollection> records,
    Map<String, List<LibraryEntry>> byType,
  ) {
    final stories = records.fold<int>(0, (n, c) => n + c.stories);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(shelfIcon(operatorShelf), color: theme.textSecondary, size: 18),
            const SizedBox(width: 6),
            Text(
              context.t.shelfMemory,
              style: theme.ui(13, weight: 700, color: theme.textSecondary),
            ),
            if (codeCaption(e) != null) ...[
              const SizedBox(width: 8),
              IndexTag(codeCaption(e)!),
            ],
          ],
        ),
        const SizedBox(height: 6),
        Text(e.name.isEmpty ? e.id : e.name, style: theme.heading(26)),
        const SizedBox(height: 10),
        const TriStrip(),
        const SizedBox(height: 10),
        FactsRow([
          if (stories > 0) context.t.libraryCountStories(stories),
          for (final g in byType.entries)
            '${entryTypeName(g.key)} ${g.value.length}',
        ]),
      ],
    );
  }
}
