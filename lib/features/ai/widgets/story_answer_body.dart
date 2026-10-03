import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/gamedata/story_catalog.dart'
    show StoryCatalogEntry, fallbackStoryLabel;
import '../../../shared/l10n/l10n.dart';
import '../../../shared/providers/theme_provider.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../shared/widgets/smooth_page_route.dart';
import '../investigation_ui.dart';
import '../story_labels_provider.dart';
import '../story_reader_page.dart';

/// Opens the whole story at [range] (R17b).
void openStoryReader(BuildContext context, String storyId, CitedRange range) {
  Navigator.of(context).push(smoothPageRoute<void>(
    builder: (_) => StoryReaderPage(
      storyId: storyId,
      highlightStart: range.start,
      highlightEnd: range.end,
    ),
  ),);
}

/// Shows a cited non-story record in a bottom sheet (R17b).
void showCitedRecord(BuildContext context, String id) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _RecordSheet(id: id),
  );
}

/// R17b: a story answer rendered block by block — each paragraph or list
/// item without its citations, followed by an indented evidence chain
/// (`故事集 → 章 → 第 a–b 行`, the line chips open the story). While the
/// answer streams the chains are left out so the text does not jump.
class StoryAnswerBody extends ConsumerWidget {
  const StoryAnswerBody({
    super.key,
    required this.content,
    required this.styleSheet,
    required this.streaming,
  });

  /// Answer markdown without envelope / coverage markers, raw citations kept.
  final String content;
  final MarkdownStyleSheet styleSheet;
  final bool streaming;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    final blocks = splitAnswerBlocks(content);
    final storyIds = {
      for (final b in blocks)
        for (final s in b.stories) s.storyId,
    };
    final entries = streaming || storyIds.isEmpty
        ? const <String, StoryCatalogEntry>{}
        : ref
                .watch(storyCatalogEntriesProvider(storyLabelsKey(storyIds)))
                .valueOrNull ??
            const <String, StoryCatalogEntry>{};
    // Records are numbered in order of first citation in the whole answer,
    // as in the summary tree below it.
    final recordNumbers = extractCitedRecordIds(content);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (i, block) in blocks.indexed) ...[
          if (i > 0) const SizedBox(height: 8),
          Padding(
            padding: EdgeInsets.only(left: 18.0 * block.indent),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (block.markdown.trim().isNotEmpty)
                  MarkdownBody(data: block.markdown, styleSheet: styleSheet),
                if (!streaming && block.hasCitations)
                  Padding(
                    // List items: align with the item text, past the bullet.
                    padding: EdgeInsets.only(
                      left: _isListItem(block.markdown) ? 18 : 0,
                      top: 4,
                    ),
                    child: _EvidenceChain(
                      block: block,
                      entries: entries,
                      recordNumbers: recordNumbers,
                      theme: theme,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  static final RegExp _listMarker = RegExp(r'^(?:[-*+]|\d+[.)])\s');
  static bool _isListItem(String markdown) => _listMarker.hasMatch(markdown);
}

class _EvidenceChain extends ConsumerWidget {
  const _EvidenceChain({
    required this.block,
    required this.entries,
    required this.recordNumbers,
    required this.theme,
  });

  final AnswerBlock block;
  final Map<String, StoryCatalogEntry> entries;
  final List<String> recordNumbers;
  final AppThemeTokens theme;

  (String, String) _labels(String storyId) {
    final entry = entries[storyId];
    if (entry != null) return (entry.collectionLabel, entry.chapterLabel);
    final fallback = fallbackStoryLabel(storyId);
    final cut = fallback.indexOf(' · ');
    return cut < 0
        ? (fallback, '')
        : (fallback.substring(0, cut), fallback.substring(cut + 3));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final muted = theme.bodyFont.copyWith(
      color: theme.textSecondary,
      fontSize: 12,
      height: 1.4,
    );
    String lineText(int start, int? end) => end == null
        ? context.t.aiCitationLine(start)
        : context.t.aiCitationLines(start, end);

    final rows = <Widget>[
      for (final story in block.stories)
        Builder(builder: (context) {
          final (collection, chapter) = _labels(story.storyId);
          return Wrap(
            spacing: 4,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(collection, style: muted),
              if (chapter.isNotEmpty) ...[
                Text('→', style: muted),
                Text(chapter, style: muted),
              ],
              Text('→', style: muted),
              for (final range in story.ranges)
                _chip(
                  key: 'chain:${range.rawRef(story.storyId)}',
                  text: citedRangeText(range, lineText),
                  tooltip: range.rawRef(story.storyId),
                  onTap: () => openStoryReader(context, story.storyId, range),
                ),
            ],
          );
        },),
      for (final id in block.records)
        Wrap(
          spacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _chip(
              key: 'chain:record:$id',
              text: '${context.t.aiCitedRecord} ${recordNumbers.indexOf(id) + 1}'
                  '${_title(ref, id).isEmpty ? '' : ' · ${_title(ref, id)}'}',
              tooltip: 'record:$id',
              onTap: () => showCitedRecord(context, id),
            ),
          ],
        ),
    ];
    return Container(
      padding: const EdgeInsets.only(left: 8),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: theme.divider, width: 2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (i, row) in rows.indexed) ...[
            if (i > 0) const SizedBox(height: 4),
            row,
          ],
        ],
      ),
    );
  }

  String _title(WidgetRef ref, String id) =>
      ref.watch(citedRecordProvider(id)).valueOrNull?.title ?? '';

  Widget _chip({
    required String key,
    required String text,
    required String tooltip,
    required VoidCallback onTap,
  }) =>
      Tooltip(
        message: tooltip,
        triggerMode: TooltipTriggerMode.longPress,
        child: InkWell(
          key: ValueKey(key),
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: theme.accentPrimary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: theme.accentPrimary.withValues(alpha: 0.5),
                width: 0.5,
              ),
            ),
            child: Text(
              text,
              style: theme.bodyFont.copyWith(
                color: theme.accentPrimary,
                fontSize: 11,
              ),
            ),
          ),
        ),
      );
}

class _RecordSheet extends ConsumerWidget {
  const _RecordSheet({required this.id});
  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    final record = ref.watch(citedRecordProvider(id));
    final muted = theme.bodyFont.copyWith(color: theme.textSecondary);
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.7,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: record.when(
          loading: () => const LinearProgressIndicator(minHeight: 2),
          error: (_, __) => Text(context.t.aiCitedLinesUnavailable, style: muted),
          data: (r) => r == null
              ? Text(context.t.aiCitedLinesUnavailable, style: muted)
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (r.title.isNotEmpty)
                      Text(r.title, style: theme.titleFont.copyWith(fontSize: 16)),
                    const SizedBox(height: 8),
                    SelectableText(
                      r.content,
                      style: theme.bodyFont.copyWith(
                        color: theme.textPrimary,
                        height: 1.55,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
