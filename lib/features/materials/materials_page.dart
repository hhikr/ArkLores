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
import '../../shared/widgets/floating_bar.dart';
import '../../shared/widgets/industrial_ui.dart';
import '../../shared/widgets/smooth_page_route.dart';
import '../../shared/widgets/theme_aware_card.dart';
import '../ai/reading_history_page.dart';
import '../library/library_pages.dart';
import '../library/library_widgets.dart';
import '../library/my_materials.dart';

/// The library tab: one page per game (its shelves, what was read in it)
/// and the user's own texts, chosen in the top bar. The pages are not
/// swiped between (a sideways drag on a shelf is not a request to change
/// game); the chosen one fades and slides in a short way.
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
    final theme = ref.watch(themeProvider);
    final labels = [
      for (final game in Game.values) gameLabel(context, game),
      context.t.libraryTabMine,
    ];
    // The tabs float over the lists, which scroll underneath them.
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          SwitchedPages(
            index: _tab,
            children: [
              for (final game in Game.values) GameLibraryView(game: game),
              const MyMaterialsView(),
            ],
          ),
          // Tabs on the left, the action on the right: two plates.
          FloatingTopBar(
            theme: theme,
            leading: Row(
              key: const ValueKey('library-tabs'),
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final (i, label) in labels.indexed)
                  Flexible(
                    child: FloatingSegment(
                      key: ValueKey('library-tab-$i'),
                      theme: theme,
                      label: label,
                      selected: _tab == i,
                      onTap: () => setState(() => _tab = i),
                    ),
                  ),
              ],
            ),
            trailing: !_mine
                ? IconButton(
                    key: const ValueKey('library-search'),
                    tooltip: context.t.librarySearchHint,
                    color: theme.textPrimary,
                    icon: const Icon(Icons.search_sharp, size: 22),
                    onPressed: () => openSearch(context),
                  )
                : IconButton(
                    key: const ValueKey('library-new-material'),
                    tooltip: context.t.materialsNew,
                    color: theme.textPrimary,
                    icon: const Icon(Icons.add_sharp, size: 22),
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
/// short fade and a slide from the side it lies on. Not swipeable.
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
    duration: const Duration(milliseconds: 260),
    value: 1,
  );
  late final Animation<double> _t =
      CurvedAnimation(parent: _enter, curve: Curves.easeOutExpo);
  double _from = 0;

  @override
  void didUpdateWidget(covariant SwitchedPages old) {
    super.didUpdateWidget(old);
    if (old.index != widget.index) {
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
      builder: (context, child) => Opacity(
        opacity: _t.value,
        child: Transform.translate(
          offset: Offset(_from * (1 - _t.value), 0),
          child: child,
        ),
      ),
      child: IndexedStack(index: widget.index, children: widget.children),
    );
  }
}

/// One game's page: continue reading (in that game), its shelves, what was
/// read in it lately; a note when its knowledge base is missing.
class GameLibraryView extends ConsumerWidget {
  const GameLibraryView({super.key, required this.game});

  final Game game;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(gameLibraryStatusProvider(game));
    if (status.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
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
        ),
    };
  }

  Widget _page(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    final recent = [
      for (final e
          in ref.watch(recentReadingProvider).valueOrNull ?? const <ReadingEntry>[])
        if (_gameOf(e) == game) e,
    ];

    return RefreshIndicator(
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
            floatingPadding(context, const EdgeInsets.fromLTRB(16, 4, 16, 32)),
        children: [
          if (recent.isNotEmpty) ...[
            const SizedBox(height: 12),
            _ContinueCard(entry: recent.first),
          ],
          _GameShelves(game: game),
          if (recent.length > 1) ...[
            IndustrialSectionHeader(
              theme: theme,
              title: context.t.readingHistoryTitle,
              code: 'recent',
            ),
            for (final e in recent.skip(1).take(4)) ...[
              _RecentRow(entry: e),
              rowDivider(theme),
            ],
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                key: const ValueKey('library-all-recent'),
                onPressed: () => Navigator.of(context).push(
                  smoothPageRoute<void>(
                    builder: (_) => const ReadingHistoryPage(),
                  ),
                ),
                child: Text(
                  context.t.libraryViewAll,
                  style: TextStyle(color: theme.accentText),
                ),
              ),
            ),
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

/// One game's shelves: a heading and the shelf cards, its codex last.
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
    final cards = <Widget>[
      for (final s in summaries)
        _ShelfCard(
          kind: s.kind,
          subtitle: [
            context.t.libraryCountCollections(s.collections),
            if (s.stories > 0) context.t.libraryCountStories(s.stories),
          ].join(' · '),
        ),
      if (codexCount > 0)
        _ShelfCard(
          kind: codexShelfOf(game),
          subtitle: context.t.libraryCountEntries(codexCount),
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        IndustrialSectionHeader(
          theme: theme,
          title: context.t.libraryShelves,
          code: game == Game.arknights ? 'arknights' : 'endfield',
        ),
        GridView.count(
          // Inside the padded list: without its own padding the grid would
          // add the status bar and the floating bar's room again.
          padding: EdgeInsets.zero,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.55,
          children: cards,
        ),
      ],
    );
  }
}

class _ShelfCard extends ConsumerWidget {
  const _ShelfCard({required this.kind, required this.subtitle});

  final String kind;
  final String subtitle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    return ThemeAwareCard(
      key: ValueKey('shelf-$kind'),
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      onTap: () => openShelf(context, kind),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(shelfIcon(kind), color: theme.accentText, size: 26),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                shelfLabel(context, kind),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.titleFont.copyWith(fontSize: 16),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.bodyFont.copyWith(
                  color: theme.textSecondary,
                  fontSize: 11.5,
                ),
              ),
            ],
          ),
        ],
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
      padding: const EdgeInsets.all(16),
      onTap: ref0 == null || ref0.kind != LibraryRefKind.story
          ? null
          : () => openStory(context, ref0.id, resume: entry),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.play_circle_fill_sharp,
                color: theme.accentText,
                size: 18,
              ),
              const SizedBox(width: 6),
              Text(
                context.t.libraryContinue,
                style: theme.bodyFont.copyWith(
                  color: theme.accentText,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                ),
              ),
              const Spacer(),
              if (progress != null)
                AccentPill(
                  entry.finished
                      ? context.t.libraryFinished
                      : context.t.libraryProgress((progress * 100).round()),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            readingTitle(ref, entry),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.titleFont.copyWith(fontSize: 17, height: 1.3),
          ),
          if (entry.snippet.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              entry.snippet,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.bodyFont.copyWith(
                color: theme.textSecondary,
                fontSize: 12.5,
                height: 1.5,
              ),
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
