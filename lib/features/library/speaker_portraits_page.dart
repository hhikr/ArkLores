import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/library/portrait_provider.dart';
import '../../shared/l10n/l10n.dart';
import '../../shared/providers/theme_provider.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/ef_widgets.dart';
import '../../shared/widgets/page_frame.dart';
import '../../shared/widgets/portrait_image.dart';
import 'portrait_sheet.dart';
import 'portrait_stories_page.dart';

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
    return PageScaffold(
      title: t.portraitSpeakerPageTitle(speaker),
      backgroundColor: theme.bgPrimary,
      body: result.isLoading
          ? const LoadingView()
          : groups.isEmpty
              ? EmptyState(text: t.portraitNoSprite)
              : ListView.builder(
                  padding: pagePadding(
                    context,
                    const EdgeInsets.all(16),
                    topBar: false,
                  ),
                  itemCount: groups.length,
                  itemBuilder: (context, index) {
                    final row = groups[index];
                    return PressRow(
                      onTap: () => pushPortraitPage(
                        context,
                        origin,
                        (_) => PortraitStoriesPage(
                          speaker: speaker,
                          groupId: row.groupId,
                          origin: origin,
                        ),
                      ),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          border: Border(
                            top: BorderSide(color: theme.divider),
                          ),
                        ),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 56,
                              height: 72,
                              child: PortraitImage(sprite: row.topSprite),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${t.portraitLines(row.lines)} / ${t.portraitStories(row.stories)}',
                                    style: theme.field(),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    t.portraitSpeakerCount(row.groupSpeakers),
                                    style: theme.text(
                                      14,
                                      color: theme.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              Icons.chevron_right_sharp,
                              color: theme.textPrimary,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
