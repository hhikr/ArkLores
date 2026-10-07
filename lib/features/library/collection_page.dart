import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/gamedata/build/story_naming.dart' show openingStoryKind;
import '../../core/gamedata/game.dart';
import '../../core/gamedata/story_catalog.dart' show releaseMonthOf;
import '../../core/library/library_labels.dart';
import '../../core/library/library_provider.dart';
import '../../core/library/library_queries.dart';
import '../../core/library/placeholders.dart';
import '../../core/userdata/library_ref.dart';
import '../../shared/l10n/l10n.dart';
import '../../shared/providers/settings_provider.dart';
import '../../shared/providers/theme_provider.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/floating_bar.dart';
import '../../shared/widgets/industrial_ui.dart';
import '../../shared/widgets/theme_aware_card.dart';
import 'library_pages.dart';
import 'library_widgets.dart';

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
              .watch(
                entryGroupsProvider(
                  (
                    type: 'roguelike_buff',
                    collectionId: collectionId,
                    game: gameOfId(collectionId),
                  ),
                ),
              )
              .valueOrNull ??
          const <({String? group, int count})>[])
        if (g.group != null) g.group!,
    ];
    final progress = ref.watch(readingProgressProvider).valueOrNull ?? const {};
    final c = collection.valueOrNull;

    final storyList = stories.valueOrNull ?? const <LibraryEntry>[];
    final intro = ref.watch(collectionIntroProvider(collectionId)).valueOrNull;
    final inline =
        ref.watch(collectionInlineProvider(collectionId)).valueOrNull ??
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
        ? [
            for (final s in storyList)
              if (s.group == openingStoryKind) s,
          ]
        : const <LibraryEntry>[];
    final restStories = ownParts
        ? [
            for (final s in storyList)
              if (s.group != openingStoryKind) s,
          ]
        : storyList;
    final sections =
        _storySections(c, restStories, other: context.t.shelfOther);
    final read = storyList
        .where(
          (s) =>
              progress[LibraryRef.story(s.rawId ?? '').toString()]
                  ?.hasCompleted ??
              false,
        )
        .length;

    return LibraryScaffold(
      title: c?.name ?? '',
      scrollUnder: true,
      actions: [
        LibrarySearchButton(
          scope: listScope(collectionId: collectionId),
          label: c?.name,
        ),
      ],
      body: collection.isLoading && c == null
          ? const Center(child: CircularProgressIndicator())
          : c == null
              ? LibraryMessage(
                  icon: Icons.folder_off_rounded,
                  title: context.t.libraryEmpty,
                )
              : ListView(
                  padding: floatingPadding(
                    context,
                    const EdgeInsets.only(bottom: 32),
                  ),
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
                    ..._ownParts(context, theme, inline,
                        notes: true, nickname: nickname,),
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
                    ..._ownParts(context, theme, inline,
                        notes: false, nickname: nickname,),
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
                          title:
                              t.type == 'roguelike_buff' && ruleKinds.isNotEmpty
                                  ? ruleKinds.join('、')
                                  : entryTypeName(t.type),
                          subtitle: context.t.libraryCountEntries(t.count),
                          subtitleLines: 1,
                          trailing: Icon(
                            Icons.chevron_right_rounded,
                            color: theme.textMuted,
                          ),
                          onTap: () => pushLibraryPage(
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
  /// reading order (stories without a group under [other]); null when the
  /// stories are listed flat.
  Map<String, List<LibraryEntry>>? _storySections(
    LibraryCollection? c,
    List<LibraryEntry> stories, {
    required String other,
  }) {
    if (c == null || (c.kind != 'roguelike' && c.kind != 'sandbox')) {
      return null;
    }
    final out = <String, List<LibraryEntry>>{};
    for (final s in stories) {
      (out[s.group ?? other] ??= []).add(s);
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
