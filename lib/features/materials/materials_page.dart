import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/library/library_provider.dart';
import '../../core/library/library_queries.dart';
import '../../core/userdata/library_ref.dart';
import '../../core/userdata/user_data_provider.dart';
import '../../core/userdata/user_data_store.dart';
import '../../shared/l10n/l10n.dart';
import '../../shared/providers/theme_provider.dart';
import '../../shared/theme/app_theme.dart';
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
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: theme.bgSecondary,
        elevation: 0,
        titleSpacing: 4,
        title: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          dividerColor: Colors.transparent,
          indicatorColor: theme.accentPrimary,
          indicatorSize: TabBarIndicatorSize.label,
          indicatorWeight: 2.5,
          labelPadding: const EdgeInsets.symmetric(horizontal: 12),
          labelColor: theme.textPrimary,
          unselectedLabelColor: theme.textSecondary,
          labelStyle: theme.titleFont.copyWith(
            fontSize: 15.5,
            fontWeight: FontWeight.bold,
          ),
          unselectedLabelStyle: theme.titleFont.copyWith(fontSize: 15.5),
          tabs: [
            Tab(text: context.t.libraryTabRead),
            Tab(text: context.t.libraryTabMine),
          ],
        ),
        actions: [
          if (reading)
            IconButton(
              key: const ValueKey('library-search'),
              tooltip: context.t.librarySearchHint,
              icon: const Icon(Icons.search_rounded),
              onPressed: () => openSearch(context),
            )
          else
            IconButton(
              key: const ValueKey('library-new-material'),
              tooltip: context.t.materialsNew,
              icon: const Icon(Icons.add_rounded),
              onPressed: () => newMaterial(context),
            ),
        ],
      ),
      body: TabBarView(
        controller: _tabs,
        children: const [
          LibraryReadView(),
          MyMaterialsView(),
        ],
      ),
    );
  }
}

/// "Read": continue reading, the shelves, the recently read.
class LibraryReadView extends ConsumerWidget {
  const LibraryReadView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    final status = ref.watch(libraryStatusProvider);
    return status.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => LibraryMessage(
        icon: Icons.folder_off_rounded,
        title: context.t.libraryNotInstalledTitle,
        description: context.t.libraryNotInstalledDesc,
      ),
      data: (s) => switch (s) {
        LibraryStatus.notInstalled => LibraryMessage(
            icon: Icons.download_for_offline_rounded,
            title: context.t.libraryNotInstalledTitle,
            description: context.t.libraryNotInstalledDesc,
          ),
        LibraryStatus.oldSchema => LibraryMessage(
            icon: Icons.system_update_alt_rounded,
            title: context.t.libraryOldSchemaTitle,
            description: context.t.libraryOldSchemaDesc,
          ),
        LibraryStatus.ready => _shelves(context, ref, theme),
      },
    );
  }

  Widget _shelves(BuildContext context, WidgetRef ref, AppThemeTokens theme) {
    final summaries = ref.watch(shelfSummariesProvider).valueOrNull ?? const [];
    final codex = ref.watch(codexTypesProvider).valueOrNull ?? const [];
    final recent = ref.watch(recentReadingProvider).valueOrNull ?? const [];
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
          kind: codexShelf,
          subtitle: context.t.libraryCountEntries(codexCount),
        ),
    ];

    return RefreshIndicator(
      onRefresh: () async {
        ref
          ..invalidate(libraryStatusProvider)
          ..invalidate(shelfSummariesProvider)
          ..invalidate(codexTypesProvider);
        invalidateReading(ref);
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          if (recent.isNotEmpty) ...[
            const SizedBox(height: 12),
            _ContinueCard(entry: recent.first),
          ],
          IndustrialSectionHeader(
            theme: theme,
            title: context.t.libraryShelves,
            code: 'shelves',
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
              Icon(Icons.play_circle_fill_rounded,
                  color: theme.accentText, size: 18,),
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
      progress: entry.progress != null && !entry.finished
          ? entry.progress
          : null,
      trailing: readMark(context, theme, entry),
      onTap: item == null || item.kind != LibraryRefKind.story
          ? null
          : () => openStory(context, item.id, resume: entry),
    );
  }
}
