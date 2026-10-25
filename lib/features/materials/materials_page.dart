import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/gamedata/game.dart';
import '../../core/library/library_provider.dart';
import '../../core/library/library_queries.dart';
import '../../core/userdata/library_ref.dart';
import '../../core/userdata/user_data_provider.dart';
import '../../core/userdata/user_data_store.dart';
import '../../shared/l10n/l10n.dart';
import '../../shared/providers/theme_provider.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/theme/motion.dart';
import '../../shared/widgets/ef_widgets.dart';
import '../../shared/widgets/industrial_ui.dart';
import '../../shared/widgets/page_frame.dart';
import '../../shared/widgets/smooth_page_route.dart';
import '../../shared/widgets/theme_aware_card.dart';
import '../ai/reading_history_page.dart';
import '../library/library_pages.dart';
import '../library/library_widgets.dart';
import '../library/my_materials.dart';

/// The library tab: one page per game (its shelves, what was read in it)
/// and the user's own texts, chosen in the top bar. The pages are not
/// swiped between (a sideways drag on a shelf is not a request to change
/// game); the chosen one slides in a short way.
class MaterialsPage extends ConsumerStatefulWidget {
  const MaterialsPage({super.key});

  @override
  ConsumerState<MaterialsPage> createState() => _MaterialsPageState();
}

class _MaterialsPageState extends ConsumerState<MaterialsPage> {
  /// Index into [Game.values]; one past them is the user's own texts.
  int _tab = 0;

  bool get _mine => _tab == Game.values.length;

  @override
  Widget build(BuildContext context) {
    final labels = [
      for (final game in Game.values) gameLabel(context, game),
      context.t.libraryTabMine,
    ];
    // The lists scroll under the top bar.
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          SwitchedPages(
            index: _tab,
            children: [
              for (final game in Game.values) GameLibraryView(game: game),
              TickerMode(enabled: _mine, child: const MyMaterialsView()),
            ],
          ),
          MainTopBar(
            // Every tab stays in sight; a long label is shortened rather
            // than pushed off the edge.
            leading: Row(
              key: const ValueKey('library-tabs'),
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final (i, label) in labels.indexed)
                  Flexible(
                    child: TopTab(
                      key: ValueKey('library-tab-$i'),
                      label: label,
                      selected: _tab == i,
                      onTap: () => setState(() => _tab = i),
                    ),
                  ),
              ],
            ),
            trailing: !_mine
                ? SquareIconButton(
                    key: const ValueKey('library-search'),
                    tooltip: context.t.librarySearchHint,
                    icon: Icons.search_sharp,
                    onPressed: () => openSearch(context),
                  )
                : SquareIconButton(
                    key: const ValueKey('library-new-material'),
                    tooltip: context.t.materialsNew,
                    icon: Icons.add_sharp,
                    filled: true,
                    onPressed: () => newMaterial(context),
                  ),
          ),
        ],
      ),
    );
  }
}

/// Pages of which one shows at a time, each keeping its state (scroll
/// position) while hidden; changing [index] brings the new page in with a
/// short slide from the side it lies on. Not swipeable.
class SwitchedPages extends StatefulWidget {
  const SwitchedPages({super.key, required this.index, required this.children});

  final int index;
  final List<Widget> children;

  @override
  State<SwitchedPages> createState() => _SwitchedPagesState();
}

class _SwitchedPagesState extends State<SwitchedPages>
    with SingleTickerProviderStateMixin {
  late final AnimationController _enter = AnimationController(
    vsync: this,
    duration: Motion.wipe,
    value: 1,
  );
  late final Animation<double> _t =
      CurvedAnimation(parent: _enter, curve: Motion.snap);
  double _from = 0;

  @override
  void didUpdateWidget(covariant SwitchedPages old) {
    super.didUpdateWidget(old);
    if (old.index != widget.index && !Motion.reduced(context)) {
      _from = widget.index > old.index ? 24 : -24;
      _enter.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _enter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _t,
      builder: (context, child) => Transform.translate(
        offset: Offset(_from * (1 - _t.value), 0),
        child: child,
      ),
      // Its own layer: the slide moves the page, it does not repaint it.
      child: RepaintBoundary(
        child: IndexedStack(index: widget.index, children: widget.children),
      ),
    );
  }
}

