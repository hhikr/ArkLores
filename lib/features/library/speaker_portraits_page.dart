import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/library/portrait_provider.dart';
import '../../core/library/portrait_queries.dart';
import '../../shared/l10n/l10n.dart';
import '../../shared/providers/theme_provider.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/ef_widgets.dart';
import '../../shared/widgets/page_frame.dart';
import '../../shared/widgets/portrait_image.dart';
import 'portrait_sheet.dart';

/// One speaker's portraits, most lines first. Portraits the speaker only
/// passes by (few lines, not their main one: [passingCount]) fold under one row at
/// the bottom, as on [PortraitSpeakersPage]'s list.
class SpeakerPortraitsPage extends ConsumerWidget {
  const SpeakerPortraitsPage({
    super.key,
    required this.speaker,
    required this.origin,
  });
  final String speaker;
  final PortraitOrigin origin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    final result = ref.watch(speakerPortraitsProvider(speaker));
    final groups = result.valueOrNull?.groups ?? [];
    final t = context.t;
    if (result.isLoading || groups.isEmpty) {
      return PageScaffold(
        title: t.portraitSpeakerPageTitle(speaker),
        backgroundColor: theme.bgPrimary,
        body: result.isLoading
            ? const LoadingView()
            : EmptyState(text: t.portraitNoSprite),
      );
    }
    // The first is the speaker's main portrait: never folded.
    bool passes(SpeakerGroup g) => passingCount(g.lines, g.stories);
    final main = [groups.first, ...groups.skip(1).where((g) => !passes(g))];
    final passing = groups.skip(1).where(passes).toList();
    Widget row(SpeakerGroup g) => _PortraitRow(
          group: g,
          // The card of that portrait (not the stories): its variants, who
          // uses it, and this speaker's stories with it from there.
          onTap: () => showPortraitGroupSheet(
            context,
            sprite: g.topSprite,
            listSpeaker: speaker,
            origin: origin,
          ),
        );
    return PageScaffold(
      title: t.portraitSpeakerPageTitle(speaker),
      backgroundColor: theme.bgPrimary,
      body: ListView(
        padding: pagePadding(context, const EdgeInsets.all(16), topBar: false),
        children: [
          for (final g in main) row(g),
          if (passing.isNotEmpty)
            DecoratedBox(
              key: const ValueKey('speaker-passing-portraits'),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: theme.divider)),
              ),
              child: FoldTile(
                title: Text(
                  t.portraitPassingPortraits(passing.length),
                  style: theme.text(14, color: theme.textSecondary),
                ),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    t.portraitPassingHint,
                    style: theme.text(12, color: theme.textMuted),
                  ),
                ),
                children: [
                  for (final g in passing)
                    Padding(
                      padding: const EdgeInsets.only(left: 12),
                      child: row(g),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _PortraitRow extends ConsumerWidget {
  const _PortraitRow({required this.group, required this.onTap});
  final SpeakerGroup group;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    final t = context.t;
    return PressRow(
      key: ValueKey('speaker-portrait-${group.groupId}'),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: theme.divider)),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 56,
              height: 72,
              child: PortraitImage(sprite: group.topSprite),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${t.portraitLines(group.lines)} / ${t.portraitStories(group.stories)}',
                    style: theme.field(),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    t.portraitSpeakerCount(group.groupSpeakers),
                    style: theme.text(14, color: theme.textSecondary),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_sharp, color: theme.textPrimary),
          ],
        ),
      ),
    );
  }
}
