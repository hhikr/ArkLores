import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/gamedata/build/text_harvest.dart' show cleanRichText;
import '../../core/library/library_labels.dart';
import '../../core/library/library_queries.dart';
import '../../core/library/placeholders.dart';
import '../../core/userdata/library_ref.dart';
import '../../core/userdata/user_data_store.dart';
import '../../shared/l10n/l10n.dart';
import '../../shared/providers/settings_provider.dart';
import '../../shared/providers/theme_provider.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/floating_bar.dart';
import '../../shared/widgets/press_feedback.dart';
import '../../shared/widgets/smooth_page_route.dart';
import '../ai/story_labels_provider.dart';
import '../ai/story_reader_page.dart';
import 'reading_text.dart' show readingStyle;

/// Opens a story in the reader. [resume] continues where the reader left
/// off (the history entry), otherwise the story opens at the top. A story
/// whose pass reached the end opens at the top too: that is a new read.
void openStory(BuildContext context, String storyId, {ReadingEntry? resume}) {
  if (resume != null && resume.finished) resume = null;
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

/// Opens a story in the reader at lines [start]–[end], marked (a search hit).
void openStoryAt(BuildContext context, String storyId, int start, int end) {
  Navigator.of(context).push(
    smoothPageRoute<void>(
      builder: (_) => StoryReaderPage(
        storyId: storyId,
        highlightStart: start,
        highlightEnd: end,
      ),
    ),
  );
}

/// The title a reading-history row shows: the story's name in the installed
/// knowledge base now (names change between builds), the title stored when it
/// was opened until that is known.
String readingTitle(WidgetRef ref, ReadingEntry entry) {
  final item = LibraryRef.tryParse(entry.ref);
  if (item == null || item.kind != LibraryRefKind.story) return entry.title;
  return ref.watch(storyLabelProvider(item.id)).valueOrNull ?? entry.title;
}

/// A pushed library page: floating docks over the backdrop (back, title,
/// actions; [FloatingScaffold]). [scrollUnder] when the body is one list
/// that pads itself with `floatingPadding`.
class LibraryScaffold extends StatelessWidget {
  const LibraryScaffold({
    super.key,
    required this.title,
    required this.body,
    this.actions = const [],
    this.scrollUnder = false,
  });

  final String title;
  final Widget body;
  final List<Widget> actions;
  final bool scrollUnder;

  @override
  Widget build(BuildContext context) => FloatingScaffold(
        title: title,
        actions: actions,
        scrollUnder: scrollUnder,
        body: body,
      );
}
/// A centred message with an icon: empty lists, a missing knowledge base.
class LibraryMessage extends ConsumerWidget {
  const LibraryMessage({
    super.key,
    required this.icon,
    required this.title,
    this.description,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? description;

  /// A button below the message.
  final Widget? action;

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
            if (action != null) ...[
              const SizedBox(height: 12),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

/// A small square tag in the accent colour (type, group, count).
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
        borderRadius: BorderRadius.zero,
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
      borderRadius: BorderRadius.zero,
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
    return PressFeedback(
      enabled: onTap != null,
      pressedScale: 0.985,
      child: InkWell(
      onTap: withHaptic(onTap),
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
      ),
    );
  }
}

Widget rowDivider(AppThemeTokens theme) =>
    Divider(height: 1, indent: 16, endIndent: 16, color: theme.divider);

/// How the count of read-throughs is written in a small badge: exact up to
/// 999, "999+" beyond, so it never outgrows its place.
String readTimesText(int times) => times > 999 ? '999+' : '$times';

/// The check that says a story was read through, with the number of times
/// from the second on ("✓ ×12"); the tooltip has the full count.
class ReadTimesBadge extends ConsumerWidget {
  const ReadTimesBadge(this.times, {super.key});

  final int times;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    return Tooltip(
      message: context.t.libraryReadTimes(times),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 64),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle_sharp, color: theme.accentText, size: 20),
              if (times > 1) ...[
                const SizedBox(width: 2),
                Text(
                  '×${readTimesText(times)}',
                  style: theme.bodyFont.copyWith(
                    color: theme.accentText,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The small trailing mark of a story row: the percent of the pass in
/// progress, the check with its count once the story was read through
/// (both while a later pass is under way), a chevron otherwise.
Widget readMark(
  BuildContext context,
  AppThemeTokens theme,
  ReadingEntry? read,
) {
  final times = read?.completedCount ?? 0;
  final progress = read?.progress;
  final reading =
      read != null && !read.finished && progress != null && progress > 0;
  final pill = reading ? AccentPill('${(progress * 100).round()}%') : null;
  final badge = times > 0 ? ReadTimesBadge(times) : null;
  if (pill != null && badge != null) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [pill, const SizedBox(width: 6), badge],
    );
  }
  return pill ??
      badge ??
      Icon(Icons.chevron_right_sharp, color: theme.textMuted, size: 22);
}
/// A story row (collection page, search): code, name, group, synopsis and
/// the reader's progress.
class StoryRow extends ConsumerWidget {
  const StoryRow({
    super.key,
    required this.story,
    this.read,
    this.showGroup = true,
  });

  final LibraryEntry story;
  final ReadingEntry? read;

  /// False under a heading that is the group already.
  final bool showGroup;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    final id = story.rawId;
    return LibraryRow(
      key: ValueKey('story-row-${story.id}'),
      titlePrefix: story.code,
      title: [
        story.name,
        if (showGroup &&
            story.group != null &&
            !story.name.contains(story.group!))
          '· ${story.group}',
      ]
          .where((s) => s.isNotEmpty)
          .join(' '),
      subtitle: story.synopsis == null
          ? null
          : withPlaceholders(story.synopsis!, ref.watch(nicknameProvider)),
      progress: read?.progress != null && !(read?.finished ?? false)
          ? read!.progress
          : null,
      trailing: readMark(context, theme, read),
      onTap: id == null ? null : () => openStory(context, id, resume: read),
    );
  }
}

/// A profile text (a character-table document) rendered as markdown: its
/// `##` headings are headings, every line of the source its own line. The
/// game's rich-text tags are removed first.
class MarkdownText extends ConsumerWidget {
  const MarkdownText(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    final cleaned = cleanRichText(withPlaceholders(text, ref.watch(nicknameProvider)))
        .split('\n')
        .map((l) => l.trimRight())
        .join('  \n');
    return MarkdownBody(
      data: cleaned,
      selectable: true,
      styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
        p: readingStyle(theme, size: 15),
        h1: theme.titleFont.copyWith(color: theme.textPrimary, fontSize: 18),
        h2: theme.titleFont.copyWith(
          color: theme.accentText,
          fontSize: 15,
          height: 2,
        ),
        h3: theme.titleFont.copyWith(color: theme.textPrimary, fontSize: 14),
        strong: theme.bodyFont.copyWith(
          color: theme.textPrimary,
          fontWeight: FontWeight.w700,
        ),
        listBullet: theme.bodyFont.copyWith(color: theme.textPrimary),
        horizontalRuleDecoration: BoxDecoration(
          border: Border(top: BorderSide(color: theme.divider)),
        ),
      ),
    );
  }
}

/// An event's text: the sections written as markdown, except `## 选项`, which
/// is a list (option, the text after choosing it, the options that follow;
/// see `eventOutline`) shown as folding rows, one level inside the other.
class EventText extends ConsumerWidget {
  const EventText(this.text, {super.key});

  final String text;

  static const optionsHeading = '选项';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sections = <({String? heading, List<String> lines})>[];
    for (final line in text.split('\n')) {
      if (line.startsWith('## ')) {
        sections.add((heading: line.substring(3).trim(), lines: <String>[]));
      } else {
        if (sections.isEmpty) sections.add((heading: null, lines: <String>[]));
        sections.last.lines.add(line);
      }
    }
    final theme = ref.watch(themeProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final s in sections)
          if (s.heading == optionsHeading) ...[
            Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 2),
              child: Text(
                optionsHeading,
                style: theme.titleFont.copyWith(
                  color: theme.accentText,
                  fontSize: 15,
                  height: 2,
                ),
              ),
            ),
            for (final n in parseEventOptions(s.lines))
              _OptionNode(n, theme: theme),
          ] else
            MarkdownText([
              if (s.heading != null) '## ${s.heading}',
              ...s.lines,
            ].join('\n'),),
      ],
    );
  }
}

