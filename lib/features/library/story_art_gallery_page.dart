import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/library/story_art_gallery.dart';
import '../../shared/l10n/l10n.dart';
import '../../shared/providers/theme_provider.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/theme/motion.dart';
import '../../shared/widgets/ef_widgets.dart';
import '../../shared/widgets/page_frame.dart';
import '../../shared/widgets/portrait_image.dart';
import 'collection_art_page.dart';
import 'library_widgets.dart';
import 'portrait_sheet.dart';
import 'story_art_viewer.dart';

class StoryArtGalleryPage extends ConsumerStatefulWidget {
  const StoryArtGalleryPage({super.key});
  @override
  ConsumerState<StoryArtGalleryPage> createState() =>
      _StoryArtGalleryPageState();
}

class _StoryArtGalleryPageState extends ConsumerState<StoryArtGalleryPage> {
  String kind = 'cg', search = '';
  final scroll = ScrollController();
  final expanded = <(String, String)>{};
  final searchController = TextEditingController();
  @override
  void dispose() {
    scroll.dispose();
    searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider);
    final result = ref.watch(storyArtGalleryProvider);
    final gallery = result.valueOrNull ?? const StoryArtGallery();
    final shots = gallery.shots(kind);
    final groups = [
      for (final group in gallery.groups)
        if (group.shots.any((a) => a.shot.kind == kind))
          GalleryArtGroup(
            group.id,
            group.title,
            group.shots.where((a) => a.shot.kind == kind).toList(),
          ),
    ];
    final portraits = gallery.portraits
        .where(
          (p) => p.names.any((name) => name.contains(search.trim())),
        )
        .toList();
    return PageScaffold(
      title: context.t.collectionArtTitle,
      body: Padding(
        padding: pagePadding(
          context,
          const EdgeInsets.fromLTRB(16, 12, 16, 0),
          topBar: false,
        ),
        child: Column(
          children: [
            SegmentedChoice(
              options: [
                ('portrait', context.t.artGalleryPortraits),
                ('scene', context.t.artGalleryBackgrounds),
                ('cg', 'CG'),
              ],
              value: kind,
              onChanged: (value) {
                if (scroll.hasClients) scroll.jumpTo(0);
                setState(() => kind = value);
              },
            ),
            if (kind == 'portrait')
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: TextField(
                  controller: searchController,
                  decoration: InputDecoration(
                    labelText: context.t.artGallerySearch,
                    prefixIcon: const Icon(Icons.search_sharp),
                  ),
                  onChanged: (value) => setState(() => search = value),
                ),
              ),
            Expanded(
              child: result.isLoading
                  ? const LoadingView()
                  : kind == 'portrait'
                      ? portraits.isEmpty
                          ? EmptyState(text: context.t.artGalleryEmpty)
                          : ListView.builder(
                              itemCount: portraits.length,
                              itemBuilder: (context, i) {
                                final portrait = portraits[i];
                                return PressRow(
                                  key: ValueKey(
                                      'gallery-portrait-${portrait.id}',),
                                  onTap: () => showPortraitGroupSheet(
                                    context,
                                    sprite: portrait.sprite,
                                    listSpeaker: portrait.names.first,
                                    origin: PortraitOrigin.materials,
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 12,),
                                    child: Row(
                                      children: [
                                        SizedBox(
                                          width: 56,
                                          height: 72,
                                          child: PortraitImage(
                                              sprite: portrait.sprite,),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(portrait.names.first,
                                                  style: theme.heading(16),),
                                              Text(
                                                context.t.portraitLines(
                                                    portrait.lines,),
                                                style: theme.field(),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Icon(Icons.chevron_right_sharp,
                                            color: theme.textPrimary,),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            )
                      : shots.isEmpty
                          ? EmptyState(text: context.t.artGalleryEmpty)
                          : LayoutBuilder(
                              builder: (context, constraints) {
                                final tileHeight =
                                    (constraints.maxWidth - 12) / 3 * 9 / 16;
                                double offset(int index) =>
                                    groups.take(index).fold(
                                          0.0,
                                          (sum, group) =>
                                              sum +
                                              64 +
                                              (expanded.contains((kind, group.id))
                                                  ? (group.shots.length / 3).ceil() *
                                                      (tileHeight + 6) - 6
                                                  : 0),
                                        );
                                return Column(
                                  children: [
                                    SingleChildScrollView(
                                      scrollDirection: Axis.horizontal,
                                      child: Row(
                                        children: [
                                          for (final (i, group)
                                              in groups.indexed)
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                  right: 8,),
                                              child: AppButton(
                                                group.title,
                                                small: true,
                                                onPressed: () {
                                                  setState(() => expanded.add((kind, group.id)));
                                                  WidgetsBinding.instance.addPostFrameCallback((_) {
                                                    if (!mounted || !scroll.hasClients) return;
                                                    scroll.animateTo(
                                                      offset(i).clamp(0, scroll.position.maxScrollExtent),
                                                      duration: Motion.of(context, Motion.row),
                                                      curve: Motion.snap,
                                                    );
                                                  });
                                                },
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                    Expanded(
                                      child: CustomScrollView(
                                        controller: scroll,
                                        slivers: [
                                          for (final group in groups) ...[
                                            SliverToBoxAdapter(
                                              child: SizedBox(
                                                height: 64,
                                                child: FoldBlock(
                                                  headKey: ValueKey('gallery-group-$kind-${group.id}'),
                                                  open: expanded.contains((kind, group.id)),
                                                  onTap: () => setState(() {
                                                    final key = (kind, group.id);
                                                    if (!expanded.remove(key)) expanded.add(key);
                                                  }),
                                                  head: GroupHeading(title: group.title, count: group.shots.length),
                                                ),
                                              ),
                                            ),
                                            if (expanded.contains((kind, group.id)))
                                              SliverGrid.builder(
                                                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                                  crossAxisCount: 3,
                                                  childAspectRatio: 16 / 9,
                                                  mainAxisSpacing: 6,
                                                  crossAxisSpacing: 6,
                                                ),
                                                itemCount: group.shots.length,
                                                itemBuilder: (context, i) => ArtThumbnail(
                                                  art: group.shots[i],
                                                  onTap: () => openArtViewer(
                                                    context,
                                                    pages: [
                                                      ArtViewerPage.story(
                                                        storyId: group.shots[i].storyId,
                                                        storyTitle: group.shots[i].storyTitle,
                                                        shot: group.shots[i].shot.copyWith(
                                                          number: shots.indexOf(group.shots[i]) + 1,
                                                          total: shots.length,
                                                        ),
                                                      ),
                                                    ],
                                                    initial: 0,
                                                  ),
                                                ),
                                              ),
                                          ],
                                          // Leave room to bring even the final heading to the top.
                                          SliverToBoxAdapter(
                                              child: SizedBox(
                                                  height:
                                                      constraints.maxHeight,),),
                                        ],
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                context.t.storyArtCredit,
                style: theme.text(12, color: theme.textMuted),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