/// One game's page: its numbers, continue reading (in that game), its
/// shelves, what was read in it lately; a note when its knowledge base is
/// missing.
class GameLibraryView extends ConsumerWidget {
  const GameLibraryView({super.key, required this.game});

  final Game game;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(gameLibraryStatusProvider(game));
    if (status.isLoading) return const LoadingView();
    return switch (status.valueOrNull) {
      LibraryStatus.ready => _page(context, ref),
      LibraryStatus.oldSchema => LibraryMessage(
          icon: Icons.system_update_alt_sharp,
          title: context.t.libraryOldSchemaTitle,
          description: context.t.libraryOldSchemaDesc,
        ),
      _ => LibraryMessage(
          key: ValueKey('library-missing-${game.key}'),
          icon: Icons.download_for_offline_sharp,
          title: context.t.libraryGameMissing(gameLabel(context, game)),
          description: context.t.libraryNotInstalledDesc,
          action: AppButton(
            context.t.libraryOpenKnowledgeBase,
            kind: ButtonKind.go,
            onPressed: () => Navigator.of(context).pushNamed('/knowledge-base'),
          ),
        ),
    };
  }

  Widget _page(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    final recent = [
      for (final e in ref.watch(recentReadingProvider).valueOrNull ??
          const <ReadingEntry>[])
        if (_gameOf(e) == game) e,
    ];

    return RefreshIndicator(
      color: theme.trace,
      backgroundColor: theme.cardSurface,
      edgeOffset: MediaQuery.paddingOf(context).top + topBarInset,
      onRefresh: () async {
        ref
          ..invalidate(libraryStatusProvider)
          ..invalidate(gameLibraryStatusProvider(game))
          ..invalidate(shelfSummariesProvider(game))
          ..invalidate(codexTypesProvider(game));
        invalidateReading(ref);
      },
      child: ListView(
        key: ValueKey('library-game-${game.key}'),
        padding:
            pagePadding(context, const EdgeInsets.fromLTRB(16, 16, 16, 32)),
        children: [
          _GameFigures(game: game),
          if (recent.isNotEmpty) ...[
            const SizedBox(height: 16),
            _ContinueCard(entry: recent.first),
          ],
          _GameShelves(game: game),
          if (recent.length > 1) ...[
            IndustrialSectionHeader(
              theme: theme,
              title: context.t.readingHistoryTitle,
              code: 'recent',
              trailing: AppButton(
                context.t.libraryViewAll,
                key: const ValueKey('library-all-recent'),
                small: true,
                kind: ButtonKind.quiet,
                icon: Icons.chevron_right_sharp,
                onPressed: () => Navigator.of(context).push(
                  smoothPageRoute<void>(
                    frosted: true,
                    builder: (_) => const ReadingHistoryPage(),
                  ),
                ),
              ),
            ),
            for (final e in recent.skip(1).take(4)) ...[
              rowDivider(theme),
              _RecentRow(entry: e),
            ],
            rowDivider(theme),
          ],
        ],
      ),
    );
  }
}

/// The game a reading-history entry belongs to (by its id's namespace).
Game? _gameOf(ReadingEntry entry) {
  final item = LibraryRef.tryParse(entry.ref);
  return item == null ? null : gameOfId(item.id);
}

/// What the game's knowledge base holds, in three real numbers.
class _GameFigures extends ConsumerWidget {
  const _GameFigures({required this.game});

