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
    return PageScaffold(
      title: t.portraitGroupPageTitle,
      backgroundColor: theme.bgPrimary,
      body: result.isLoading
          ? const LoadingView()
          : group == null || group.speakers.isEmpty
              ? EmptyState(text: t.portraitNoSprite)
              : ListView.builder(
                  padding: pagePadding(
                    context,
                    const EdgeInsets.all(16),
                    topBar: false,
                  ),
                  itemCount: group.speakers.length + 1,
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return Padding(
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
                                  FactsRow([
                                    t.portraitSpeakerCount(
                                      group.speakers.length,
                                    ),
                                  ]),
                                  const SizedBox(height: 8),
                                  FactsRow([t.portraitSprites(group.sprites)]),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    }
                    final row = group.speakers[index - 1];
                    return PressRow(
                      onTap: () => pushPortraitPage(
                        context,
                        origin,
                        (_) => PortraitStoriesPage(
                          groupId: groupId,
                          speaker: row.speaker,
                          origin: origin,
                        ),
                      ),
                      child: Container(
                        constraints: const BoxConstraints(minHeight: 56),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          border: Border(
                            top: BorderSide(color: theme.divider),
                          ),
                        ),
                        child: Row(
                          children: [
                            Text(
                              'No.${index.toString().padLeft(2, '0')}',
                              style: theme.field(),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                row.speaker,
                                style: theme.heading(16),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${t.portraitLines(row.lines)} / ${t.portraitStories(row.stories)}',
                              style: theme.field(),
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
