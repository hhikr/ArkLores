import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/gamedata/build/portrait_names.dart';
import '../../core/library/portrait_provider.dart';
import '../../core/library/portrait_queries.dart';
import '../../shared/l10n/l10n.dart';
import '../../shared/providers/theme_provider.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/theme/cut_border.dart';
import '../../shared/theme/motion.dart';
import '../../shared/widgets/ef_widgets.dart';
import '../../shared/widgets/portrait_image.dart';
import '../../shared/widgets/press_feedback.dart';
import '../../shared/widgets/smooth_page_route.dart';
import 'entry_page.dart';
import 'portrait_speakers_page.dart';
import 'portrait_stories_page.dart';
import 'story_art_viewer.dart';

enum PortraitOrigin { materials, ask }

Future<void> pushPortraitPage(
  BuildContext context,
  PortraitOrigin origin,
  WidgetBuilder builder,
) async {
  await Navigator.of(context).push(
    smoothPageRoute<void>(
      frosted: origin == PortraitOrigin.materials,
      builder: builder,
    ),
  );
}

/// Opens immediately; queries populate the card while it is visible.
Future<void> showPortraitSheet(
  BuildContext context, {
  required String speaker,
  String? sprite,
  Future<String?>? spriteFuture,
  bool fromLine = false,
  required PortraitOrigin origin,
}) async {
  await showAppSheet<void>(
    context,
    (_) => PlainSheet(
      child: FutureBuilder<String?>(
        future: spriteFuture,
        builder: (_, snapshot) => PortraitSheet(
          speaker: speaker,
          sprite: spriteFuture == null ? sprite : snapshot.data,
          spriteLoading: spriteFuture != null &&
              snapshot.connectionState != ConnectionState.done,
          fromLine: fromLine,
          origin: origin,
        ),
      ),
    ),
  );
}

/// A speaker's card: the figure stays in view at the top; under it every
/// portrait of the speaker, an outfit to a row. Those the speaker only passes
/// by ([passingCount]) fold under one row. What the figure shows decides what
/// the rows at the end are about.
class PortraitSheet extends ConsumerStatefulWidget {
  const PortraitSheet({
    super.key,
    required this.speaker,
    this.sprite,
    this.fromLine = false,
    required this.origin,
    this.spriteLoading = false,
  });

  final String speaker;
  final String? sprite;
  final bool fromLine;
  final PortraitOrigin origin;
  final bool spriteLoading;

  @override
  ConsumerState<PortraitSheet> createState() => _PortraitSheetState();
}

