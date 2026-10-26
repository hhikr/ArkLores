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
import 'portrait_stories_page.dart';

/// Who speaks on one portrait, most lines first. Speakers who pass by
/// ([GroupSpeaker.passing]: a line or two here, their own portrait
/// elsewhere) fold under one row at the bottom, never the first speaker.
class PortraitSpeakersPage extends ConsumerWidget {
  const PortraitSpeakersPage({
    super.key,
    required this.groupId,
    required this.origin,
  });
  final String groupId;
  final PortraitOrigin origin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    final result = ref.watch(portraitGroupProvider(groupId));
    final group = result.valueOrNull;
    final t = context.t;
    if (result.isLoading || group == null || group.speakers.isEmpty) {
      return PageScaffold(
        title: t.portraitGroupPageTitle,
        backgroundColor: theme.bgPrimary,
        body: result.isLoading
            ? const LoadingView()
            : EmptyState(text: t.portraitNoSprite),
      );
    }
    final speakers = group.speakers;
    final main = [
      speakers.first,
      ...speakers.skip(1).where((s) => !s.passing),
    ];
    final passing = speakers.skip(1).where((s) => s.passing).toList();
    Widget row(GroupSpeaker s, int number) => _SpeakerRow(
          speaker: s,
          number: number,
          onTap: () => pushPortraitPage(
            context,
            origin,
            (_) => PortraitStoriesPage(
              groupId: groupId,
              speaker: s.speaker,
              origin: origin,
            ),
          ),
        );
    return PageScaffold(
      title: t.portraitGroupPageTitle,
      backgroundColor: theme.bgPrimary,
      body: ListView(
        padding: pagePadding(context, const EdgeInsets.all(16), topBar: false),
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Row(
              children: [
                SizedBox(
                  width: 96,
                  height: 128,
                  child: PortraitImage(sprite: group.topSprite),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FactsRow([t.portraitLines(group.lines)]),
                      const SizedBox(height: 8),
                      FactsRow([t.portraitSpeakerCount(speakers.length)]),
                      const SizedBox(height: 8),
                      FactsRow([t.portraitSprites(group.sprites)]),
                    ],
                  ),
                ),
              ],
            ),
          ),
          for (final (i, s) in main.indexed) row(s, i + 1),
          if (passing.isNotEmpty)
            DecoratedBox(
              key: const ValueKey('portrait-passing-speakers'),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: theme.divider)),
              ),
              child: FoldTile(
                title: Text(
                  t.portraitPassingSpeakers(passing.length),
                  style: theme.text(14, color: theme.textSecondary),
                ),
                children: [
                  for (final (i, s) in passing.indexed)
                    Padding(
                      padding: const EdgeInsets.only(left: 12),
                      child: row(s, main.length + i + 1),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _SpeakerRow extends ConsumerWidget {
  const _SpeakerRow({
    required this.speaker,
    required this.number,
    required this.onTap,
  });
  final GroupSpeaker speaker;
  final int number;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    final t = context.t;
    return PressRow(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 56),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: theme.divider)),
        ),
        child: Row(
          children: [
            Text(
              'No.${number.toString().padLeft(2, '0')}',
              style: theme.field(),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(speaker.speaker, style: theme.heading(16)),
            ),
            const SizedBox(width: 8),
            Text(
              '${t.portraitLines(speaker.lines)} / ${t.portraitStories(speaker.stories)}',
              style: theme.field(),
            ),
          ],
        ),
      ),
    );
  }
}
