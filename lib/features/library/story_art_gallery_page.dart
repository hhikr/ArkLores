import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/library/collection_story_art.dart';
import '../../core/library/story_art_gallery.dart';
import '../../shared/l10n/l10n.dart';
import '../../shared/providers/settings_provider.dart';
import '../../shared/providers/theme_provider.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/theme/cut_border.dart';
import '../../shared/theme/motion.dart';
import '../../shared/widgets/ef_widgets.dart';
import '../../shared/widgets/page_frame.dart';
import '../../shared/widgets/portrait_image.dart';
import '../../shared/widgets/press_feedback.dart';
import 'collection_art_page.dart';
import 'portrait_sheet.dart';
import 'story_art_viewer.dart';

const double _gap = 8;
const double _gutter = 16;

/// Every picture of the stories: the speakers, as a wall of figures, and the
/// backgrounds and CGs under the collection each first appears in. One search
/// over all three: names, picture titles and collections.
class StoryArtGalleryPage extends ConsumerStatefulWidget {
  const StoryArtGalleryPage({super.key});
  @override
  ConsumerState<StoryArtGalleryPage> createState() =>
      _StoryArtGalleryPageState();
}

class _StoryArtGalleryPageState extends ConsumerState<StoryArtGalleryPage> {
  String kind = 'portrait', query = '';
  final scroll = ScrollController();
  final searchController = TextEditingController();

  /// The groups the reader folded or opened against the rule of the moment.
  final turned = <(String, String)>{};

  StoryArtGallery? _matchedIn;
  String? _matchedQuery;
  GalleryMatches? _matches;

  @override
  void dispose() {
    scroll.dispose();
    searchController.dispose();
    super.dispose();
  }

  GalleryMatches _matchesOf(StoryArtGallery gallery) {
    if (!identical(_matchedIn, gallery) || _matchedQuery != query) {
      _matchedIn = gallery;
      _matchedQuery = query;
      _matches = gallery.matches(query);
    }
    return _matches!;
  }

  void _search(String value) {
    if (scroll.hasClients) scroll.jumpTo(0);
    setState(() {
      // Words open what they find; the reader's folds were for another list.
      if ((query.trim().isEmpty) != (value.trim().isEmpty)) turned.clear();
      query = value;
    });
  }

  bool _open(GalleryArtGroup group, bool folded) {
    final base = query.trim().isNotEmpty || !folded;
    return turned.contains((kind, group.id)) ? !base : base;
  }

