import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/gamedata/story_catalog.dart';
import '../../core/library/portrait_provider.dart';
import '../../shared/l10n/l10n.dart';
import '../../shared/providers/theme_provider.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/ef_widgets.dart';
import '../../shared/widgets/page_frame.dart';
import '../ai/story_reader_page.dart';
import 'library_widgets.dart';
import 'portrait_sheet.dart';

class PortraitStoriesPage extends ConsumerWidget {
  const PortraitStoriesPage({
    super.key,
    required this.speaker,
    required this.groupId,
    required this.origin,
  });
  final String speaker, groupId;
  final PortraitOrigin origin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    final result = ref
        .watch(portraitStoriesProvider((speaker: speaker, groupId: groupId)));
    final rows = result.valueOrNull ?? [];
    return PageScaffold(
      title: context.t.portraitStoryTitle(speaker),
      body: result.isLoading
          ? const LoadingView()
          : rows.isEmpty
              ? EmptyState(text: context.t.portraitNoStories)
              : ListView.builder(
                  padding: pagePadding(
                    context,
                    const EdgeInsets.all(16),
                    topBar: false,
                  ),
                  itemCount: rows.length,
                  itemBuilder: (context, index) {
                    final row = rows[index];
                    return LibraryRow(
                      title:
                          row.catalog?.label ?? fallbackStoryLabel(row.storyId),
                      subtitle: row.catalog?.collectionLabel,
                      trailing: Text(context.t.portraitLines(row.lines), style: theme.field()),
                      onTap: () => pushPortraitPage(
                        context,
                        origin,
                        (_) => StoryReaderPage(
                          storyId: row.storyId,
                          highlightStart: row.firstLine,
                          highlightEnd: row.firstLine,
                          portraitOrigin: origin,
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
