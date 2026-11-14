import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
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

const double _gap = 8;
const double _gutter = 16;

void openCollectionArt(BuildContext context, CollectionArtShot art) =>
    openArtViewer(
      context,
      pages: [
        ArtViewerPage.story(
          storyId: art.storyId,
          storyTitle: art.storyTitle,
          shot: art.shot,
        ),
      ],
      initial: 0,
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
                    color: pressTint(Colors.transparent, theme.textPrimary),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One line of the page: a story's heading, or a row of one or two pictures.
class _ArtLine {
  const _ArtLine.head(this.story, this.count) : shots = const [];
  const _ArtLine.shots(this.shots)
      : story = null,
        count = 0;
  final CollectionArtShot? story;
  final int count;
  final List<CollectionArtShot> shots;
}

/// The lines of [shots], which are in story order: under each story's heading
/// a wide picture when the number is odd, then pairs.
List<_ArtLine> _artLines(List<CollectionArtShot> shots) {
  final groups = <String, List<CollectionArtShot>>{};
  for (final shot in shots) {
    (groups[shot.storyId] ??= []).add(shot);
  }
  return [
    for (final group in groups.values) ...[
      _ArtLine.head(group.first, group.length),
      if (group.length.isOdd) _ArtLine.shots([group.first]),
      for (var i = group.length % 2; i < group.length; i += 2)
        _ArtLine.shots([group[i], group[i + 1]]),
    ],
  ];
}

/// The pictures of one collection, story by story, all shown: the page is
/// opened to look at them.
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
        const <CollectionArtShot>[];
    List<CollectionArtShot> ofKind(String kind) =>
        art.where((a) => a.shot.kind == kind).toList();
    final cgs = ofKind('cg');
    final scenes = ofKind('scene');
    final selected = kind == 'cg' && cgs.isEmpty
        ? 'scene'
        : kind == 'scene' && scenes.isEmpty
            ? 'cg'
            : kind;
    final lines = _artLines(selected == 'cg' ? cgs : scenes);
    return PageScaffold(
      title: context.t.collectionArtTitle,
      body: Padding(
        padding: pagePadding(context, EdgeInsets.zero, topBar: false),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (cgs.isNotEmpty && scenes.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(_gutter, 12, _gutter, 12),
                child: SegmentedChoice(
                  options: [
                    ('cg', 'CG ${cgs.length}'),
                    ('scene', '${context.t.storyArtScene} ${scenes.length}'),
                  ],
                  value: selected,
                  onChanged: (value) => setState(() => kind = value),
                ),
              ),
              Divider(height: 1, color: theme.divider),
            ],
            Expanded(
              child: CustomScrollView(
                key: ValueKey('collection-art-$selected'),
                scrollCacheExtent: const ScrollCacheExtent.pixels(240),
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: _gutter),
                    sliver: SliverList.builder(
                      itemCount: lines.length,
                      itemBuilder: (context, i) {
                        final line = lines[i];
                        final story = line.story;
                        return story != null
                            ? _StoryHead(
                                story: story,
                                count: line.count,
                                first: i == 0,
                              )
                            : _shotRow(line.shots);
                      },
                    ),
                  ),
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                      _gutter,
                      16,
                      _gutter,
                      16 + MediaQuery.viewPaddingOf(context).bottom,
                    ),
                    sliver: SliverToBoxAdapter(
                      child: Text(
                        context.t.storyArtCredit,
                        style: theme.text(12, color: theme.textMuted),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _shotRow(List<CollectionArtShot> shots) {
    Widget tile(CollectionArtShot art) => AspectRatio(
          aspectRatio: 16 / 9,
          child: ArtThumbnail(
            art: art,
            onTap: () => openCollectionArt(context, art),
          ),
        );
    return Padding(
      padding: const EdgeInsets.only(bottom: _gap),
      child: shots.length == 1
          ? tile(shots.single)
          : Row(
              children: [
                Expanded(child: tile(shots[0])),
                const SizedBox(width: _gap),
                Expanded(child: tile(shots[1])),
              ],
            ),
    );
  }
}

/// A story's heading over its pictures: its code, name and part, how many.
class _StoryHead extends ConsumerWidget {
  const _StoryHead({
    required this.story,
    required this.count,
    required this.first,
  });
  final CollectionArtShot story;
  final int count;
  final bool first;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    final code = story.storyCode;
    return Container(
      key: ValueKey('collection-art-head-${story.storyId}'),
      margin: EdgeInsets.only(top: first ? 4 : 16),
      padding: const EdgeInsets.fromLTRB(0, 12, 0, 12),
      decoration: first
          ? null
          : BoxDecoration(
              border: Border(top: BorderSide(color: theme.divider)),
            ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (code != null && code.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: IndexTag(code),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(child: Text(story.storyName, style: theme.heading(15))),
          const SizedBox(width: 12),
          Text('$count', style: theme.field()),
        ],
      ),
    );
  }
}