class _PortraitSheetState extends ConsumerState<PortraitSheet> {
  String? selected;
  bool passingOpen = false;
  String get speaker => widget.speaker;
  String? get sprite => widget.sprite;
  bool get fromLine => widget.fromLine;
  PortraitOrigin get origin => widget.origin;
  bool get spriteLoading => widget.spriteLoading;

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider);
    final t = context.t;
    final names = ref.watch(speakerPortraitsProvider(speaker));
    final name = names.valueOrNull;
    final shown = selected ?? (fromLine ? sprite : name?.topSprite);
    final parsed = shown == null ? null : SpriteName.parse(shown);
    final group =
        parsed == null ? null : ref.watch(portraitGroupProvider(parsed.group));
    final data = group?.valueOrNull;
    final variants = parsed == null
        ? const <String>[]
        : ref.watch(portraitSpritesProvider(parsed.group)).valueOrNull ??
            const <String>[];
    // Over the card, which stays: back from the page returns to it.
    void open(WidgetBuilder builder) =>
        pushPortraitPage(context, origin, builder);
    void select(String item) => setState(() => selected = item);

    // The portrait of the line opened from comes first, so its outfits are
    // right under the figure; it stays there while the reader looks around.
    final lead = fromLine && sprite != null
        ? SpriteName.parse(sprite!)?.group
        : null;
    final all = name?.groups ?? const <SpeakerGroup>[];
    final known = all.any((g) => g.groupId == lead);
    final main = <SpeakerGroup>[];
    final passing = <SpeakerGroup>[];
    for (final (i, g) in all.indexed) {
      if (g.groupId == lead) {
        main.insert(0, g);
      } else if (i == 0 || !passingCount(g.lines, g.stories)) {
        main.add(g);
      } else {
        passing.add(g);
      }
    }
    final several = all.length + (lead != null && !known ? 1 : 0) > 1;
    Widget outfits(SpeakerGroup g) => _PortraitOutfits(
          key: ValueKey('portrait-outfits-${g.groupId}'),
          groupId: g.groupId,
          caption: several
              ? '${t.portraitLines(g.lines)} / ${t.portraitStories(g.stories)}'
              : null,
          selected: shown,
          onSelect: select,
        );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Eyebrow(t.portraitEyebrow),
              Text(speaker, style: theme.heading(22)),
              const SizedBox(height: 12),
              if (spriteLoading)
                const SizedBox(height: 48)
              else if (shown != null)
                ColoredBox(
                  color: theme.cardSurface,
                  child: SizedBox(
                    height:
                        math.min(MediaQuery.sizeOf(context).height * 0.36, 340),
                    child: PortraitFullscreenTap(
                      onTap: () {
                        final items = variants.contains(shown)
                            ? variants
                            : [shown, ...variants];
                        openArtViewer(
                          context,
                          pages: [
                            for (final item in items)
                              ArtViewerPage.portrait(
                                sprite: item,
                                speaker: speaker,
                              ),
                          ],
                          initial: items.indexOf(shown),
                          onPageChanged: (index) => select(items[index]),
                        );
                      },
                      child: PortraitImage(
                        sprite: shown,
                        fallbackSprite: data?.topSprite,
                      ),
                    ),
                  ),
                )
              else if (fromLine && sprite == null)
                Text(
                  t.portraitNoSprite,
                  style: theme.text(14, color: theme.textSecondary),
                ),
              const SizedBox(height: 8),
              if (names.isLoading || (group?.isLoading ?? false))
                const SizedBox(height: 20)
              else
                FactsRow([
                  if (name != null) t.portraitLines(name.lines),
                  if (data != null) t.portraitSprites(data.sprites),
                  if (parsed != null)
                    t.portraitFaceBody(parsed.face, parsed.body),
                ]),
              const SizedBox(height: 8),
            ],
          ),
        ),
        Flexible(
          // Lazy: a name many people go by has hundreds of portraits.
          child: ListView(
            shrinkWrap: true,
            scrollCacheExtent: const ScrollCacheExtent.pixels(120),
            padding: EdgeInsets.fromLTRB(
              16,
              0,
              16,
              20 + MediaQuery.paddingOf(context).bottom,
            ),
            children: [
              if (lead != null && !known)
                _PortraitOutfits(
                  key: ValueKey('portrait-outfits-$lead'),
                  groupId: lead,
                  selected: shown,
                  onSelect: select,
                ),
              for (final g in main) outfits(g),
              if (passing.isNotEmpty)
                FoldBlock(
                  headKey: const ValueKey('speaker-passing-portraits'),
                  open: passingOpen,
                  onTap: () => setState(() => passingOpen = !passingOpen),
                  head: Container(
                    constraints: const BoxConstraints(minHeight: 52),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    alignment: Alignment.centerLeft,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t.portraitPassingPortraits(passing.length),
                          style: theme.text(14, color: theme.textSecondary),
                        ),
                        Text(
                          t.portraitPassingHint,
                          style: theme.text(12, color: theme.textMuted),
                        ),
                      ],
                    ),
                  ),
                ),
              if (passingOpen) for (final g in passing) outfits(g),
              const SizedBox(height: 8),
              if (data != null)
                ActionRow(
                  label: t.portraitGroupSpeakers,
                  meta: '${data.speakers.length}',
                  onTap: () => open(
                    (_) => PortraitSpeakersPage(
                      groupId: data.groupId,
                      origin: origin,
                    ),
                  ),
                ),
              if (data != null && all.any((g) => g.groupId == data.groupId))
                ActionRow(
                  key: const ValueKey('portrait-stories-of-speaker'),
                  label: t.portraitStoriesWith(speaker),
                  onTap: () => open(
                    (_) => PortraitStoriesPage(
                      speaker: speaker,
                      groupId: data.groupId,
                      origin: origin,
                    ),
                  ),
                ),
              if (data?.operatorEntryId != null)
                ActionRow(
                  label: t.portraitOperator,
                  onTap: () =>
                      open((_) => EntryPage(entryId: data!.operatorEntryId!)),
                ),
              const SizedBox(height: 12),
              Text(
                t.storyArtCredit,
                style: theme.text(12, color: theme.textMuted),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// One portrait's sprites: a row for each outfit, its expressions side by
/// side. With one outfit the row needs no name.
class _PortraitOutfits extends ConsumerWidget {
  const _PortraitOutfits({
    super.key,
    required this.groupId,
    this.caption,
    required this.selected,
    required this.onSelect,
  });
  final String groupId;
  final String? caption;
  final String? selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    final sprites =
        ref.watch(portraitSpritesProvider(groupId)).valueOrNull ?? const [];
    final outfits = <int, List<String>>{};
    for (final sprite in sprites) {
      final parsed = SpriteName.parse(sprite);
      if (parsed != null) (outfits[parsed.body] ??= []).add(sprite);
    }
    final caption = this.caption;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (caption != null)
          Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.only(top: 8),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: theme.divider)),
            ),
            child: Text(caption, style: theme.field(size: 12)),
          ),
        for (final outfit in outfits.entries) ...[
          if (outfits.length > 1)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                context.t.portraitOutfit(outfit.key),
                style: theme.ui(12, color: theme.textSecondary),
              ),
            ),
          _OutfitRow(
            key: ValueKey('portrait-outfit-$groupId-${outfit.key}'),
            sprites: outfit.value,
            selected: selected,
            onSelect: onSelect,
          ),
        ],
      ],
    );
  }
}

