import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/gamedata/build/story_naming.dart'
    show endingStoryKind, openingStoryKind;
import '../../core/gamedata/build/text_harvest.dart' show cleanRichText;
import '../../core/gamedata/story_catalog.dart' show releaseMonthOf;
import '../../core/gamedata/story_coverage_models.dart' show StoryLineEntry;
import '../../core/library/library_labels.dart';
import '../../core/library/library_provider.dart';
import '../../core/library/library_queries.dart';
import '../../core/library/placeholders.dart';
import '../../core/userdata/library_ref.dart';
import '../../shared/l10n/l10n.dart';
import '../../shared/providers/settings_provider.dart';
import '../../shared/providers/theme_provider.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/industrial_ui.dart';
import '../../shared/widgets/smooth_page_route.dart';
import '../../shared/widgets/theme_aware_card.dart';
import '../ai/story_labels_provider.dart' show storyFullLinesProvider;
import 'library_widgets.dart';

// ─── Shelves ───────────────────────────────────────────────────────

String shelfLabel(BuildContext context, String kind) => switch (kind) {
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

IconData shelfIcon(String kind) => switch (kind) {
      'main' => Icons.auto_stories_rounded,
      'sidestory' => Icons.menu_book_rounded,
      'ministory' => Icons.bookmarks_rounded,
      'branchline' => Icons.alt_route_rounded,
      'activity' => Icons.event_note_rounded,
      'memory' => Icons.badge_rounded,
      'roguelike' => Icons.diamond_rounded,
      'sandbox' => Icons.landscape_rounded,
      _ => Icons.collections_bookmark_rounded,
    };

void _push(BuildContext context, WidgetBuilder builder) =>
    Navigator.of(context).push(smoothPageRoute<void>(builder: builder));

/// The operator shelf lists the operators; every other shelf its
/// collections (the codex its entry types).
void openShelf(BuildContext context, String kind) => _push(
      context,
      (_) => kind == operatorShelf
          ? EntryListPage(type: 'operator', title: shelfLabel(context, kind))
          : ShelfPage(kind: kind),
    );

void openCollection(BuildContext context, String id) =>
    _push(context, (_) => CollectionPage(collectionId: id));

void openEntry(BuildContext context, LibraryEntry entry) {
  final story = entry.rawId;
  if (entry.isStory && story != null) {
    openStory(context, story);
    return;
  }
  _push(
    context,
    (_) => entry.type == 'operator'
        ? OperatorPage(entryId: entry.id)
        : EntryPage(entryId: entry.id),
  );
}

void openSearch(BuildContext context) =>
    _push(context, (_) => const LibrarySearchPage());

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
    return LibraryScaffold(
      title: shelfLabel(context, widget.kind),
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
                onTap: () => _push(
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

// ─── One collection ───────────────────────────────────────────────

/// A story set, activity, operator record set or roguelike topic: its
/// stories in reading order and the other texts that belong to it.
class CollectionPage extends ConsumerWidget {
  const CollectionPage({super.key, required this.collectionId});

  final String collectionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    final collection = ref.watch(collectionProvider(collectionId));
    final stories = ref.watch(collectionStoriesProvider(collectionId));
    final types = ref.watch(collectionTypesProvider(collectionId));
    final nickname = ref.watch(nicknameProvider);
    // Special rules are named by what the game calls each kind.
    final ruleKinds = [
      for (final g in ref
              .watch(entryGroupsProvider(
                (type: 'roguelike_buff', collectionId: collectionId),
              ),)
              .valueOrNull ??
          const <({String? group, int count})>[])
        if (g.group != null) g.group!,
    ];
    final progress = ref.watch(readingProgressProvider).valueOrNull ?? const {};
    final c = collection.valueOrNull;

    final storyList = stories.valueOrNull ?? const <LibraryEntry>[];
    final intro = ref.watch(collectionIntroProvider(collectionId)).valueOrNull;
    final inline = ref.watch(collectionInlineProvider(collectionId)).valueOrNull ??
        const <LibraryEntry>[];
    // A topic whose endings and squads carry their own stories lists them
    // first; the stories left over and the kinds of texts follow, without
    // headings of their own.
    final ownParts = inline.isNotEmpty;
    final typeList = [
      for (final t in types.valueOrNull ?? const <({String type, int count})>[])
        if (!inlineEntryTypes.contains(t.type)) t,
    ]..sort((a, b) {
        final byRank = typeRank(a.type).compareTo(typeRank(b.type));
        return byRank != 0 ? byRank : b.count.compareTo(a.count);
      });
    // Roguelike and sandbox stories come in tens, under a heading each
    // (ending, squad, character …): one folding section per heading.
    // The story that plays on first entering a topic has a place of its own,
    // before the endings; the stories left over (tutorials, challenge
    // stories of older topics) follow the endings and squads, each kind
    // under its own folding heading.
    final opening = ownParts
        ? [for (final s in storyList) if (s.group == openingStoryKind) s]
        : const <LibraryEntry>[];
    final restStories = ownParts
        ? [for (final s in storyList) if (s.group != openingStoryKind) s]
        : storyList;
    final sections = _storySections(c, restStories);
    final read = storyList
        .where((s) =>
            progress[LibraryRef.story(s.rawId ?? '').toString()]?.hasCompleted ??
            false,)
        .length;

    return LibraryScaffold(
      title: c?.name ?? '',
      body: collection.isLoading && c == null
          ? const Center(child: CircularProgressIndicator())
          : c == null
              ? LibraryMessage(
                  icon: Icons.folder_off_rounded,
                  title: context.t.libraryEmpty,
                )
              : ListView(
                  padding: const EdgeInsets.only(bottom: 32),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                      child: _headerCard(context, theme, c, read),
                    ),
                    if (intro != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                        child: Text(
                          intro,
                          key: const ValueKey('collection-intro'),
                          style: theme.bodyFont.copyWith(
                            color: theme.textSecondary,
                            fontSize: 14,
                            height: 1.7,
                          ),
                        ),
                      ),
                    ..._ownParts(context, theme, inline, notes: true, nickname: nickname),
                    if (opening.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: IndustrialSectionHeader(
                          theme: theme,
                          title: openingStoryKind,
                          code: 'opening',
                        ),
                      ),
                      for (final s in opening) ...[
                        StoryRow(
                          story: s,
                          showGroup: false,
                          read: progress[
                              LibraryRef.story(s.rawId ?? '').toString()],
                        ),
                        rowDivider(theme),
                      ],
                    ],
                    ..._ownParts(context, theme, inline, notes: false, nickname: nickname),
                    if (restStories.isNotEmpty) ...[
                      if (!ownParts)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: IndustrialSectionHeader(
                            theme: theme,
                            title: context.t.libraryStories,
                            code: 'stories',
                          ),
                        ),
                      if (sections == null)
                        for (final s in restStories) ...[
                          StoryRow(
                            story: s,
                            read: progress[
                                LibraryRef.story(s.rawId ?? '').toString()],
                          ),
                          rowDivider(theme),
                        ]
                      else
                        for (final g in sections.entries) ...[
                          Theme(
                            data: Theme.of(context)
                                .copyWith(dividerColor: Colors.transparent),
                            child: ExpansionTile(
                              key: ValueKey('story-group-${g.key}'),
                              shape: const Border(),
                              collapsedShape: const Border(),
                              tilePadding:
                                  const EdgeInsets.symmetric(horizontal: 16),
                              iconColor: theme.accentText,
                              collapsedIconColor: theme.textMuted,
                              title: Text(
                                g.key,
                                style: theme.titleFont.copyWith(fontSize: 15),
                              ),
                              subtitle: Text(
                                context.t.libraryCountStories(g.value.length),
                                style: theme.bodyFont.copyWith(
                                  color: theme.textSecondary,
                                  fontSize: 12,
                                ),
                              ),
                              children: [
                                for (final s in g.value) ...[
                                  StoryRow(
                                    story: s,
                                    showGroup: false,
                                    read: progress[LibraryRef.story(
                                      s.rawId ?? '',
                                    ).toString()],
                                  ),
                                  rowDivider(theme),
                                ],
                              ],
                            ),
                          ),
                          rowDivider(theme),
                        ],
                    ],
                    if (typeList.isNotEmpty) ...[
                      // Zones to medals: one heading for all of them.
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: IndustrialSectionHeader(
                          theme: theme,
                          title: context.t.libraryOtherSections,
                          code: 'related',
                        ),
                      ),
                      for (final t in typeList) ...[
                        LibraryRow(
                          key: ValueKey('collection-type-${t.type}'),
                          title: t.type == 'roguelike_buff' && ruleKinds.isNotEmpty
                              ? ruleKinds.join('、')
                              : entryTypeName(t.type),
                          subtitle: context.t.libraryCountEntries(t.count),
                          subtitleLines: 1,
                          trailing: Icon(
                            Icons.chevron_right_rounded,
                            color: theme.textMuted,
                          ),
                          onTap: () => _push(
                            context,
                            (_) => EntryListPage(
                              type: t.type,
                              collectionId: collectionId,
                              collectionName: c.name,
                            ),
                          ),
                        ),
                        rowDivider(theme),
                      ],
                    ],
                    if (storyList.isEmpty &&
                        typeList.isEmpty &&
                        !ownParts &&
                        !stories.isLoading)
                      SizedBox(
                        height: 240,
                        child: LibraryMessage(
                          icon: Icons.folder_open_rounded,
                          title: context.t.libraryEmpty,
                        ),
                      ),
                  ],
                ),
    );
  }

  /// The collection's own parts (endings, month squads): a heading per kind
  /// and a row per entry with its sentence; each opens its own page with the
  /// stories it holds.
  List<Widget> _ownParts(
    BuildContext context,
    AppThemeTokens theme,
    List<LibraryEntry> inline, {
    required bool notes,
    required String nickname,
  }) {
    final byType = <String, List<LibraryEntry>>{};
    for (final e in inline) {
      // The notes come before the opening story, the rest after it.
      if ((e.type == 'roguelike_tip') != notes) continue;
      (byType[e.type] ??= []).add(e);
    }
    final order = byType.keys.toList()
      ..sort((a, b) => typeRank(a).compareTo(typeRank(b)));
    if (notes) {
      // The notes are one folding row, not a section of their own.
      final list = byType['roguelike_tip'];
      if (list == null) return const [];
      return [
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            key: const ValueKey('notes-group'),
            shape: const Border(),
            collapsedShape: const Border(),
            tilePadding: const EdgeInsets.symmetric(horizontal: 16),
            iconColor: theme.accentText,
            collapsedIconColor: theme.textMuted,
            title: Text(
              entryTypeName('roguelike_tip'),
              style: theme.titleFont.copyWith(fontSize: 15),
            ),
            subtitle: Text(
              context.t.libraryCountEntries(list.length),
              style: theme.bodyFont.copyWith(
                color: theme.textSecondary,
                fontSize: 12,
              ),
            ),
            children: [
              for (final e in list) ...[
                LibraryRow(
                  key: ValueKey('part-${e.id}'),
                  title: e.name,
                  subtitle: withPlaceholders(e.synopsis ?? '', nickname),
                  subtitleLines: 2,
                  trailing: Icon(
                    Icons.chevron_right_rounded,
                    color: theme.textMuted,
                  ),
                  onTap: () => openEntry(context, e),
                ),
                rowDivider(theme),
              ],
            ],
          ),
        ),
        rowDivider(theme),
      ];
    }
    return [
      for (final type in order) ...[
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: IndustrialSectionHeader(
            theme: theme,
            title: entryTypeName(type),
            code: type,
          ),
        ),
        for (final e in byType[type]!) ...[
          LibraryRow(
            key: ValueKey('part-${e.id}'),
            title: e.name,
            subtitle: [
              if (e.group != null) e.group!,
              if (e.synopsis != null) withPlaceholders(e.synopsis!, nickname),
            ].join('\n'),
            subtitleLines: 3,
            trailing: Icon(Icons.chevron_right_rounded, color: theme.textMuted),
            onTap: () => openEntry(context, e),
          ),
          rowDivider(theme),
        ],
      ],
    ];
  }

  /// The stories of a roguelike or sandbox collection by their group, in
  /// reading order; null when the stories are listed flat.
  Map<String, List<LibraryEntry>>? _storySections(
    LibraryCollection? c,
    List<LibraryEntry> stories,
  ) {
    if (c == null || (c.kind != 'roguelike' && c.kind != 'sandbox')) {
      return null;
    }
    final out = <String, List<LibraryEntry>>{};
    for (final s in stories) {
      (out[s.group ?? '其他'] ??= []).add(s);
    }
    return out.length >= 2 ? out : null;
  }

  Widget _headerCard(
    BuildContext context,
    AppThemeTokens theme,
    LibraryCollection c,
    int read,
  ) {
    final month = releaseMonthOf(c.startTime);
    return ThemeAwareCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(shelfIcon(c.kind), color: theme.accentText, size: 28),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  c.name,
                  style: theme.titleFont.copyWith(fontSize: 18, height: 1.25),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    AccentPill(
                      c.kind == operatorShelf
                          ? context.t.libraryOperatorRecords
                          : shelfLabel(context, c.kind),
                    ),
                    if (month != null)
                      AccentPill(context.t.libraryRelease(month), muted: true),
                    if (c.stories > 0)
                      AccentPill(
                        context.t.libraryCountStories(c.stories),
                        muted: true,
                      ),
                    if (read > 0)
                      AccentPill(
                        '${context.t.libraryFinished} $read/${c.stories}',
                        muted: true,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

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
  });

  final String type;
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
/// short list.
List<({String label, List<String?> raws, int count})>? _groupMenu(
  String type,
  List<({String? group, int count})> groups,
) {
  final total = groups.fold<int>(0, (n, g) => n + g.count);
  if (total < 30) return null;
  final byLabel = <String, ({List<String?> raws, int count})>{};
  for (final g in groups) {
    final label = groupLabel(type, g.group) ?? '其他';
    final prev = byLabel[label];
    byLabel[label] = (
      raws: [...?prev?.raws, g.group],
      count: (prev?.count ?? 0) + g.count,
    );
  }
  if (byLabel.length < 2) return null;
  final labels = byLabel.keys.toList()
    ..sort((a, b) => a == '其他' ? 1 : b == '其他' ? -1 : 0);
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
    final key = (
      type: widget.type,
      collectionId: widget.collectionId,
      query: _query,
      groups: groupsKey(widget.groups),
    );
    final title = widget.title ??
        [
          if (widget.collectionName != null) widget.collectionName!,
          entryTypeName(widget.type),
        ].join(' · ');
    final flat = widget.flat || widget.groups != null || _query.trim().isNotEmpty;
    // A long list of grouped entries opens as a menu of its groups.
    final groupData = flat
        ? null
        : ref.watch(
            entryGroupsProvider(
              (type: widget.type, collectionId: widget.collectionId),
            ),
          );
    final menu = groupData?.valueOrNull == null
        ? null
        : _groupMenu(widget.type, groupData!.valueOrNull!);
    if (!flat && groupData!.isLoading) {
      return LibraryScaffold(
        title: title,
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final entries = ref.watch(entriesOfTypeProvider(key));
    return LibraryScaffold(
      title: title,
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
    void open(String label, List<String?>? raws) => _push(
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

/// One non-story entry: its text and what it is bound to.
class EntryPage extends ConsumerWidget {
  const EntryPage({super.key, required this.entryId});

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
            ? const Center(child: CircularProgressIndicator())
            : LibraryMessage(
                icon: Icons.folder_off_rounded,
                title: context.t.libraryEmpty,
              ),
      );
    }
    final texts = ref.watch(entryTextsProvider(e));
    final bindings = ref.watch(entryBindingsProvider(e.id));
    final blocks = texts.valueOrNull ?? const <EntryTextBlock>[];
    final parts =
        ref.watch(entryPartsProvider(e.id)).valueOrNull ?? const <LibraryEntry>[];
    final progress = ref.watch(readingProgressProvider).valueOrNull ?? const {};
    final attached = ref.watch(attachedStoriesProvider(e.id)).valueOrNull ??
        const <LibraryEntry>[];
    final all = bindings.valueOrNull ?? const <EntryBinding>[];
    // A month squad's protagonist comes before its stories; the story that
    // has the entry's own name (an ending's) comes right after its sentence,
    // the others are what it unlocks.
    final protagonists = [
      for (final b in all)
        if (e.type == 'roguelike_squad' &&
            b.relation == 'features' &&
            b.outgoing)
          b,
    ];
    // An act of a sandbox's plot holds all its stories in order; an ending
    // or a squad has its own story and what it unlocks.
    final own = e.type == 'sandbox_act'
        ? parts
        : [
            for (final s in parts)
              if (s.name == e.name || s.group == endingStoryKind) s,
          ];
    final unlocked = e.type == 'sandbox_act'
        ? const <LibraryEntry>[]
        : [for (final s in parts) if (s.name != e.name) s];
    Widget storyRow(LibraryEntry s) => Column(
          key: ValueKey('part-story-${s.id}'),
          children: [
            StoryRow(
              story: s,
              showGroup: false,
              read: progress[LibraryRef.story(s.rawId ?? '').toString()],
            ),
            rowDivider(theme),
          ],
        );

    return LibraryScaffold(
      title: e.name.isEmpty ? e.id : e.name,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          _header(context, theme, e),
          const SizedBox(height: 16),
          if (blocks.isEmpty && !texts.isLoading)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                context.t.libraryNoText,
                style: theme.bodyFont.copyWith(color: theme.textSecondary),
              ),
            ),
          for (final b in blocks) _textBlock(theme, e, b, ref.watch(nicknameProvider)),
          for (final s in own) storyRow(s),
          // Dialogue played in the battle of a stage, read here (a stage with
          // a story of its own has it at the end of that story).
          if (attached.isNotEmpty) ...[
            IndustrialSectionHeader(
              theme: theme,
              title: context.t.storyReaderBattleDialogue,
              code: 'battle',
            ),
            for (final s in attached)
              _AttachedDialogue(key: ValueKey('attached-${s.id}'), story: s),
            const SizedBox(height: 8),
          ],
          if (protagonists.isNotEmpty) ...[
            IndustrialSectionHeader(
              theme: theme,
              title: bindingName(
                'features',
                outgoing: true,
                ownerType: e.type,
              ),
              code: 'protagonist',
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final b in protagonists)
                  ActionChip(
                    key: ValueKey('binding-${b.entry.id}'),
                    label: Text(entryHeadline(b.entry)),
                    labelStyle: theme.bodyFont.copyWith(fontSize: 12.5),
                    backgroundColor: theme.cardSurface,
                    side: BorderSide(color: theme.cardBorder),
                    onPressed: () => openEntry(context, b.entry),
                  ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          // What the entry unlocks (an ending's pages, a month squad's three
          // stories), in reading order.
          if (unlocked.isNotEmpty) ...[
            IndustrialSectionHeader(
              theme: theme,
              title: context.t.libraryParts,
              code: 'parts',
            ),
            for (final s in unlocked) storyRow(s),
            const SizedBox(height: 8),
          ],
          ..._bindingSections(
            context,
            theme,
            [
              for (final b in all)
                if (b.relation != 'part_of' && !protagonists.contains(b)) b,
            ],
            e.type,
          ),
        ],
      ),
    );
  }

  Widget _header(BuildContext context, AppThemeTokens theme, LibraryEntry e) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The collection the entry belongs to opens its page.
          if (e.collectionName != null)
            InkWell(
              key: const ValueKey('entry-collection'),
              onTap: e.collectionId == null
                  ? null
                  : () => openCollection(context, e.collectionId!),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: e.collectionName!),
                      if (e.collectionId != null)
                        const WidgetSpan(
                          alignment: PlaceholderAlignment.middle,
                          child: Icon(Icons.chevron_right_rounded, size: 16),
                        ),
                    ],
                  ),
                  style: theme.bodyFont.copyWith(
                    color: theme.accentText,
                    fontSize: 12,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),
          const SizedBox(height: 2),
          Text(
            e.name.isEmpty ? e.id : e.name,
            style: theme.titleFont.copyWith(fontSize: 22, height: 1.25),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              AccentPill(entryTypeName(e.type)),
              if (codeCaption(e) != null)
                AccentPill(codeCaption(e)!, muted: true),
              if (groupLabel(e.type, e.group) != null)
                AccentPill(groupLabel(e.type, e.group)!, muted: true),
            ],
          ),
        ],
      );

  static Widget _textBlock(
    AppThemeTokens theme,
    LibraryEntry e,
    EntryTextBlock b,
    String nickname,
  ) {
    final text = cleanRichText(withPlaceholders(b.content, nickname)).trim();
    if (text.isEmpty) return const SizedBox.shrink();
    final showTitle = b.title.trim().isNotEmpty &&
        b.title.trim() != e.name &&
        !b.title.trim().endsWith(e.name);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: ThemeAwareCard(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showTitle) ...[
              Text(
                b.title.trim(),
                style: theme.bodyFont.copyWith(
                  color: theme.textSecondary,
                  fontSize: 12,
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(height: 6),
            ],
            if (eventEntryTypes.contains(e.type))
              EventText(text)
            else if (markdownEntryTypes.contains(e.type))
              MarkdownText(text)
            else
              SelectableText(
                text,
                style: theme.bodyFont.copyWith(
                  color: theme.textPrimary,
                  fontSize: 15,
                  height: 1.7,
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Bindings grouped by what they say and what they point at; each group
  /// is a heading and a wrap of chips that open the bound entry.
  List<Widget> _bindingSections(
    BuildContext context,
    AppThemeTokens theme,
    List<EntryBinding> bindings,
    String ownerType,
  ) {
    if (bindings.isEmpty) return const [];
    final groups = <String, List<EntryBinding>>{};
    for (final b in bindings) {
      final key = '${bindingName(b.relation, outgoing: b.outgoing, ownerType: ownerType)}'
          '\u0000${entryTypeName(b.entry.type)}';
      (groups[key] ??= []).add(b);
    }
    return [
      Padding(
        padding: const EdgeInsets.only(top: 6),
        child: IndustrialSectionHeader(
          theme: theme,
          title: context.t.libraryRelated,
          code: 'bindings',
        ),
      ),
      for (final g in groups.entries) ...[
        Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 8),
          child: Text(
            '${g.key.split('\u0000').first} · ${g.key.split('\u0000').last}'
            '  ${g.value.length}',
            style: theme.bodyFont.copyWith(
              color: theme.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final b in g.value.take(40))
              ActionChip(
                key: ValueKey('binding-${b.entry.id}'),
                label: Text(entryHeadline(b.entry)),
                labelStyle: theme.bodyFont.copyWith(fontSize: 12.5),
                backgroundColor: theme.cardSurface,
                side: BorderSide(color: theme.cardBorder),
                onPressed: () => openEntry(context, b.entry),
              ),
            if (g.value.length > 40)
              Text(
                '+${g.value.length - 40}',
                style: theme.bodyFont.copyWith(color: theme.textMuted),
              ),
          ],
        ),
      ],
    ];
  }
}

/// The lines of one attached story (in-battle dialogue), shown in the page of
/// its stage.
class _AttachedDialogue extends ConsumerWidget {
  const _AttachedDialogue({super.key, required this.story});

  final LibraryEntry story;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    final nickname = ref.watch(nicknameProvider);
    final lines = ref.watch(storyFullLinesProvider(story.rawId ?? '')).valueOrNull ??
        const <StoryLineEntry>[];
    final shown = [
      for (final l in lines)
        if (l.kind != 'title' && l.content.trim().isNotEmpty) l,
    ];
    if (shown.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: ThemeAwareCard(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (i, l) in shown.indexed) ...[
              if (i > 0) const SizedBox(height: 10),
              if ((l.speaker ?? '').trim().isNotEmpty)
                Text(
                  l.speaker!.trim(),
                  style: theme.bodyFont.copyWith(
                    color: theme.accentText,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              Text(
                withPlaceholders(l.content, nickname),
                style: theme.bodyFont.copyWith(
                  color: theme.textPrimary,
                  fontSize: 15,
                  height: 1.65,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
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
            ? const Center(child: CircularProgressIndicator())
            : LibraryMessage(
                icon: Icons.folder_off_rounded,
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

    // Owned entries by type, in the order the query returns them.
    final byType = <String, List<LibraryEntry>>{};
    for (final o in owned) {
      (byType[o.type] ??= []).add(o);
    }

    Widget header(String title, String code) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: IndustrialSectionHeader(theme: theme, title: title, code: code),
        );

    return LibraryScaffold(
      title: e.name.isEmpty ? e.id : e.name,
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: _headerCard(context, theme, e, records, byType),
          ),
          // The profile (archive) leads: it is what the page is about.
          if (blocks.isNotEmpty) ...[
            header(context.t.libraryOperatorProfile, 'profile'),
            const SizedBox(height: 4),
            for (final b in blocks)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: EntryPage._textBlock(theme, e, b, ref.watch(nicknameProvider)),
              ),
          ],
          if (samePerson.isNotEmpty) ...[
            header(bindingName('same_person', outgoing: true), 'same_person'),
            for (final o in samePerson) ...[
              LibraryRow(
                key: ValueKey('operator-same-${o.id}'),
                title: o.name.isEmpty ? o.id : o.name,
                subtitle: codeCaption(o),
                subtitleLines: 1,
                trailing: Icon(Icons.chevron_right_rounded, color: theme.textMuted),
                onTap: () => openEntry(context, o),
              ),
              rowDivider(theme),
            ],
          ],
          if (records.isNotEmpty) ...[
            header(context.t.libraryOperatorRecords, 'records'),
            for (final c in records) ...[
              LibraryRow(
                key: ValueKey('operator-record-${c.id}'),
                title: c.name,
                subtitle: context.t.libraryCountStories(c.stories),
                subtitleLines: 1,
                trailing: Icon(Icons.chevron_right_rounded, color: theme.textMuted),
                onTap: () => openCollection(context, c.id),
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
                trailing: Icon(Icons.chevron_right_rounded, color: theme.textMuted),
                onTap: () => openEntry(context, o),
              ),
              rowDivider(theme),
            ],
          ],
        ],
      ),
    );
  }

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
    return ThemeAwareCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(shelfIcon(operatorShelf), color: theme.accentText, size: 28),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  e.name.isEmpty ? e.id : e.name,
                  style: theme.titleFont.copyWith(fontSize: 18, height: 1.25),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    AccentPill(context.t.shelfMemory),
                    if (codeCaption(e) != null)
                      AccentPill(codeCaption(e)!, muted: true),
                    if (stories > 0)
                      AccentPill(
                        context.t.libraryCountStories(stories),
                        muted: true,
                      ),
                    for (final g in byType.entries)
                      AccentPill(
                        '${entryTypeName(g.key)} ${g.value.length}',
                        muted: true,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Search ───────────────────────────────────────────────────────

/// Search over story-set names, entry names and codes.
class LibrarySearchPage extends ConsumerStatefulWidget {
  const LibrarySearchPage({super.key});

  @override
  ConsumerState<LibrarySearchPage> createState() => _LibrarySearchPageState();
}

class _LibrarySearchPageState extends ConsumerState<LibrarySearchPage> {
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
    final result = _query.trim().isEmpty
        ? null
        : ref.watch(librarySearchProvider(_query.trim()));
    final progress = ref.watch(readingProgressProvider).valueOrNull ?? const {};
    return LibraryScaffold(
      title: context.t.librarySearchTitle,
      body: Column(
        children: [
          FilterField(
            autofocus: true,
            hint: context.t.librarySearchHint,
            onChanged: (v) {
              _debounce?.cancel();
              _debounce = Timer(
                const Duration(milliseconds: 300),
                () => setState(() => _query = v),
              );
            },
          ),
          Expanded(
            child: result == null
                ? const SizedBox.shrink()
                : result.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (_, __) => LibraryMessage(
                      icon: Icons.search_off_rounded,
                      title: context.t.libraryNoResults,
                    ),
                    data: (r) {
                      if (r.collections.isEmpty && r.entries.isEmpty) {
                        return LibraryMessage(
                          icon: Icons.search_off_rounded,
                          title: context.t.libraryNoResults,
                        );
                      }
                      return ListView(
                        padding: const EdgeInsets.only(bottom: 24),
                        children: [
                          if (r.collections.isNotEmpty) ...[
                            _heading(
                              theme,
                              context.t.librarySearchCollections,
                            ),
                            for (final c in r.collections) ...[
                              LibraryRow(
                                key: ValueKey('hit-collection-${c.id}'),
                                title: c.name,
                                subtitle: shelfLabel(context, c.kind),
                                subtitleLines: 1,
                                trailing: Icon(
                                  Icons.chevron_right_rounded,
                                  color: theme.textMuted,
                                ),
                                onTap: () => openCollection(context, c.id),
                              ),
                              rowDivider(theme),
                            ],
                          ],
                          if (r.entries.isNotEmpty) ...[
                            _heading(theme, context.t.librarySearchEntries),
                            for (final e in r.entries) ...[
                              e.isStory
                                  ? StoryRow(
                                      story: e,
                                      read: progress[LibraryRef.story(
                                        e.rawId ?? '',
                                      ).toString()],
                                    )
                                  : EntryRow(
                                      entry: e,
                                      onTap: () => openEntry(context, e),
                                    ),
                              rowDivider(theme),
                            ],
                          ],
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _heading(AppThemeTokens theme, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
        child: Text(
          text,
          style: theme.bodyFont.copyWith(
            color: theme.textMuted,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
          ),
        ),
      );
}