  void _openShot(CollectionArtShot art, List<CollectionArtShot> all) =>
      openArtViewer(
        context,
        pages: [
          ArtViewerPage.story(
            storyId: art.storyId,
            storyTitle: art.storyTitle,
            shot: art.shot.copyWith(
              number: all.indexOf(art) + 1,
              total: all.length,
            ),
          ),
        ],
        initial: 0,
      );

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider);
    final folded = ref.watch(storyArtFoldedProvider);
    final result = ref.watch(storyArtGalleryProvider);
    final gallery = result.valueOrNull ?? const StoryArtGallery();
    final matches = _matchesOf(gallery);
    final portraits = matches.portraits();
    final scenes = matches.groups('scene');
    final cgs = matches.groups('cg');
    int count(List<GalleryArtGroup> groups) =>
        groups.fold(0, (sum, group) => sum + group.shots.length);
    final groups = kind == 'scene' ? scenes : cgs;
    final empty = kind == 'portrait' ? portraits.isEmpty : groups.isEmpty;
    return PageScaffold(
      title: context.t.collectionArtTitle,
      body: Padding(
        padding: pagePadding(context, EdgeInsets.zero, topBar: false),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(_gutter, 12, _gutter, 8),
              child: TextField(
                key: const ValueKey('gallery-search'),
                controller: searchController,
                decoration: InputDecoration(
                  labelText: context.t.artGallerySearch,
                  prefixIcon: const Icon(Icons.search_sharp),
                  suffixIcon: query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: context.t.artGallerySearchClear,
                          icon: const Icon(Icons.close_sharp),
                          onPressed: () {
                            searchController.clear();
                            _search('');
                          },
                        ),
                ),
                onChanged: _search,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(_gutter, 0, _gutter, 12),
              child: SegmentedChoice(
                options: [
                  (
                    'portrait',
                    '${context.t.artGalleryPortraits} ${portraits.length}',
                  ),
                  (
                    'scene',
                    '${context.t.artGalleryBackgrounds} ${count(scenes)}',
                  ),
                  ('cg', 'CG ${count(cgs)}'),
                ],
                value: kind,
                onChanged: (value) {
                  if (scroll.hasClients) scroll.jumpTo(0);
                  setState(() => kind = value);
                },
              ),
            ),
            Divider(height: 1, color: theme.divider),
            Expanded(
              child: result.isLoading && !result.hasValue
                  ? const LoadingView()
                  : empty
                      ? EmptyState(text: context.t.artGalleryEmpty)
                      : CustomScrollView(
                          key: ValueKey('gallery-list-$kind'),
                          controller: scroll,
                          scrollCacheExtent:
                              const ScrollCacheExtent.pixels(240),
                          keyboardDismissBehavior:
                              ScrollViewKeyboardDismissBehavior.onDrag,
                          slivers: [
                            if (kind == 'portrait')
                              _SpeakerWall(portraits: portraits)
                            else
                              for (final (i, group) in groups.indexed)
                                ..._group(
                                  theme,
                                  i,
                                  group,
                                  open: _open(group, folded),
                                  all: gallery.shots(kind),
                                  titles: gallery.search.artTitles,
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
                                  style: theme.text(
                                    12,
                                    color: theme.textMuted,
                                  ),
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

  /// A collection: its place in the order the stories came out, its name and
  /// how many pictures; under it, when open, the pictures.
  List<Widget> _group(
    AppThemeTokens theme,
    int index,
    GalleryArtGroup group, {
    required bool open,
    required List<CollectionArtShot> all,
    required Map<String, String> titles,
  }) =>
      [
        SliverToBoxAdapter(
          child: Semantics(
            button: true,
            expanded: open,
            child: FoldBlock(
              headKey: ValueKey('gallery-group-$kind-${group.id}'),
              open: open,
              onTap: () => setState(() {
                final key = (kind, group.id);
                if (!turned.remove(key)) turned.add(key);
              }),
              head: Container(
                constraints: const BoxConstraints(minHeight: 56),
                padding: const EdgeInsets.symmetric(horizontal: _gutter),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: theme.divider)),
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 34,
                      child: Text(
                        (index + 1).toString().padLeft(2, '0'),
                        style: theme.field(color: theme.textMuted),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        group.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.heading(15),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text('${group.shots.length}', style: theme.field()),
                    const SizedBox(width: 4),
                    AnimatedRotation(
                      turns: open ? 0 : -0.25,
                      duration: Motion.of(context, Motion.wipe),
                      curve: Motion.mech,
                      child: Icon(
                        Icons.expand_more_sharp,
                        size: 22,
                        color: open ? theme.textPrimary : theme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (open)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(_gutter, 12, _gutter, 20),
            sliver: SliverLayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.crossAxisExtent;
                final columns = (width / 200).floor().clamp(2, 6);
                final tile = (width - _gap * (columns - 1)) / columns;
                return SliverGrid.builder(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: _gap,
                    mainAxisExtent: tile * 9 / 16 + 26,
                  ),
                  itemCount: group.shots.length,
                  itemBuilder: (context, i) {
                    final art = group.shots[i];
                    final title = titles[art.shot.image];
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: ArtThumbnail(
                            art: art,
                            onTap: () => _openShot(art, all),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          title == null || title.isEmpty
                              ? art.storyTitle
                              : title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.ui(12, color: theme.textSecondary),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
      ];
}

/// Everyone who spoke with a portrait, one figure each, most lines first.
class _SpeakerWall extends StatelessWidget {
  const _SpeakerWall({required this.portraits});
  final List<GalleryPortrait> portraits;

  @override
  Widget build(BuildContext context) => SliverPadding(
        padding: const EdgeInsets.fromLTRB(_gutter, 12, _gutter, 0),
        sliver: SliverGrid.builder(
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 132,
            mainAxisExtent: 196,
            mainAxisSpacing: _gap,
            crossAxisSpacing: _gap,
          ),
          itemCount: portraits.length,
          itemBuilder: (context, i) => _SpeakerTile(portrait: portraits[i]),
        ),
      );
}

class _SpeakerTile extends ConsumerWidget {
  const _SpeakerTile({required this.portrait});
  final GalleryPortrait portrait;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    final count = context.t.portraitLines(portrait.lines);
    return Semantics(
      button: true,
      label: '${portrait.speaker} $count',
      excludeSemantics: true,
      child: PressBuilder(
        builder: (context, down) => GestureDetector(
          key: ValueKey('gallery-portrait-${portrait.speaker}'),
          behavior: HitTestBehavior.opaque,
          onTap: withHaptic(
            () => showPortraitSheet(
              context,
              speaker: portrait.speaker,
              origin: PortraitOrigin.materials,
            ),
          ),
          child: Material(
            color: down
                ? pressTint(theme.cardSurface, theme.textPrimary)
                : theme.cardSurface,
            animationDuration: Motion.of(context, Motion.press),
            shape: CutBorder.br(10, side: BorderSide(color: theme.cardBorder)),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(6, 8, 6, 0),
                    child: PortraitImage(
                      sprite: portrait.sprite,
                      transparent: true,
                    ),
                  ),
                ),
                Container(
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: theme.cardBorder)),
                  ),
                  padding: const EdgeInsets.fromLTRB(8, 6, 14, 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        portrait.speaker,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.heading(14),
                      ),
                      Text(
                        count,
                        maxLines: 1,
                        style: theme.field(size: 12),
                      ),
                    ],
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