const double _thumbWidth = 80;

class _OutfitRow extends ConsumerStatefulWidget {
  const _OutfitRow({
    super.key,
    required this.sprites,
    required this.selected,
    required this.onSelect,
  });
  final List<String> sprites;
  final String? selected;
  final ValueChanged<String> onSelect;
  @override
  ConsumerState<_OutfitRow> createState() => _OutfitRowState();
}

class _OutfitRowState extends ConsumerState<_OutfitRow> {
  late final ScrollController controller = ScrollController(
    initialScrollOffset:
        math.max(0, widget.sprites.indexOf(widget.selected ?? '')) * _thumbWidth,
  );

  @override
  void didUpdateWidget(_OutfitRow old) {
    super.didUpdateWidget(old);
    // Paged to in the viewer: the row keeps it in sight.
    final at = widget.sprites.indexOf(widget.selected ?? '');
    if (old.selected == widget.selected || at < 0 || !controller.hasClients) {
      return;
    }
    final position = controller.position;
    final left = at * _thumbWidth;
    if (left >= position.pixels &&
        left + _thumbWidth <= position.pixels + position.viewportDimension) {
      return;
    }
    controller.animateTo(
      left.clamp(0.0, position.maxScrollExtent),
      duration: Motion.of(context, Motion.row),
      curve: Motion.snap,
    );
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider);
    return SizedBox(
      height: 104,
      child: ListView.builder(
        controller: controller,
        scrollDirection: Axis.horizontal,
        scrollCacheExtent: const ScrollCacheExtent.pixels(0),
        itemCount: widget.sprites.length,
        itemExtent: _thumbWidth,
        itemBuilder: (context, index) {
          final item = widget.sprites[index];
          final parsed = SpriteName.parse(item)!;
          final current = item == widget.selected;
          // The one shown carries the trace rail on its left; choosing
          // another draws it back up here and down there.
          return Semantics(
            selected: current,
            button: true,
            label: context.t.portraitFaceBody(parsed.face, parsed.body),
            child: Padding(
              padding: const EdgeInsets.only(top: 8, right: 8),
              child: PressBuilder(
                builder: (context, down) => GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: withHaptic(() => widget.onSelect(item)),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      DecoratedBox(
                        decoration: ShapeDecoration(
                          color: down
                              ? pressTint(theme.cardSurface, theme.textPrimary)
                              : theme.cardSurface,
                          shape: CutBorder(
                            bottomRight: 7,
                            side: BorderSide(
                              color: current
                                  ? theme.textSecondary
                                  : theme.cardBorder,
                            ),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(6, 3, 3, 3),
                          child: PortraitImage(sprite: item),
                        ),
                      ),
                      Positioned(
                        left: 0,
                        top: 0,
                        bottom: 0,
                        width: traceRailWidth,
                        child: TraceRail(on: current),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