/// One option of an event with what follows choosing it.
class EventOption {
  EventOption(this.title, this.depth);

  final String title;
  final int depth;
  final List<String> body = [];
  final List<EventOption> children = [];
}

/// The `## 选项` lines as a forest: `- **option**：text` (one dash more per
/// level), the lines after it being what is said after choosing it.
List<EventOption> parseEventOptions(List<String> lines) {
  final roots = <EventOption>[];
  final stack = <EventOption>[];
  final bullet = RegExp(r'^(-+) (\*\*.*)$');
  for (final raw in lines) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    final m = bullet.firstMatch(line);
    if (m != null) {
      final node = EventOption(m.group(2)!, m.group(1)!.length - 1);
      while (stack.isNotEmpty && stack.last.depth >= node.depth) {
        stack.removeLast();
      }
      (stack.isEmpty ? roots : stack.last.children).add(node);
      stack.add(node);
    } else if (stack.isNotEmpty) {
      stack.last.body.add(line);
    }
  }
  return roots;
}

class _OptionNode extends StatelessWidget {
  const _OptionNode(this.node, {required this.theme});

  final EventOption node;
  final AppThemeTokens theme;

  @override
  Widget build(BuildContext context) {
    final m = RegExp(r'^\*\*(.*?)\*\*(?:：(.*))?$').firstMatch(node.title);
    final title = m?.group(1) ?? node.title;
    final said = m?.group(2);
    final heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.titleFont.copyWith(fontSize: 14)),
        if (said != null && said.isNotEmpty)
          Text(
            said,
            style: theme.bodyFont.copyWith(
              color: theme.textSecondary,
              fontSize: 12,
            ),
          ),
      ],
    );
    if (node.body.isEmpty && node.children.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
        child: heading,
      );
    }
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        key: ValueKey('event-option-${node.depth}-${node.title}'),
        shape: const Border(),
        collapsedShape: const Border(),
        tilePadding: const EdgeInsets.symmetric(horizontal: 16),
        childrenPadding: const EdgeInsets.only(left: 14),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        iconColor: theme.accentText,
        collapsedIconColor: theme.textMuted,
        title: heading,
        children: [
          if (node.body.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: SelectableText(
                node.body.join('\n'),
                style: readingStyle(theme, size: 14.5),
              ),
            ),
          for (final c in node.children) _OptionNode(c, theme: theme),
        ],
      ),
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
    final numbered = numberedTypes.contains(entry.type);
    final context2 = [
      entryTypeName(entry.type),
      if (numbered && codeCaption(entry) != null) codeCaption(entry)!,
      if (entry.collectionName != null) entry.collectionName!,
    ].join(' · ');
    return LibraryRow(
      key: ValueKey('entry-row-${entry.id}'),
      titlePrefix: numbered ? null : entry.code,
      title: entry.name.isEmpty ? entry.id : entry.name,
      subtitle: context2,
      subtitleLines: 1,
      trailing: Icon(Icons.chevron_right_sharp, color: theme.textMuted, size: 22),
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
          prefixIcon: Icon(Icons.search_sharp, color: theme.textMuted),
          filled: true,
          fillColor: theme.cardSurface,
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.zero,
            borderSide: BorderSide(color: theme.cardBorder),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.zero,
            borderSide: BorderSide(color: theme.cardBorder),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.zero,
            borderSide: BorderSide(color: theme.accentText),
          ),
        ),
      ),
    );
  }
}