  final Game game;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    final summaries =
        ref.watch(shelfSummariesProvider(game)).valueOrNull ?? const [];
    final codex = ref.watch(codexTypesProvider(game)).valueOrNull ?? const [];
    if (summaries.isEmpty) return const SizedBox.shrink();
    final stories = summaries.fold<int>(0, (n, s) => n + s.stories);
    final collections = summaries.fold<int>(0, (n, s) => n + s.collections);
    final entries = codex.fold<int>(0, (n, t) => n + t.count);
    return InkPanel(
      key: ValueKey('library-figures-${game.key}'),
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Which game, in words (not the decorative script).
          Text(
            game == Game.arknights
                ? 'ARKNIGHTS  ${context.t.gameArknights}'
                : 'ENDFIELD  ${context.t.gameEndfield}',
            style: theme.label(),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Figure(
                    groupDigits(stories),
                    context.t.libraryFigureStories,
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Figure(
                    groupDigits(collections),
                    context.t.libraryFigureCollections,
                  ),
                ),
              ),
              if (entries > 0)
                Expanded(
                  child: Figure(
                    groupDigits(entries),
                    context.t.libraryFigureEntries,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 12345 as "12,345".
String groupDigits(int n) {
  final s = n.abs().toString();
  final out = StringBuffer(n < 0 ? '-' : '');
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) out.write(',');
    out.write(s[i]);
  }
  return out.toString();
}

/// One game's shelves: a heading and one numbered row per shelf, its codex
/// last.
class _GameShelves extends ConsumerWidget {
  const _GameShelves({required this.game});

  final Game game;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    final summaries =
        ref.watch(shelfSummariesProvider(game)).valueOrNull ?? const [];
    final codex = ref.watch(codexTypesProvider(game)).valueOrNull ?? const [];
    final codexCount = codex.fold<int>(0, (n, t) => n + t.count);
    final rows = <(String, List<String>)>[
      for (final s in summaries)
        (
          s.kind,
          [
            context.t.libraryCountCollections(s.collections),
            if (s.stories > 0) context.t.libraryCountStories(s.stories),
          ],
        ),
      if (codexCount > 0)
        (codexShelfOf(game), [context.t.libraryCountEntries(codexCount)]),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        IndustrialSectionHeader(
          theme: theme,
          title: context.t.libraryShelves,
          code: 'shelves',
        ),
        for (final (i, (kind, facts)) in rows.indexed) ...[
          rowDivider(theme),
          _ShelfRow(index: i + 1, kind: kind, facts: facts),
        ],
        rowDivider(theme),
      ],
    );
  }
}

class _ShelfRow extends ConsumerWidget {
  const _ShelfRow({
    required this.index,
    required this.kind,
    required this.facts,
  });

  final int index;
  final String kind;
  final List<String> facts;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    return Semantics(
      button: true,
      child: PressRow(
        key: ValueKey('shelf-$kind'),
        onTap: () => openShelf(context, kind),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 60),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 10, 4, 10),
            child: Row(
              children: [
                SizedBox(
                  width: 36,
                  child: Text(
                    index.toString().padLeft(2, '0'),
                    style: theme.field(color: theme.textMuted, size: 14),
                  ),
                ),
                Icon(shelfIcon(kind), size: 22, color: theme.textSecondary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        shelfLabel(context, kind),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.heading(16),
                      ),
                      const SizedBox(height: 2),
                      FactsRow(facts),
                    ],
                  ),
                ),
                ExcludeSemantics(
                  child: Icon(
                    Icons.chevron_right_sharp,
                    color: theme.textMuted,
                    size: 22,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The story read last, with a way to continue it.
class _ContinueCard extends ConsumerWidget {
  const _ContinueCard({required this.entry});

  final ReadingEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    final ref0 = LibraryRef.tryParse(entry.ref);
    final progress = entry.progress;
    return ThemeAwareCard(
      key: const ValueKey('library-continue'),
      padding: const EdgeInsets.fromLTRB(16, 18, 20, 16),
      onTap: ref0 == null || ref0.kind != LibraryRefKind.story
          ? null
          : () => openStory(context, ref0.id, resume: entry),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  context.t.libraryContinue,
                  style: theme.ui(13, weight: 700, color: theme.textSecondary),
                ),
              ),
              if (progress != null)
                Text(
                  entry.finished
                      ? context.t.libraryFinished
                      : '${(progress * 100).round().toString().padLeft(3, '0')}%',
                  style: theme.field(color: theme.textPrimary, weight: 600),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            readingTitle(ref, entry),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.heading(18),
          ),
          if (entry.snippet.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              entry.snippet,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.text(14, color: theme.textSecondary, height: 1.55),
            ),
          ],
          if (progress != null) ...[
            const SizedBox(height: 12),
            ProgressLine(progress),
          ],
        ],
      ),
    );
  }
}

class _RecentRow extends ConsumerWidget {
  const _RecentRow({required this.entry});

  final ReadingEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    final item = LibraryRef.tryParse(entry.ref);
    return LibraryRow(
      key: ValueKey('recent-${entry.ref}'),
      title: readingTitle(ref, entry),
      subtitle: entry.snippet,
      subtitleLines: 1,
      progress:
          entry.progress != null && !entry.finished ? entry.progress : null,
      trailing: readMark(context, theme, entry),
      onTap: item == null || item.kind != LibraryRefKind.story
          ? null
          : () => openStory(context, item.id, resume: entry),
    );
  }
}
