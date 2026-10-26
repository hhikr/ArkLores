import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/gamedata/build/portrait_names.dart';
import '../../core/library/portrait_provider.dart';
import '../../shared/l10n/l10n.dart';
import '../../shared/providers/theme_provider.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/ef_widgets.dart';
import '../../shared/widgets/portrait_image.dart';
import '../../shared/widgets/smooth_page_route.dart';
import 'entry_page.dart';
import 'portrait_speakers_page.dart';
import 'speaker_portraits_page.dart';

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
  final target = await showAppSheet<WidgetBuilder>(
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
  if (target != null && context.mounted) {
    await pushPortraitPage(context, origin, target);
  }
}

class PortraitSheet extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    final t = context.t;
    final names = ref.watch(speakerPortraitsProvider(speaker));
    final name = names.valueOrNull;
    final shown = fromLine ? sprite : name?.topSprite;
    final parsed = shown == null ? null : SpriteName.parse(shown);
    final group =
        parsed == null ? null : ref.watch(portraitGroupProvider(parsed.group));
    final data = group?.valueOrNull;
    void open(WidgetBuilder builder) => Navigator.of(context).pop(builder);
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
          Text(speaker, style: theme.heading(22)),
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
                child: PortraitImage(
                  sprite: shown,
                  fallbackSprite: data?.topSprite,
                ),
              ),
            ),
          const SizedBox(height: 12),
          if (names.isLoading || (group?.isLoading ?? false))
            const SizedBox(height: 20)
          else
            FactsRow([
              if (name != null) t.portraitLines(name.lines),
              if (data != null) t.portraitSprites(data.sprites),
              if (fromLine && parsed != null)
                t.portraitFaceBody(parsed.face, parsed.body),
            ]),
          const SizedBox(height: 12),
          if (data != null)
            ActionRow(
              label: t.portraitGroupSpeakers,
              meta: '${data.speakers.length}',
              onTap: () => open(
                (_) =>
                    PortraitSpeakersPage(groupId: data.groupId, origin: origin),
              ),
            ),
          if (name != null)
            ActionRow(
              label: t.portraitSpeakerGroups(speaker),
              meta: '${name.groups.length}',
              onTap: () => open(
                (_) => SpeakerPortraitsPage(speaker: speaker, origin: origin),
              ),
            ),
          if (data?.operatorEntryId != null)
            ActionRow(
              label: t.portraitOperator,
              onTap: () =>
                  open((_) => EntryPage(entryId: data!.operatorEntryId!)),
            ),
          const SizedBox(height: 12),
          Text(t.portraitPackCredit,
              style: theme.text(12, color: theme.textMuted),),
        ],
      ),
    );
  }
}
