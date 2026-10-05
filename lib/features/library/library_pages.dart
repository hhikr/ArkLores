import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/gamedata/build/text_harvest.dart' show cleanRichText;
import '../../core/gamedata/story_catalog.dart' show releaseMonthOf;
import '../../core/library/library_labels.dart';
import '../../core/library/library_provider.dart';
import '../../core/library/library_queries.dart';
import '../../core/userdata/library_ref.dart';
import '../../shared/l10n/l10n.dart';
import '../../shared/providers/theme_provider.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/industrial_ui.dart';
import '../../shared/widgets/smooth_page_route.dart';
import '../../shared/widgets/theme_aware_card.dart';
import 'library_widgets.dart';

// ─── Shelves ───────────────────────────────────────────────────────

String shelfLabel(BuildContext context, String kind) => switch (kind) {
      'main' => context.t.shelfMain,
      'activity' => context.t.shelfActivity,
      'memory' => context.t.shelfMemory,
      'roguelike' => context.t.shelfRoguelike,
      'sandbox' => context.t.shelfSandbox,
      _ => context.t.shelfCodex,
    };

IconData shelfIcon(String kind) => switch (kind) {
      'main' => Icons.auto_stories_rounded,
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
    final progress = ref.watch(readingProgressProvider).valueOrNull ?? const {};
    final c = collection.valueOrNull;

    final storyList = stories.valueOrNull ?? const <LibraryEntry>[];
    final typeList = types.valueOrNull ?? const <({String type, int count})>[];
    final read = storyList
        .where((s) =>
            progress[LibraryRef.story(s.rawId ?? '').toString()]?.finished ??
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
                    if (storyList.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: IndustrialSectionHeader(
                          theme: theme,
                          title: context.t.libraryStories,
                          code: 'stories',
                        ),
                      ),
                      for (final s in storyList) ...[
                        StoryRow(
                          story: s,
                          read: progress[
                              LibraryRef.story(s.rawId ?? '').toString()],
                        ),
                        rowDivider(theme),
                      ],
                    ],
                    if (typeList.isNotEmpty) ...[
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
                          title: entryTypeName(t.type),
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
  });

  final String type;
  final String? collectionId;
  final String? collectionName;

  /// Replaces the default title (the type's name).
  final String? title;

  @override
  ConsumerState<EntryListPage> createState() => _EntryListPageState();
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
    );
    final entries = ref.watch(entriesOfTypeProvider(key));
    return LibraryScaffold(
      title: widget.title ??
          [
            if (widget.collectionName != null) widget.collectionName!,
            entryTypeName(widget.type),
          ].join(' · '),
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
            child: entries.when(
              loading: () => const Center(child: CircularProgressIndicator()),
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
          for (final b in blocks) _textBlock(theme, e, b),
          ..._bindingSections(context, theme, bindings.valueOrNull ?? const []),
        ],
      ),
    );
  }

  Widget _header(BuildContext context, AppThemeTokens theme, LibraryEntry e) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (e.collectionName != null)
            Text(
              e.collectionName!,
              style: theme.bodyFont.copyWith(
                color: theme.textSecondary,
                fontSize: 12,
                letterSpacing: 0.5,
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
              if (e.code != null) AccentPill(e.code!, muted: true),
              if (e.group != null) AccentPill(e.group!, muted: true),
            ],
          ),
        ],
      );

  static Widget _textBlock(
    AppThemeTokens theme,
    LibraryEntry e,
    EntryTextBlock b,
  ) {
    final text = cleanRichText(b.content).trim();
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
  ) {
    if (bindings.isEmpty) return const [];
    final groups = <String, List<EntryBinding>>{};
    for (final b in bindings) {
      final key = '${bindingName(b.relation, outgoing: b.outgoing)}'
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
                titlePrefix: o.code,
                title: o.name.isEmpty ? o.id : o.name,
                subtitle: o.group,
                subtitleLines: 1,
                trailing: Icon(Icons.chevron_right_rounded, color: theme.textMuted),
                onTap: () => openEntry(context, o),
              ),
              rowDivider(theme),
            ],
          ],
          if (blocks.isNotEmpty) ...[
            header(context.t.libraryOperatorProfile, 'profile'),
            const SizedBox(height: 4),
            for (final b in blocks)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: EntryPage._textBlock(theme, e, b),
              ),
          ],
        ],
      ),
    );
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
