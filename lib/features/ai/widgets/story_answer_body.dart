import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/agent/agent_provider.dart' show gameStoreProvider;
import '../../../core/agent/lore_answer_stages.dart' show loreDetailsMarker;
import '../../../core/gamedata/build/text_harvest.dart' show cleanRichText;
import '../../../core/gamedata/game.dart' show gameOfId;
import '../../../core/gamedata/story_catalog.dart' show fallbackStoryLabel;
import '../../../core/library/library_queries.dart' show entryIdOfRecord;
import '../../../core/library/placeholders.dart';
import '../../../core/library/portrait_provider.dart';
import '../../../core/materials/material_provider.dart';
import '../../../core/wiki/wiki_page.dart';
import '../../../core/wiki/wiki_provider.dart';
import '../../../shared/l10n/l10n.dart';
import '../../../shared/providers/handoff_provider.dart';
import '../../../shared/providers/settings_provider.dart';
import '../../../shared/providers/theme_provider.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../shared/theme/cut_border.dart';
import '../../../shared/theme/motion.dart';
import '../../../shared/widgets/ef_widgets.dart';
import '../../../shared/widgets/press_feedback.dart';
import '../../../shared/widgets/smooth_page_route.dart';
import '../../library/entry_page.dart';
import '../../library/material_pages.dart';
import '../../library/portrait_sheet.dart';
import '../../library/reading_text.dart';
import '../investigation_ui.dart';
import '../speaker_highlight.dart';
import '../story_labels_provider.dart';
import '../story_reader_page.dart';

/// Opens the whole story at [range] (R17b).
void openStoryReader(BuildContext context, String storyId, CitedRange range) {
  Navigator.of(context).push(
    smoothPageRoute<void>(
      builder: (_) => StoryReaderPage(
        storyId: storyId,
        portraitOrigin: PortraitOrigin.ask,
        highlightStart: range.start,
        highlightEnd: range.end,
      ),
    ),
  );
}

/// Opens a cited non-story record where the library shows it: the page of
/// the entry it is part of, rendered as the library renders it. A record
/// with no entry (an older knowledge base) opens in a bottom sheet.
Future<void> showCitedRecord(
  BuildContext context,
  WidgetRef ref,
  String id,
) async {
  String? entryId;
  try {
    entryId = await ref
        .read(gameStoreProvider(gameOfId(id)))
        .withDatabase<String?>((db) => entryIdOfRecord(db, id));
  } catch (_) {}
  if (!context.mounted) return;
  if (entryId != null) {
    final target = entryId;
    await Navigator.of(context).push(
      smoothPageRoute<void>(
        builder: (_) => EntryPage(entryId: target),
      ),
    );
    return;
  }
  await showAppSheet<void>(
    context,
    (_) => PlainSheet(child: _RecordSheet(id: id)),
  );
}

/// 0.13: shows the cited paragraphs of a wiki page (the version the agent
/// read) in a bottom sheet, with a way to open the page in the Wiki tab.
void showCitedWiki(BuildContext context, String pageId, CitedRange range) {
  showAppSheet<void>(
    context,
    (_) => PlainSheet(child: WikiCitationSheet(pageId: pageId, range: range)),
  );
}

/// The wiki tab (its `WikiSiteConfig` id) that shows [site]'s pages.
String wikiTabIdOf(WikiSite site) => switch (site) {
      WikiSite.prts => 'prts',
      WikiSite.warfarin => 'endfield',
    };

/// Opens [url] of [site] in the Wiki tab (leaving the pages pushed over the
/// main tabs).
void openInWikiTab(
  BuildContext context,
  WidgetRef ref,
  WikiSite site,
  Uri url,
) {
  ref.read(wikiOpenRequestProvider.notifier).state =
      WikiOpenRequest(wikiTabIdOf(site), url);
  ref.read(mainTabRequestProvider.notifier).state = 0;
  Navigator.of(context).popUntil((route) => route.isFirst);
}

