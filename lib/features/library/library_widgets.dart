import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/library/library_labels.dart';
import '../../core/library/library_queries.dart';
import '../../core/userdata/user_data_store.dart';
import '../../shared/l10n/l10n.dart';
import '../../shared/providers/theme_provider.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/smooth_page_route.dart';
import '../ai/story_reader_page.dart';

/// Opens a story in the reader. [resume] continues where the reader left
/// off (the history entry), otherwise the story opens at the top.
void openStory(BuildContext context, String storyId, {ReadingEntry? resume}) {
  Navigator.of(context).push(
    smoothPageRoute<void>(
      builder: (_) => StoryReaderPage(
        storyId: storyId,
        resumeLine: resume?.lineIndex,
        snippet: resume?.snippet,
      ),
    ),
  );
}

/// A pushed library page: the app's usual secondary-page frame (transparent
/// body over the backdrop, a quiet app bar), as the conversation history.
class LibraryScaffold extends ConsumerWidget {
  const LibraryScaffold({
    super.key,
    required this.title,
    required this.body,
    this.actions = const [],
    this.bottom,
  });

  final String title;
  final Widget body;
  final List<Widget> actions;
  final PreferredSizeWidget? bottom;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: theme.bgSecondary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleSpacing: 0,
        title: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.titleFont.copyWith(fontSize: 18),
        ),
        actions: actions,
        bottom: bottom,
      ),
      body: body,
    );
  }
}

/// A centred message with an icon: empty lists, a missing knowledge base.
class LibraryMessage extends ConsumerWidget {
  const LibraryMessage({
    super.key,
    required this.icon,
    required this.title,
    this.description,
  });

  final IconData icon;
  final String title;
  final String? description;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 52,
              color: theme.textSecondary.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.titleFont.copyWith(fontSize: 17),
            ),
            if (description != null) ...[
              const SizedBox(height: 8),
              Text(
                description!,
                textAlign: TextAlign.center,
                style: theme.bodyFont.copyWith(
                  color: theme.textSecondary,
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A small rounded label in the accent colour (type, group, count).
class AccentPill extends ConsumerWidget {
  const AccentPill(this.text, {super.key, this.muted = false});

  final String text;

  /// Neutral instead of accent: for secondary facts.
  final bool muted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: muted
            ? theme.textSecondary.withValues(alpha: 0.12)
            : theme.accentPrimary.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: theme.bodyFont.copyWith(
          color: muted ? theme.textSecondary : theme.accentText,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          height: 1.3,
        ),
      ),
    );
  }
}

/// A thin reading-progress line.
class ProgressLine extends ConsumerWidget {
  const ProgressLine(this.value, {super.key});

  final double value;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: LinearProgressIndicator(
        value: value.clamp(0.0, 1.0),
        minHeight: 3,
        backgroundColor: theme.divider,
        valueColor: AlwaysStoppedAnimation(theme.accentPrimary),
      ),
    );
  }
}

/// A list row in the app's list style: icon, title, up to two lines below,
/// a trailing widget. Rows are separated with [rowDivider].
class LibraryRow extends ConsumerWidget {
  const LibraryRow({
    super.key,
    required this.title,
    this.leading,
    this.subtitle,
    this.trailing,
    this.titlePrefix,
    this.onTap,
    this.progress,
    this.subtitleLines = 2,
  });

  final String title;
  final Widget? leading;
  final String? subtitle;
  final Widget? trailing;

  /// Shown before the title in the accent colour (a stage code).
  final String? titlePrefix;
  final VoidCallback? onTap;

