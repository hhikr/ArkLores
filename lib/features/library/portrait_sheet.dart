import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/gamedata/build/portrait_names.dart';
import '../../core/library/portrait_provider.dart';
import '../../shared/l10n/l10n.dart';
import '../../shared/providers/theme_provider.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/theme/cut_border.dart';
import '../../shared/widgets/ef_widgets.dart';
import '../../shared/widgets/portrait_image.dart';
import '../../shared/widgets/press_feedback.dart';
import '../../shared/widgets/smooth_page_route.dart';
import 'entry_page.dart';
import 'portrait_speakers_page.dart';
import 'portrait_stories_page.dart';
import 'speaker_portraits_page.dart';
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

/// The card of one portrait opened from a list of portraits: nothing there
/// says whose it is (a speaker's list holds others' portraits too), so it
/// has no name; who uses it is one tap away. [listSpeaker], the speaker
/// whose list it came from, leads to their stories with it.
Future<void> showPortraitGroupSheet(
  BuildContext context, {
  required String sprite,
  String? listSpeaker,
  required PortraitOrigin origin,
}) async {
  await showAppSheet<void>(
    context,
    (_) => PlainSheet(
      child: PortraitSheet(
        speaker: null,
        sprite: sprite,
        fromLine: true,
        listSpeaker: listSpeaker,
        origin: origin,
      ),
    ),
  );
}

class PortraitSheet extends ConsumerStatefulWidget {
  const PortraitSheet({
    super.key,
    required this.speaker,
    this.sprite,
    this.fromLine = false,
    required this.origin,
    this.spriteLoading = false,
    this.listSpeaker,
  });

  /// Null: the card of a portrait, not of a name ([showPortraitGroupSheet]).
  final String? speaker;
  final String? listSpeaker;
  final String? sprite;
  final bool fromLine;
  final PortraitOrigin origin;
  final bool spriteLoading;

  @override
  ConsumerState<PortraitSheet> createState() => _PortraitSheetState();
}

class _PortraitSheetState extends ConsumerState<PortraitSheet> {
  String? selected;
  String? get speaker => widget.speaker;
  String? get sprite => widget.sprite;
  bool get fromLine => widget.fromLine;
  PortraitOrigin get origin => widget.origin;
  bool get spriteLoading => widget.spriteLoading;

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider);
    final t = context.t;
    final speaker = this.speaker;
    final names =
        speaker == null ? null : ref.watch(speakerPortraitsProvider(speaker));
    final name = names?.valueOrNull;
    final listSpeaker = widget.listSpeaker;
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
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        20 + MediaQuery.paddingOf(context).bottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Eyebrow(t.portraitEyebrow),
          if (speaker != null) Text(speaker, style: theme.heading(22)),
          const SizedBox(height: 12),
          if (spriteLoading)
            const SizedBox(height: 48)
          else if (fromLine && sprite == null)
            Text(
              t.portraitNoSprite,
              style: theme.text(14, color: theme.textSecondary),
            )
          else if (shown != null)
            ColoredBox(
              color: theme.cardSurface,
              child: SizedBox(
                height: math.min(MediaQuery.sizeOf(context).height * 0.46, 420),
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
                      onPageChanged: (index) =>
                          setState(() => selected = items[index]),
                    );
                  },
                  child: PortraitImage(
                    sprite: shown,
                    fallbackSprite: data?.topSprite,
                  ),
                ),
              ),
            ),
          if (variants.isNotEmpty)
            _PortraitVariants(
              key: ValueKey(parsed!.group),
              sprites: variants,
              selected: shown!,
              onSelect: (item) => setState(() => selected = item),
            ),
          const SizedBox(height: 12),
          if ((names?.isLoading ?? false) || (group?.isLoading ?? false))
            const SizedBox(height: 20)
          else
            FactsRow([
              if (name != null) t.portraitLines(name.lines),
              if (speaker == null && data != null) t.portraitLines(data.lines),
              if (data != null) t.portraitSprites(data.sprites),
              if (parsed != null) t.portraitFaceBody(parsed.face, parsed.body),
            ]),
          const SizedBox(height: 12),
          if (data != null)
            ActionRow(
              label:
                  speaker == null ? t.portraitWhoUses : t.portraitGroupSpeakers,
              meta: '${data.speakers.length}',
              onTap: () => open(
                (_) =>
                    PortraitSpeakersPage(groupId: data.groupId, origin: origin),
              ),
            ),
          if (name != null && speaker != null)
            ActionRow(
              label: t.portraitSpeakerGroups,
              meta: '${name.groups.length}',
              onTap: () => open(
                (_) => SpeakerPortraitsPage(speaker: speaker, origin: origin),
              ),
            ),
          if (speaker == null && listSpeaker != null && data != null)
            ActionRow(
              key: const ValueKey('portrait-stories-of-list-speaker'),
              label: t.portraitStoriesWith(listSpeaker),
              onTap: () => open(
                (_) => PortraitStoriesPage(
                  speaker: listSpeaker,
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
    );
  }
}

class _PortraitVariants extends ConsumerStatefulWidget {
  const _PortraitVariants({
    super.key,
    required this.sprites,
    required this.selected,
    required this.onSelect,
  });
  final List<String> sprites;
  final String selected;
  final ValueChanged<String> onSelect;
  @override
  ConsumerState<_PortraitVariants> createState() => _PortraitVariantsState();
}

class _PortraitVariantsState extends ConsumerState<_PortraitVariants> {
  late final ScrollController controller = ScrollController(
    initialScrollOffset:
        math.max(0, widget.sprites.indexOf(widget.selected)) * 80.0,
  );
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
        itemExtent: 80,
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