/// The label of a cited wiki page: `PRTS《title》` once its kept version is
/// loaded, the site's name before (or when it is not kept).
String wikiPageLabel(WidgetRef ref, String pageId) {
  final page = ref.watch(citedWikiPageProvider(pageId)).valueOrNull;
  final site = WikiPageId.parse(pageId)?.site;
  if (page != null) return '${page.site.label}《${page.title}》';
  return site?.label ?? 'Wiki';
}

/// R17b: a story answer rendered block by block — each paragraph or list
/// item without its citations, followed by an indented evidence chain
/// (`故事集 → 章 → 第 a–b 行`, the line chips open the story). R17d: while
/// the answer streams, every block but the one being written already shows
/// its chain, so the text grows only at the bottom and what the reader has
/// scrolled to never moves.
///
/// R18: an answer with [loreDetailsMarker] shows the reorganised paragraphs
/// above it and folds the detailed answer below it into one row
/// ("详细经过 · N 条"), also while the detailed answer is still streaming —
/// so the row keeps one height until the reader opens it.
class StoryAnswerBody extends ConsumerStatefulWidget {
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
  ConsumerState<StoryAnswerBody> createState() => _StoryAnswerBodyState();
}

class _StoryAnswerBodyState extends ConsumerState<StoryAnswerBody> {
  bool _detailsOpen = false;
  List<String>? _names;
  SpeakerMatcher? _matcher;

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider);
    final names =
        widget.streaming ? null : ref.watch(highlightNamesProvider).valueOrNull;
    if (!identical(names, _names)) {
      _names = names;
      _matcher = names == null || names.isEmpty ? null : SpeakerMatcher(names);
    }
    final content = widget.content;
    final cut = content.indexOf(loreDetailsMarker);
    // Records are numbered in order of first citation in the whole answer,
    // as in the summary tree below it.
    final recordNumbers = extractCitedRecordIds(content);
    if (cut < 0) {
      return _blocks(
        splitAnswerBlocks(content),
        recordNumbers,
        theme,
        streaming: widget.streaming,
      );
    }
    final top = splitAnswerBlocks(content.substring(0, cut));
    final details = splitAnswerBlocks(
      content.substring(cut + loreDetailsMarker.length),
    );
    final count = details.where((b) => !_isHeading(b.markdown)).length;
    // The paragraphs are written after the details: while they stream, the
    // details are complete.
    final writingTop = widget.streaming && top.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (top.isNotEmpty) ...[
          _blocks(top, recordNumbers, theme, streaming: writingTop),
          const SizedBox(height: 8),
        ],
        PressRow(
          key: const ValueKey('answer-details-toggle'),
          onTap: () => setState(() => _detailsOpen = !_detailsOpen),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _detailsOpen
                      ? Icons.expand_less_sharp
                      : Icons.expand_more_sharp,
                  size: 20,
                  color: theme.textPrimary,
                ),
                const SizedBox(width: 6),
                Text(
                  context.t.aiAnswerDetails(count),
                  style: theme.ui(15, weight: 700),
                ),
              ],
            ),
          ),
        ),
        if (_detailsOpen) ...[
          const SizedBox(height: 6),
          _blocks(
            details,
            recordNumbers,
            theme,
            streaming: widget.streaming && !writingTop,
          ),
        ],
      ],
    );
  }

  Widget _blocks(
    List<AnswerBlock> blocks,
    List<String> recordNumbers,
    AppThemeTokens theme, {
    required bool streaming,
  }) =>
      Column(
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
                    MarkdownBody(
                      data: !widget.streaming && _matcher != null
                          ? _matcher!.linkNames(block.markdown)
                          : block.markdown,
                      styleSheet: widget.styleSheet.copyWith(
                        a: (widget.styleSheet.p ?? theme.text(16)).copyWith(
                          backgroundColor: theme.accentPrimary,
                          color: theme.onAccent,
                          decoration: TextDecoration.none,
                        ),
                      ),
                      onTapLink: (_, href, __) {
                        final prefix = '$speakerLinkScheme:';
                        if (href != null && href.startsWith(prefix)) {
                          showPortraitSheet(
                            context,
                            speaker: Uri.decodeComponent(
                              href.substring(prefix.length),
                            ),
                            origin: PortraitOrigin.ask,
                          );
                        }
                      },
                    ),
                  // The last block may still be receiving its citations.
                  if (block.hasCitations &&
                      (!streaming || i < blocks.length - 1))
                    Padding(
                      // List items: align with the item text, past the bullet.
                      padding: EdgeInsets.only(
                        left: _isListItem(block.markdown) ? 18 : 0,
                        top: 4,
                      ),
                      child: _EvidenceChain(
                        block: block,
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

  static final RegExp _listMarker = RegExp(r'^(?:[-*+]|\d+[.)])\s');
  static bool _isListItem(String markdown) => _listMarker.hasMatch(markdown);
  static bool _isHeading(String markdown) =>
      markdown.trimLeft().startsWith('#');
}

/// R18b: the sources of one block, folded into one tag — "出处 N" and the
/// story collections — that opens a card with `故事集 · 章` and the line
/// chips. Folded by default; only the reader's tap changes its height.
class _EvidenceChain extends ConsumerStatefulWidget {
  const _EvidenceChain({
    required this.block,
    required this.recordNumbers,
    required this.theme,
  });

  final AnswerBlock block;
  final List<String> recordNumbers;
  final AppThemeTokens theme;

  @override
  ConsumerState<_EvidenceChain> createState() => _EvidenceChainState();
}

class _EvidenceChainState extends ConsumerState<_EvidenceChain> {
  bool _open = false;

  AppThemeTokens get theme => widget.theme;

  (String, String) _labels(String storyId) {
    final entry = ref.watch(storyCatalogEntryProvider(storyId)).valueOrNull;
    if (entry != null) return (entry.collectionLabel, entry.chapterLabel);
    final fallback = fallbackStoryLabel(storyId);
    final cut = fallback.indexOf(' · ');
    return cut < 0
        ? (fallback, '')
        : (fallback.substring(0, cut), fallback.substring(cut + 3));
  }

  @override
  Widget build(BuildContext context) {
    final block = widget.block;
    final count = block.stories.fold<int>(0, (n, s) => n + s.ranges.length) +
        block.records.length +
        block.wikis.fold<int>(0, (n, w) => n + w.ranges.length);
    final collections = <String>{
      for (final story in block.stories) _labels(story.storyId).$1,
      if (block.records.isNotEmpty) context.t.aiCitedRecord,
      if (block.wikis.isNotEmpty) context.t.aiCitedWiki,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _toggle(count, collections.join(' / ')),
        // As FoldSection: snap open, the card its own layer.
        AnimatedSize(
          duration: Motion.of(context, Motion.wipe),
          curve: _open ? Motion.snap : Motion.mech,
          alignment: Alignment.topLeft,
          child: _open
              ? RepaintBoundary(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: _card(context),
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }

  Widget _toggle(int count, String collections) => Semantics(
        button: true,
        expanded: _open,
        child: PressBuilder(
          builder: (context, down) => GestureDetector(
            key: const ValueKey('evidence-toggle'),
            behavior: HitTestBehavior.opaque,
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() => _open = !_open);
            },
            child: Padding(
              // 44 to the finger.
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: AnimatedContainer(
                duration: Motion.of(context, Motion.press),
                curve: Motion.mech,
                constraints: const BoxConstraints(minHeight: 36),
                padding: const EdgeInsets.fromLTRB(10, 6, 12, 6),
                decoration: ShapeDecoration(
                  color: down
                      ? pressTint(_toggleGround, theme.textPrimary)
                      : _toggleGround,
                  shape: const CutBorder.br(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.menu_book_sharp,
                      size: 16,
                      color: _open ? theme.onAccent : theme.textPrimary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      context.t.aiCitationSources(count),
                      style: theme.ui(
                        13,
                        weight: 700,
                        color: _open ? theme.onAccent : theme.textPrimary,
                      ),
                    ),
                    if (collections.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          collections,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.text(
                            13,
                            color: _open ? theme.onAccent : theme.textSecondary,
                          ),
                        ),
                      ),
                    ],
                    AnimatedRotation(
                      turns: _open ? 0.5 : 0,
                      duration: Motion.of(context, Motion.wipe),
                      curve: Motion.mech,
                      child: Icon(
                        Icons.expand_more_sharp,
                        size: 18,
                        color: _open ? theme.onAccent : theme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

  Color get _toggleGround =>
      _open ? theme.accentPrimary : theme.surfaceElevated;

  /// The block's stories grouped by collection (first-cited order), the
  /// chapters of one collection in story order.
  List<_SourceGroup> _groups() {
    final groups = <String, _SourceGroup>{};
    for (final story in widget.block.stories) {
      final (collection, chapter) = _labels(story.storyId);
      final sort = ref
              .watch(storyCatalogEntryProvider(story.storyId))
              .valueOrNull
              ?.storySort ??
          1 << 30;
      groups
          .putIfAbsent(collection, () => _SourceGroup(collection))
          .chapters
          .add(_SourceChapter(story, chapter, sort));
    }
    for (final group in groups.values) {
      group.chapters.sort((a, b) {
        final byOrder = a.sort.compareTo(b.sort);
        return byOrder != 0
            ? byOrder
            : a.story.storyId.compareTo(b.story.storyId);
      });
    }
    return groups.values.toList();
  }

  Widget _card(BuildContext context) {
    final block = widget.block;
    String lineText(int start, int? end) => end == null
        ? context.t.aiCitationLine(start)
        : context.t.aiCitationLines(start, end);

    // The line chips of a chapter: siblings of its name in one Wrap, so they
    // share its row and wrap one by one only when the row is full.
    List<Widget> chips(_SourceChapter chapter) => [
          for (final range in chapter.story.ranges)
            _chip(
              key: 'chain:${range.rawRef(chapter.story.storyId)}',
              text: citedRangeText(range, lineText),
              tooltip: range.rawRef(chapter.story.storyId),
              onTap: () =>
                  openStoryReader(context, chapter.story.storyId, range),
            ),
        ];

    final collectionStyle =
        theme.ui(13, weight: 700, color: theme.textSecondary);
    final chapterStyle = theme.text(13.5, weight: FontWeight.w500, height: 1.4);

    Widget groupWidget(_SourceGroup group) {
      // One chapter: "collection · chapter" and its chips on one line.
      if (group.chapters.length == 1) {
        final chapter = group.chapters.single;
        return Wrap(
          spacing: 6,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: group.collection, style: collectionStyle),
                  if (chapter.label.isNotEmpty) ...[
                    TextSpan(
                      text: ' / ',
                      style: collectionStyle.copyWith(color: theme.divider),
                    ),
                    TextSpan(text: chapter.label, style: chapterStyle),
                  ],
                ],
              ),
            ),
            ...chips(chapter),
          ],
        );
      }
      // Several chapters: the collection once, the chapters indented under
      // it on a thin guide line, each with its chips on the same row.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(group.collection, style: collectionStyle),
          Container(
            margin: const EdgeInsets.only(left: 3, top: 3),
            padding: const EdgeInsets.only(left: 9),
            decoration: BoxDecoration(
              border: Border(left: BorderSide(color: theme.divider, width: 1)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final (i, chapter) in group.chapters.indexed) ...[
                  if (i > 0) const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (chapter.label.isNotEmpty)
                        Text(chapter.label, style: chapterStyle),
                      ...chips(chapter),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      );
    }

    final rows = <Widget>[
      for (final group in _groups()) groupWidget(group),
      if (block.records.isNotEmpty)
        Wrap(
          spacing: 5,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final id in block.records)
              _chip(
                key: 'chain:record:$id',
                text: '${context.t.aiCitedRecord} '
                    '${widget.recordNumbers.indexOf(id) + 1}'
                    '${_title(id).isEmpty ? '' : ' / ${_title(id)}'}',
                tooltip: 'record:$id',
                onTap: () => showCitedRecord(context, ref, id),
              ),
          ],
        ),
      for (final material in block.materials)
        Wrap(
          spacing: 6,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              ref
                      .watch(citedMaterialProvider(material.pageId))
                      .valueOrNull
                      ?.title ??
                  '补充资料',
              style: chapterStyle,
            ),
            for (final range in material.ranges)
              _chip(
                key: 'chain:${material.pageId}:${range.start}',
                text: range.start == range.end
                    ? context.t.aiCitationParagraph(range.start + 1)
                    : context.t
                        .aiCitationParagraphs(range.start + 1, range.end + 1),
                tooltip: '${material.pageId}:${range.start}-${range.end}',
                onTap: () => openMaterialPage(
                  context,
                  MaterialReaderPage(
                    pageId: material.pageId,
                    start: range.start,
                    end: range.end,
                  ),
                ),
              ),
          ],
        ),
      // 0.13: wiki pages — "PRTS《title》" and its paragraph chips.
      for (final wiki in block.wikis)
        Wrap(
          spacing: 6,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(wikiPageLabel(ref, wiki.pageId), style: chapterStyle),
            for (final range in wiki.ranges)
              _chip(
                key: 'chain:${wiki.pageId}:${range.start}',
                // Shown from 1, as line numbers are.
                text: range.start == range.end
                    ? context.t.aiCitationParagraph(range.start + 1)
                    : context.t
                        .aiCitationParagraphs(range.start + 1, range.end + 1),
                tooltip: '${wiki.pageId}:${range.start}-${range.end}',
                onTap: () => showCitedWiki(context, wiki.pageId, range),
              ),
          ],
        ),
    ];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: theme.cardSurface,
        border: Border(
          left: BorderSide(color: theme.trace, width: 3),
          top: BorderSide(color: theme.divider),
          right: BorderSide(color: theme.divider),
          bottom: BorderSide(color: theme.divider),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (i, row) in rows.indexed) ...[
            if (i > 0)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Divider(height: 1, thickness: 1, color: theme.divider),
              ),
            row,
          ],
        ],
      ),
    );
  }

  String _title(String id) =>
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
        child: Semantics(
          button: true,
          child: PressBuilder(
            builder: (context, down) => GestureDetector(
              key: ValueKey(key),
              behavior: HitTestBehavior.opaque,
              onTap: withHaptic(onTap),
              child: Padding(
                // 44 to the finger.
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: AnimatedContainer(
                  duration: Motion.of(context, Motion.press),
                  curve: Motion.mech,
                  constraints: const BoxConstraints(minHeight: 36),
                  padding: const EdgeInsets.fromLTRB(9, 6, 10, 6),
                  decoration: ShapeDecoration(
                    color: down
                        ? pressTint(theme.surfaceElevated, theme.textPrimary)
                        : theme.surfaceElevated,
                    shape: const CutBorder.br(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        text,
                        style: theme.field(
                          color: theme.textPrimary,
                          size: 13,
                          weight: 600,
                        ),
                      ),
                      const SizedBox(width: 2),
                      Icon(
                        Icons.chevron_right_sharp,
                        size: 16,
                        color: theme.textPrimary,
                      ),
                    ],
                  ),
                ),
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
    final muted = theme.text(14, color: theme.textSecondary);
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.7,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: record.when(
          loading: () => const BusyMark(width: 80, cells: 8),
          error: (_, __) =>
              Text(context.t.aiCitedLinesUnavailable, style: muted),
          data: (r) => r == null
              ? Text(context.t.aiCitedLinesUnavailable, style: muted)
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (r.title.isNotEmpty)
                      Text(r.title, style: theme.heading(18)),
                    const SizedBox(height: 8),
                    CitedRecordText(r.content),
                  ],
                ),
        ),
      ),
    );
  }
}

