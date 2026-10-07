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
import '../../shared/widgets/floating_bar.dart';
import '../../shared/widgets/industrial_ui.dart';
import '../../shared/widgets/smooth_page_route.dart';
import '../../shared/widgets/theme_aware_card.dart';
import '../ai/reading_history_page.dart';
import '../library/library_pages.dart';
import '../library/library_widgets.dart';
import '../library/my_materials.dart';

/// The library tab: what can be read (the knowledge base's stories and
/// texts, by shelf) and the user's own texts.
class MaterialsPage extends ConsumerStatefulWidget {
  const MaterialsPage({super.key});

  @override
  ConsumerState<MaterialsPage> createState() => _MaterialsPageState();
}

class _MaterialsPageState extends ConsumerState<MaterialsPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this)
    ..addListener(() {
      if (!_tabs.indexIsChanging && mounted) setState(() {});
    });

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider);
    final reading = _tabs.index == 0;
    // The tabs float over the lists, which scroll underneath them.
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          TabBarView(
            controller: _tabs,
            children: const [
              LibraryReadView(),
              MyMaterialsView(),
            ],
          ),
          // Tabs on the left, the action on the right: two pills.
          FloatingTopBar(
            theme: theme,
            leading: Row(
              key: const ValueKey('library-tabs'),
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final (i, label) in [
                  context.t.libraryTabRead,
                  context.t.libraryTabMine,
                ].indexed)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: FloatingSegment(
                      theme: theme,
                      label: label,
                      selected: _tabs.index == i,
                      onTap: () => _tabs.animateTo(i),
                    ),
                  ),
              ],
            ),
            trailing: reading
                ? IconButton(
                    key: const ValueKey('library-search'),
                    tooltip: context.t.librarySearchHint,
                    color: theme.textPrimary,
                    icon: const Icon(Icons.search_rounded, size: 22),
                    onPressed: () => openSearch(context),
                  )
                : IconButton(
                    key: const ValueKey('library-new-material'),
                    tooltip: context.t.materialsNew,
                    color: theme.textPrimary,
                    icon: const Icon(Icons.add_rounded, size: 22),
                    onPressed: () => newMaterial(context),
                  ),
          ),
        ],
      ),
    );
  }
}

/// "Read": continue reading, each game's shelves, the recently read.
class LibraryReadView extends ConsumerWidget {
  const LibraryReadView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    final statuses = {
      for (final game in Game.values)
        game: ref.watch(gameLibraryStatusProvider(game)),
    };
    if (statuses.values.any((s) => s.isLoading)) {
      return const Center(child: CircularProgressIndicator());
    }
    final ready = [
      for (final game in Game.values)
        if (statuses[game]!.valueOrNull == LibraryStatus.ready) game,
    ];
    if (ready.isEmpty) {
      final old =
          statuses.values.any((s) => s.valueOrNull == LibraryStatus.oldSchema);
      return old
          ? LibraryMessage(
              icon: Icons.system_update_alt_rounded,
              title: context.t.libraryOldSchemaTitle,
              description: context.t.libraryOldSchemaDesc,
            )
          : LibraryMessage(
              icon: Icons.download_for_offline_rounded,
              title: context.t.libraryNotInstalledTitle,
              description: context.t.libraryNotInstalledDesc,
            );
    }
    return _shelves(context, ref, theme, ready);
  }

  Widget _shelves(
    BuildContext context,
    WidgetRef ref,
    AppThemeTokens theme,
    List<Game> ready,
  ) {
    final recent = ref.watch(recentReadingProvider).valueOrNull ?? const [];
    final missing = [
      for (final game in Game.values)
        if (!ready.contains(game)) game,
    ];

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(libraryStatusProvider);
        for (final game in Game.values) {
          ref
            ..invalidate(gameLibraryStatusProvider(game))
            ..invalidate(shelfSummariesProvider(game))
            ..invalidate(codexTypesProvider(game));
        }
        invalidateReading(ref);
      },
      child: ListView(
        padding:
            floatingPadding(context, const EdgeInsets.fromLTRB(16, 4, 16, 32)),
        children: [
          if (recent.isNotEmpty) ...[
            const SizedBox(height: 12),
            _ContinueCard(entry: recent.first),
          ],
          for (final game in ready)
            _GameShelves(
                game: game, titled: ready.length > 1 || game != Game.arknights,),
          for (final game in missing)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: LibraryRow(
                key: ValueKey('library-missing-${game.key}'),
                title: context.t.libraryGameMissing(gameLabel(context, game)),
                subtitle: context.t.libraryNotInstalledDesc,
                subtitleLines: 2,
                leading: Icon(Icons.download_for_offline_rounded,
                    color: theme.textMuted,),
              ),
            ),
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

/// One game's shelves: a heading (when there is more than one game) and the
/// shelf cards, its codex last.
class _GameShelves extends ConsumerWidget {
  const _GameShelves({required this.game, required this.titled});

  final Game game;
  final bool titled;

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
      key: ValueKey('library-game-${game.key}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        IndustrialSectionHeader(
          theme: theme,
          title: titled ? gameLabel(context, game) : context.t.libraryShelves,
          code: game == Game.arknights ? 'shelves' : 'endfield',
        ),
        GridView.count(
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
                Icons.play_circle_fill_rounded,
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
