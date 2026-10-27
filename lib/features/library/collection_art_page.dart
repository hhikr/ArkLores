import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/library/collection_story_art.dart';
import '../../shared/l10n/l10n.dart';
import '../../shared/providers/theme_provider.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/theme/cut_border.dart';
import '../../shared/widgets/ef_widgets.dart';
import '../../shared/widgets/page_frame.dart';
import '../../shared/widgets/press_feedback.dart';
import '../../shared/widgets/story_art_composite.dart';
import 'story_art_viewer.dart';

void openCollectionArt(
  BuildContext context,
  List<CollectionArtShot> shots,
  int initial,
) =>
    openArtViewer(
      context,
      pages: [
        for (final art in shots)
          ArtViewerPage.story(
            storyId: art.storyId,
            storyTitle: art.storyTitle,
            shot: art.shot,
          ),
      ],
      initial: initial,
    );

class ArtThumbnail extends ConsumerWidget {
  const ArtThumbnail({super.key, required this.art, required this.onTap});
  final CollectionArtShot art;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    return Semantics(
      button: true,
      label: art.storyTitle,
      child: PressBuilder(
        builder: (context, down) => GestureDetector(
          onTap: onTap,
          child: ClipPath(
            clipper: const ShapeBorderClipper(
              shape: CutBorder(bottomRight: 8),
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                StoryArtComposite(art.shot, fit: BoxFit.cover),
                if (down)
                  ColoredBox(
                    color: theme.textPrimary.withValues(alpha: .1),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class CollectionArtPage extends ConsumerStatefulWidget {
  const CollectionArtPage({super.key, required this.collectionId});
  final String collectionId;
  @override
  ConsumerState<CollectionArtPage> createState() => _CollectionArtPageState();
}

class _CollectionArtPageState extends ConsumerState<CollectionArtPage> {
  String kind = 'cg';
  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider);
    final art = ref
            .watch(collectionStoryArtProvider(widget.collectionId))
            .valueOrNull ??
        [];
    final options = [
      if (art.any((a) => a.shot.kind == 'cg')) ('cg', 'CG'),
      if (art.any((a) => a.shot.kind == 'scene'))
        ('scene', context.t.storyArtScene),
    ];
    final selected =
        options.any((o) => o.$1 == kind) ? kind : options.firstOrNull?.$1;
    final shots = art.where((a) => a.shot.kind == selected).toList();
    final groups = <String, List<CollectionArtShot>>{};
    for (final shot in shots) {
      (groups[shot.storyId] ??= []).add(shot);
    }
    return PageScaffold(
      title: context.t.collectionArtTitle,
      scrollUnder: true,
      body: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: pagePadding(
              context,
              const EdgeInsets.fromLTRB(16, 12, 16, 0),
            ),
            sliver: SliverToBoxAdapter(
              child: options.isEmpty
                  ? const SizedBox.shrink()
                  : SegmentedChoice(
                      options: options,
                      value: selected!,
                      onChanged: (value) => setState(() => kind = value),
                    ),
            ),
          ),
          for (final group in groups.values) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        group.first.storyTitle,
                        style: theme.heading(15),
                      ),
                    ),
                    Text('${group.length}', style: theme.field()),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverGrid.builder(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: selected == 'cg' ? 2 : 3,
                  childAspectRatio: 16 / 9,
                  mainAxisSpacing: 6,
                  crossAxisSpacing: 6,
                ),
                itemCount: group.length,
                itemBuilder: (context, i) => ArtThumbnail(
                  art: group[i],
                  onTap: () => openCollectionArt(
                    context,
                    shots,
                    shots.indexOf(group[i]),
                  ),
                ),
              ),
            ),
          ],
          SliverToBoxAdapter(
            child: SizedBox(
              height: 24 + MediaQuery.viewPaddingOf(context).bottom,
            ),
          ),
        ],
      ),
    );
  }
}