/// A cited record's text as the library shows it: a profile file (`## `
/// parts) in its parts, anything else as reading text.
class CitedRecordText extends ConsumerWidget {
  const CitedRecordText(this.content, {super.key, this.size = 15.5});

  final String content;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = cleanRichText(
      withPlaceholders(content, ref.watch(nicknameProvider)),
    ).trim();
    return text.contains('## ')
        ? ProfileText(text)
        : ReadingText(text, fields: isFieldList(text), size: size);
  }
}

/// 0.13: the cited paragraphs of a wiki page as the agent read them (with
/// one paragraph around them for context), under their section headings;
/// the page's site, title and when it was read; a button to the page.
class WikiCitationSheet extends ConsumerWidget {
  const WikiCitationSheet({
    super.key,
    required this.pageId,
    required this.range,
  });

  final String pageId;
  final CitedRange range;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    final id = WikiPageId.parse(pageId);
    final page = ref.watch(citedWikiPageProvider(pageId));
    final muted = theme.text(13, color: theme.textSecondary, height: 1.5);
    final body = readingStyle(theme, size: 15.5);

    Widget content(WikiPage? p) {
      if (p == null) return Text(context.t.aiWikiPageUnavailable, style: muted);
      final shown = p.range(range.start - 1, range.end + 1);
      String? section;
      final date =
          MaterialLocalizations.of(context).formatShortDate(p.fetchedAt);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${p.site.label}《${p.title}》',
            style: theme.heading(18),
          ),
          const SizedBox(height: 4),
          Text(context.t.aiWikiVersion(p.site.label, date), style: muted),
          const SizedBox(height: 10),
          for (final (i, block) in shown) ...[
            if (block.section.isNotEmpty && block.section != section)
              Padding(
                padding: const EdgeInsets.only(top: 6, bottom: 4),
                child: Text(
                  section = block.section,
                  style: theme.ui(13, weight: 700, color: theme.textSecondary),
                ),
              ),
            _paragraph(
              theme,
              i,
              block.text,
              cited: i >= range.start && i <= range.end,
              style: body,
            ),
          ],
        ],
      );
    }

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.75,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            page.when(
              loading: () => const BusyMark(width: 80, cells: 8),
              error: (_, __) => content(null),
              data: content,
            ),
            const SizedBox(height: 12),
            Text(context.t.aiWikiSecondary, style: muted),
            if (id != null) ...[
              const SizedBox(height: 10),
              AppButton(
                context.t.aiWikiOpen,
                key: const ValueKey('wiki-citation-open'),
                icon: Icons.language_sharp,
                onPressed: () => openInWikiTab(
                  context,
                  ref,
                  id.site,
                  page.valueOrNull?.url ?? id.url,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// One paragraph: the cited ones on the accent rail, the context ones
  /// muted.
  Widget _paragraph(
    AppThemeTokens theme,
    int index,
    String text, {
    required bool cited,
    required TextStyle style,
  }) =>
      Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.fromLTRB(10, 4, 4, 4),
        decoration: BoxDecoration(
          color: cited
              ? theme.accentPrimary
                  .withValues(alpha: theme.isDark ? 0.14 : 0.22)
              : null,
          border: Border(
            left: BorderSide(
              color: cited ? theme.trace : theme.divider,
              width: cited ? 3 : 1,
            ),
          ),
        ),
        child: SelectableText(
          text,
          style: cited ? style : style.copyWith(color: theme.textSecondary),
        ),
      );
}

/// The chapters of one story collection cited by a block.
class _SourceGroup {
  _SourceGroup(this.collection);
  final String collection;
  final List<_SourceChapter> chapters = [];
}

class _SourceChapter {
  _SourceChapter(this.story, this.label, this.sort);
  final BlockStoryCitation story;
  final String label;
  final int sort;
}