  /// 0..1 reading progress drawn under the text, or null.
  final double? progress;
  final int subtitleLines;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (leading != null) ...[leading!, const SizedBox(width: 14)],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text.rich(
                    TextSpan(
                      children: [
                        if (titlePrefix != null)
                          TextSpan(
                            text: '$titlePrefix  ',
                            style: TextStyle(
                              color: theme.accentText,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        TextSpan(text: title),
                      ],
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.titleFont.copyWith(fontSize: 15, height: 1.3),
                  ),
                  if (subtitle != null && subtitle!.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      subtitle!,
                      maxLines: subtitleLines,
                      overflow: TextOverflow.ellipsis,
                      style: theme.bodyFont.copyWith(
                        color: theme.textSecondary,
                        fontSize: 12,
                        height: 1.45,
                      ),
                    ),
                  ],
                  if (progress != null) ...[
                    const SizedBox(height: 8),
                    ProgressLine(progress!),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 10), trailing!],
          ],
        ),
      ),
    );
  }
}

Widget rowDivider(AppThemeTokens theme) =>
    Divider(height: 1, indent: 16, endIndent: 16, color: theme.divider);

/// The small trailing mark of a story row: a check when finished, the
/// percent while reading, a chevron otherwise.
Widget readMark(
  BuildContext context,
  AppThemeTokens theme,
  ReadingEntry? read,
) {
  if (read != null && read.finished) {
    return Tooltip(
      message: context.t.libraryFinished,
      child: Icon(Icons.check_circle_rounded, color: theme.accentText, size: 20),
    );
  }
  final progress = read?.progress;
  if (progress != null && progress > 0) {
    return AccentPill('${(progress * 100).round()}%');
  }
  return Icon(Icons.chevron_right_rounded, color: theme.textMuted, size: 22);
}

/// A story row (collection page, search): code, name, group, synopsis and
/// the reader's progress.
class StoryRow extends ConsumerWidget {
  const StoryRow({super.key, required this.story, this.read});

  final LibraryEntry story;
  final ReadingEntry? read;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    final id = story.rawId;
    return LibraryRow(
      key: ValueKey('story-row-${story.id}'),
      titlePrefix: story.code,
      title: [story.name, if (story.group != null) '· ${story.group}']
          .where((s) => s.isNotEmpty)
          .join(' '),
      subtitle: story.synopsis,
      progress: read?.progress != null && !(read?.finished ?? false)
          ? read!.progress
          : null,
      trailing: readMark(context, theme, read),
      onTap: id == null ? null : () => openStory(context, id, resume: read),
    );
  }
}

/// A row of a non-story entry.
class EntryRow extends ConsumerWidget {
  const EntryRow({super.key, required this.entry, required this.onTap});

  final LibraryEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    final context2 = [
      entryTypeName(entry.type),
      if (entry.collectionName != null) entry.collectionName!,
    ].join(' · ');
    return LibraryRow(
      key: ValueKey('entry-row-${entry.id}'),
      titlePrefix: entry.code,
      title: entry.name.isEmpty ? entry.id : entry.name,
      subtitle: context2,
      subtitleLines: 1,
      trailing: Icon(Icons.chevron_right_rounded, color: theme.textMuted, size: 22),
      onTap: onTap,
    );
  }
}

/// The filter box on top of long lists.
class FilterField extends ConsumerWidget {
  const FilterField({
    super.key,
    required this.hint,
    required this.onChanged,
    this.controller,
    this.autofocus = false,
  });

  final String hint;
  final ValueChanged<String> onChanged;
  final TextEditingController? controller;
  final bool autofocus;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: TextField(
        controller: controller,
        autofocus: autofocus,
        onChanged: onChanged,
        textInputAction: TextInputAction.search,
        style: theme.bodyFont.copyWith(fontSize: 14),
        decoration: InputDecoration(
          isDense: true,
          hintText: hint,
          hintStyle: theme.bodyFont.copyWith(
            color: theme.textMuted,
            fontSize: 14,
          ),
          prefixIcon: Icon(Icons.search_rounded, color: theme.textMuted),
          filled: true,
          fillColor: theme.cardSurface,
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: theme.cardBorder),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: theme.cardBorder),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: theme.accentText),
          ),
        ),
      ),
    );
  }
}
