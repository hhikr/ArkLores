import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/gamedata/story_catalog.dart' show fallbackStoryLabel;
import '../../core/gamedata/story_coverage_models.dart'
    show StoryLineEntry, storyKindLabel;
import '../../core/library/library_labels.dart';
import '../../core/library/library_provider.dart';
import '../../core/library/library_queries.dart' show LibraryEntry;
import '../../core/library/placeholders.dart';
import '../../core/userdata/library_ref.dart';
import '../../core/userdata/user_data_provider.dart';
import '../../core/userdata/user_data_store.dart'
    show UserDataStore, readingEndDwell, readingEndLines, reanchorLine;
import '../../shared/l10n/l10n.dart';
import '../../shared/providers/settings_provider.dart';
import '../../shared/providers/theme_provider.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/smooth_page_route.dart';
import 'story_labels_provider.dart';

/// The story reader's font: LXGW WenKai Screen (bundled, see pubspec).
const String readingFontFamily = 'LXGWWenKaiScreen';

/// The whole text of one story. Three ways in:
///
/// - **cited** ([highlightStart]–[highlightEnd], 0-based `line_index`): opened
///   from an answer's evidence. Scrolls to the lines, flashes them twice, then
///   keeps them highlighted (R17b);
/// - **resumed** ([resumeLine], with [snippet] to find the line again if the
///   story changed): opened from the reading history. Scrolls to where the
///   reader was and marks that line;
/// - neither: opened from the library, at the top.
///
/// R18b layout: the text starts at the page gutter (line numbers sit small
/// on the right), a speaker's name is shown only when the speaker changes,
/// the cited lines are one rounded block, and the app bar can jump back to
/// them.
///
/// 0.11: the page records the visit and where the reader is (first and last
/// line on screen) in the reading history, and offers the previous and next
/// chapter of the story's collection.
class StoryReaderPage extends ConsumerWidget {
  const StoryReaderPage({
    super.key,
    required this.storyId,
    this.highlightStart,
    this.highlightEnd,
    this.resumeLine,
    this.snippet,
  });

  final String storyId;
  final int? highlightStart;
  final int? highlightEnd;

  /// The line the reader was at (history); highlighted lines win over it.
  final int? resumeLine;

  /// The text of the anchor line, to find it again in a changed story.
  final String? snippet;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reading = ref.watch(storyReadingProvider(storyId));
    final r = reading.valueOrNull;
    if (r == null) {
      final theme = ref.watch(themeProvider);
      return Scaffold(
        backgroundColor: theme.bgPrimary,
        appBar: AppBar(
          backgroundColor: theme.bgPrimary,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
        ),
        body: reading.isLoading
            ? const Center(child: CircularProgressIndicator())
            : Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(
                    context.t.aiCitedLinesUnavailable,
                    textAlign: TextAlign.center,
                    style: theme.bodyFont.copyWith(color: theme.textSecondary),
                  ),
                ),
              ),
      );
    }
    // Dialogue attached to a story is read at the end of that story: the
    // lines asked for move with it.
    return _StoryReaderBody(
      key: ValueKey('story-reader-${r.hostId}'),
      storyId: r.hostId,
      text: r.lines,
      shift: r.offset,
      highlightStart: highlightStart == null ? null : highlightStart! + r.offset,
      highlightEnd: highlightEnd == null ? null : highlightEnd! + r.offset,
      resumeLine: resumeLine == null ? null : resumeLine! + r.offset,
      snippet: snippet,
    );
  }
}

class _StoryReaderBody extends ConsumerStatefulWidget {
  const _StoryReaderBody({
    super.key,
    required this.storyId,
    required this.text,
    this.shift = 0,
    this.highlightStart,
    this.highlightEnd,
    this.resumeLine,
    this.snippet,
  });

  final String storyId;

  /// The whole text: the story, then the dialogue attached to it.
  final List<StoryLineEntry> text;

  /// Where the story asked for begins in [text]; the numbers the reader shows
  /// for a cited range are its own.
  final int shift;
  final int? highlightStart;
  final int? highlightEnd;
  final int? resumeLine;
  final String? snippet;

  @override
  ConsumerState<_StoryReaderBody> createState() => _StoryReaderPageState();
}

class _StoryReaderPageState extends ConsumerState<_StoryReaderBody>
    with SingleTickerProviderStateMixin {
  final GlobalKey _targetKey = GlobalKey();
  final GlobalKey _scrollKey = GlobalKey();
  final Map<int, GlobalKey> _lineKeys = {};
  bool _scrolled = false;
  bool _recorded = false;
  bool _anchored = false;
  bool _moved = false;

  /// The cited range, if any (moved by [_anchor] after a story change).
  late final int? _start = widget.highlightStart;
  late final int? _stop = widget.highlightEnd ?? widget.highlightStart;

  /// The line marked as "where you were".
  late int? _resume = widget.highlightStart == null ? widget.resumeLine : null;

  UserDataStore? _store;
  List<StoryLineEntry> _lines = const [];
  Timer? _saveTimer;

  /// The end of the text has been in view long enough, and the timer that
  /// says so ([readingEndDwell] after it came into view).
  bool _endStayed = false;
  Timer? _endTimer;

  final ScrollController _scroll = ScrollController();
  List<_Row> _rows = const [];
  List<StoryLineEntry>? _preparedFor;
  bool _spoken = false;
  String _nickname = '';

  /// The item the lazy list is anchored on (0 = the header, then one per row,
  /// then the end block) and where on the screen it starts (a fraction of the
  /// height). Everything is built outward from it, so opening deep into a
  /// story, or jumping back to a place, costs the same as opening at the top.
  int _center = 0;
  double _centerAt = 0;
  /// Highlight strength: on-off-on-off over 1.2 s, then steady.
  late final AnimationController _flash = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );
  late final Animation<double> _strength = TweenSequence<double>([
    for (var i = 0; i < 2; i++) ...[
      TweenSequenceItem(tween: Tween(begin: 0.25, end: 1), weight: 1),
      TweenSequenceItem(tween: Tween(begin: 1, end: 0.25), weight: 1),
    ],
  ]).animate(CurvedAnimation(parent: _flash, curve: Curves.easeInOut));

  @override
  void dispose() {
    _saveTimer?.cancel();
    _endTimer?.cancel();
    unawaited(_saveProgress());
    _flash.dispose();
    _scroll.dispose();
    super.dispose();
  }

  GlobalKey _keyOf(int index) => _lineKeys.putIfAbsent(index, GlobalKey.new);

  bool get _cited => _start != null;

  bool _isTarget(int index) =>
      _cited && index >= _start! && index <= _stop!;

  /// Finds the history anchor again in the current text (once).
  void _anchor(List<StoryLineEntry> lines) {
    if (_anchored) return;
    _anchored = true;
    _lines = lines;
    final snippet = widget.snippet;
    final line = widget.resumeLine;
    if (snippet == null || line == null || _cited) return;
    final found = reanchorLine([for (final l in lines) l.content], line, snippet);
    if (found == null) return;
    _resume = lines[found.index].lineIndex;
    _moved = !found.exact;
  }

  /// Computes what the list needs from the text, once per text.
  void _prepare(List<StoryLineEntry> lines) {
    if (identical(_preparedFor, lines)) return;
    _preparedFor = lines;
    _lines = lines;
    // Narration is set in italics only between spoken lines; a text that is
    // all narration (a month squad's story, a document) is plain.
    _spoken = lines.any((l) => (l.speaker ?? '').trim().isNotEmpty);
    _rows = _makeRows(lines);
    // Open anchored on the cited block or the line to resume at.
    _anchorOnTarget();
  }

  // ─── History ───────────────────────────────────────────────────

  /// Writes this visit to the reading history (once, after the text loaded;
  /// the history is a convenience, so a failure is ignored).
  void _recordLater(List<StoryLineEntry> lines) {
    if (_recorded) return;
    _recorded = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => _record(lines));
  }

  Future<void> _record(List<StoryLineEntry> lines) async {
    try {
      final entry =
          await ref.read(storyCatalogEntryProvider(widget.storyId).future);
      final title = entry?.label ?? fallbackStoryLabel(widget.storyId);
      final store = await ref.read(userDataStoreProvider.future);
      _store = store;
      final at = _start ?? _resume ?? 0;
      final anchor = lines.firstWhere(
        (l) => l.lineIndex == at,
        orElse: () => lines.first,
      );
      await store.recordOpen(
        LibraryRef.story(widget.storyId),
        title: title,
        lineIndex: anchor.lineIndex,
        snippet: anchor.content,
        totalLines: lines.length,
      );
      if (mounted) invalidateReading(ref);
    } catch (_) {}
  }

  /// First and last line on screen, by position. Only lines that are built
  /// have a place to measure (the list is lazy), and those are the ones near
  /// the screen.
  (int, int)? _visibleRange() {
    final viewport = _scrollKey.currentContext?.findRenderObject();
    if (viewport is! RenderBox || !viewport.attached || _lines.isEmpty) {
      return null;
    }
    final top = viewport.localToGlobal(Offset.zero).dy + 8;
    final bottom = viewport.localToGlobal(Offset(0, viewport.size.height)).dy;
    int? first, last;
    for (final e in _lineKeys.entries) {
      final box = e.value.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.attached) continue;
      final y = box.localToGlobal(Offset.zero).dy;
      if (y + box.size.height > top && y < bottom) {
        if (first == null || e.key < first) first = e.key;
        if (last == null || e.key > last) last = e.key;
      }
    }
    return first == null ? null : (first, last!);
  }
  Future<void> _saveProgress() async {
    final store = _store;
    final range = _visibleRange();
    if (store == null || range == null) return;
    final first = _lines[range.$1];
    final last = _lines[range.$2];
    // The end counts as reached once it has stayed in view for a while: the
    // timer says so; moving away from the end starts over.
    final nearEnd = range.$2 >= _lines.length - readingEndLines;
    if (!nearEnd) {
      _endTimer?.cancel();
      _endTimer = null;
      _endStayed = false;
    } else if (!_endStayed && _endTimer == null) {
      _endTimer = Timer(readingEndDwell, () {
        _endStayed = true;
        _saveSoon();
      });
    }
    final atEnd = nearEnd && _endStayed;    try {
      await store.updateProgress(
        LibraryRef.story(widget.storyId),
        lineIndex: first.lineIndex,
        snippet: first.content,
        totalLines: _lines.length,
        reached: last.lineIndex,
        atEnd: atEnd,
      );
    } catch (_) {}
  }

  void _saveSoon() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), () async {
      await _saveProgress();
      if (mounted) invalidateReading(ref);
    });
  }

  // ─── Scrolling ─────────────────────────────────────────────────

  /// The row (not the item) holding the cited block or the line to resume at.
  int? _targetRow() {
    final at = _cited ? _start : _resume;
    if (at == null) return null;
    final p = _lines.indexWhere((l) => l.lineIndex == at);
    if (p < 0) return null;
    final r = _rows.indexWhere((row) => row.first <= p && p <= row.last);
    return r < 0 ? null : r;
  }

  /// Anchors the list on the cited block or the line to resume at.
  void _anchorOnTarget() {
    final r = _targetRow();
    if (r == null) return;
    _center = r + 1;
    _centerAt = _cited ? 0.25 : 0.08;
  }

  /// Back to the cited block or the line the reader was at, from wherever
  /// they have scrolled to.
  void _jumpToTarget() {
    if (_targetRow() == null || !mounted) return;
    if (_scroll.hasClients) _scroll.jumpTo(0);
    setState(_anchorOnTarget);
    if (_cited) _flash.forward(from: 0);
  }

  void _scrollToTarget() {
    if (_scrolled) return;
    _scrolled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_cited && mounted) _flash.forward(from: 0);
      // Short stories fit the screen: no scroll will report them.
      if (mounted) _saveSoon();
    });
  }

  // ─── Build ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider);
    final entry =
        ref.watch(storyCatalogEntryProvider(widget.storyId)).valueOrNull;
    final fallback = fallbackStoryLabel(widget.storyId);
    final cut = fallback.indexOf(' · ');
    final collection = entry?.collectionLabel ??
        (cut < 0 ? fallback : fallback.substring(0, cut));
    final chapter =
        entry?.chapterLabel ?? (cut < 0 ? '' : fallback.substring(cut + 3));
    final canJump = _cited || _resume != null;

    _nickname = ref.watch(nicknameProvider);
    return Scaffold(
      backgroundColor: theme.bgPrimary,
      appBar: AppBar(
        backgroundColor: theme.bgPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        titleSpacing: 0,
        title: Text(
          chapter.isNotEmpty ? chapter : collection,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.titleFont.copyWith(fontSize: 16),
        ),
        actions: [
          if (canJump)
            IconButton(
              key: const ValueKey('story-reader-jump'),
              tooltip: context.t.aiStoryReaderJumpBack,
              onPressed: _jumpToTarget,
              icon: Icon(Icons.my_location_rounded, color: theme.accentText),
            ),
        ],
      ),
      body: Builder(
        builder: (context) {
          final lines = widget.text;
          if (lines.isEmpty) return _unavailable(theme);
          _anchor(lines);
          _prepare(lines);
          _recordLater(lines);
          _scrollToTarget();
          final range = !_cited
              ? null
              : _start == _stop
                  ? context.t.aiCitationLine(_start! - widget.shift + 1)
                  : context.t.aiCitationLines(
                      _start! - widget.shift + 1,
                      _stop! - widget.shift + 1,
                    );
          return NotificationListener<ScrollEndNotification>(
            onNotification: (_) {
              _saveSoon();
              return false;
            },
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                key: _scrollKey,
                constraints: const BoxConstraints(maxWidth: 720),
                // Two lazy lists meet at the anchor item: what comes before it
                // (built upward) and what comes from it on. The scroll offset
                // is measured from the anchor, so no height is ever estimated
                // and a story of any length is built the same way.
                child: CustomScrollView(
                  key: const ValueKey('story-reader-scroll'),
                  controller: _scroll,
                  center: const ValueKey('story-reader-center'),
                  anchor: _centerAt,
                  scrollCacheExtent: const ScrollCacheExtent.pixels(1200),
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, i) => _item(
                            theme,
                            _center - 1 - i,
                            collection,
                            chapter,
                            range,
                            entry?.synopsis,
                          ),
                          childCount: _center,
                        ),
                      ),
                    ),
                    SliverPadding(
                      key: const ValueKey('story-reader-center'),
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, i) => _item(
                            theme,
                            _center + i,
                            collection,
                            chapter,
                            range,
                            entry?.synopsis,
                          ),
                          childCount: _rows.length + 2 - _center,
                        ),
                      ),
                    ),
                  ],
                ),              ),
            ),
          );
        },
      ),
    );
  }

  /// Item `i` of the list: the header, a row, or the end of the text.
  Widget _item(
    AppThemeTokens theme,
    int i,
    String collection,
    String chapter,
    String? range,
    String? synopsis,
  ) {
    if (i == 0) return _header(theme, collection, chapter, range, synopsis);
    if (i == _rows.length + 1) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 40),
        child: _end(theme),
      );
    }
    return _rowWidget(theme, i - 1);
  }

  Widget _chip(AppThemeTokens theme, String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: theme.accentPrimary.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          text,
          style: theme.bodyFont.copyWith(
            color: theme.accentText,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      );

  Widget _header(
    AppThemeTokens theme,
    String collection,
    String chapter,
    String? range,
    String? synopsis,
  ) =>
      Padding(
        padding: const EdgeInsets.fromLTRB(10, 4, 10, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_moved)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  context.t.aiStoryReaderMoved,
                  style: theme.bodyFont.copyWith(
                    color: theme.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ),
            Text(
              collection,
              style: theme.bodyFont.copyWith(
                color: theme.textSecondary,
                fontSize: 12,
                letterSpacing: 0.5,
              ),
            ),
            if (chapter.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                chapter,
                style: theme.titleFont.copyWith(fontSize: 20, height: 1.3),
              ),
            ],
            if (range != null) ...[
              const SizedBox(height: 10),
              _chip(theme, '${context.t.aiStoryReaderTitle} · $range'),
            ] else if (_resume != null) ...[
              const SizedBox(height: 10),
              _chip(theme, context.t.storyReaderResumed(_resume! + 1)),
            ],
            if (synopsis != null && synopsis.trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                decoration: BoxDecoration(
                  color: theme.cardSurface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border(
                    left: BorderSide(color: theme.accentPrimary, width: 3),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.t.storyReaderSynopsis,
                      style: theme.bodyFont.copyWith(
                        color: theme.textSecondary,
                        fontSize: 11,
                        letterSpacing: 0.4,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      withPlaceholders(synopsis.trim(), ref.watch(nicknameProvider)),
                      style: theme.bodyFont.copyWith(
                        color: theme.textPrimary,
                        fontSize: 13,
                        height: 1.55,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 14),
            Divider(height: 1, color: theme.divider),
          ],
        ),
      );

  /// What the list is made of: one row per line, the cited lines together in
  /// one highlighted block. Positions are indexes into [_lines].
  List<_Row> _makeRows(List<StoryLineEntry> lines) {
    final rows = <_Row>[];
    var i = 0;
    while (i < lines.length) {
      if (_isTarget(lines[i].lineIndex)) {
        var j = i;
        while (j + 1 < lines.length && _isTarget(lines[j + 1].lineIndex)) {
          j++;
        }
        rows.add(_Row(i, j));
        i = j + 1;
      } else {
        rows.add(_Row(i, i));
        i++;
      }
    }
    return rows;
  }

  /// A line of the text, or the cited block. Built only while it is on (or
  /// near) the screen: the list is lazy, so a story of any length opens and
  /// scrolls the same.
  Widget _rowWidget(AppThemeTokens theme, int index) {
    final row = _rows[index];
    final first = row.first == 0;
    if (row.first == row.last && !_isTarget(_lines[row.first].lineIndex)) {
      final line = _lines[row.first];
      if (line.kind == 'divider') {
        return Padding(
          key: _keyOf(row.first),
          padding: const EdgeInsets.fromLTRB(10, 36, 10, 6),
          child: _divider(theme, line.content),
        );
      }
      final isResume = !_cited && line.lineIndex == _resume;
      final child = Container(
        key: _keyOf(row.first),
        child: _line(
          theme,
          line,
          speaker: _speakerOf(row.first),
          showName: _showName(row.first),
          marked: isResume,
          italicNarration: _spoken,
          nickname: _nickname,
        ),
      );
      return Padding(
        padding: EdgeInsets.fromLTRB(10, first ? 0 : _gapBefore(row.first), 10, 0),
        child: isResume
            ? KeyedSubtree(
                key: ValueKey('story-line-resume-${line.lineIndex}'),
                child: child,
              )
            : child,
      );
    }
    final inside = <Widget>[];
    for (var p = row.first; p <= row.last; p++) {
      if (p > row.first) inside.add(SizedBox(height: _gapBefore(p)));
      inside.add(
        KeyedSubtree(
          key: ValueKey('story-line-target-${_lines[p].lineIndex}'),
          child: Container(
            key: _keyOf(p),
            child: _line(
              theme,
              _lines[p],
              speaker: _speakerOf(p),
              showName: _showName(p),
              italicNarration: _spoken,
              nickname: _nickname,
            ),
          ),
        ),
      );
    }
    return Padding(
      padding: EdgeInsets.only(top: first ? 0 : 8, bottom: 8),
      child: _citedBlock(theme, inside),
    );
  }

  /// The heading of dialogue played in the battle, attached to the story
  /// (`n/total` is the part's place among the parts).
  Widget _divider(AppThemeTokens theme, String place) {
    final parts = place.split('/');
    final many = parts.length == 2 && parts[1] != '1';
    return Row(
      key: const ValueKey('story-reader-battle-dialogue'),
      children: [
        Expanded(child: Divider(color: theme.divider, endIndent: 12)),
        Text(
          many
              ? '${context.t.storyReaderBattleDialogue} ${parts[0]}'
              : context.t.storyReaderBattleDialogue,
          style: theme.bodyFont.copyWith(
            color: theme.accentText,
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
          ),
        ),
        Expanded(child: Divider(color: theme.divider, indent: 12)),
      ],
    );
  }

  String _speakerOf(int p) => (_lines[p].speaker ?? '').trim();

  bool _showName(int p) =>
      _speakerOf(p).isNotEmpty && (p == 0 || _speakerOf(p) != _speakerOf(p - 1));

  /// Between paragraphs a little more than the leading inside one; a new
  /// speaker a little more still.
  double _gapBefore(int p) =>
      p > 0 && _speakerOf(p) == _speakerOf(p - 1) ? 14.0 : 20.0;
  Widget _citedBlock(AppThemeTokens theme, List<Widget> rows) =>
      AnimatedBuilder(
        key: _targetKey,
        animation: _strength,
        builder: (context, child) => Container(
          decoration: BoxDecoration(
            color: theme.accentPrimary.withValues(
              alpha: 0.10 + 0.22 * _strength.value,
            ),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: theme.accentText.withValues(alpha: 0.35),
              width: 0.8,
            ),
          ),
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          child: child,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: rows,
        ),
      );

  /// End of the text: the chapter's end mark and the way on.
  Widget _end(AppThemeTokens theme) {
    final place = ref.watch(storyPlaceProvider(widget.storyId)).valueOrNull;
    return Padding(
      padding: const EdgeInsets.only(top: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Divider(color: theme.divider, endIndent: 12)),
              Text(
                context.t.aiStoryReaderEnd,
                style: theme.bodyFont.copyWith(
                  color: theme.textSecondary,
                  fontSize: 12,
                ),
              ),
              Expanded(child: Divider(color: theme.divider, indent: 12)),
            ],
          ),
          if (place != null &&
              (place.previous != null || place.next != null)) ...[
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: _neighbour(
                    theme,
                    place.previous,
                    context.t.storyReaderPrevious,
                    Icons.chevron_left_rounded,
                    key: const ValueKey('story-reader-previous'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _neighbour(
                    theme,
                    place.next,
                    context.t.storyReaderNext,
                    Icons.chevron_right_rounded,
                    trailingIcon: true,
                    key: const ValueKey('story-reader-next'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _neighbour(
    AppThemeTokens theme,
    LibraryEntry? target,
    String label,
    IconData icon, {
    required Key key,
    bool trailingIcon = false,
  }) {
    if (target == null || target.rawId == null) return const SizedBox.shrink();
    final text = [
      if (target.code != null) target.code!,
      if (target.group != null) target.group!,
      if (target.code == null && target.group == null) entryHeadline(target),
    ].join(' ');
    return Material(
      key: key,
      color: theme.cardSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: theme.cardBorder),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => Navigator.of(context).pushReplacement(
          smoothPageRoute<void>(
            builder: (_) => StoryReaderPage(storyId: target.rawId!),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          child: Row(
            mainAxisAlignment:
                trailingIcon ? MainAxisAlignment.end : MainAxisAlignment.start,
            children: [
              if (!trailingIcon) Icon(icon, color: theme.accentText, size: 22),
              Flexible(
                child: Column(
                  crossAxisAlignment: trailingIcon
                      ? CrossAxisAlignment.end
                      : CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: theme.bodyFont.copyWith(
                        color: theme.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                    Text(
                      text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.titleFont.copyWith(fontSize: 14),
                    ),
                  ],
                ),
              ),
              if (trailingIcon) Icon(icon, color: theme.accentText, size: 22),
            ],
          ),
        ),
      ),
    );
  }

  Widget _unavailable(AppThemeTokens theme) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            context.t.aiCitedLinesUnavailable,
            textAlign: TextAlign.center,
            style: theme.bodyFont.copyWith(color: theme.textSecondary),
          ),
        ),
      );

  /// The tag above a line that is neither dialogue nor narration, in the
  /// interface language (the agent's tools use [storyKindLabel]).
  String? _kindTag(String? kind) => switch (kind) {
        'subtitle' => context.t.lineKindSubtitle,
        'document' => context.t.lineKindDocument,
        'choice' => context.t.lineKindChoice,
        'title' => context.t.lineKindTitle,
        'system' => context.t.lineKindTutorial,
        _ => null,
      };

  Widget _line(
    AppThemeTokens theme,
    StoryLineEntry line, {
    required String speaker,
    required bool showName,
    bool marked = false,
    bool italicNarration = true,
    String nickname = '',
  }) {
    final narration = speaker.isEmpty;
    final plain = narration && !italicNarration;
    final kindTag = _kindTag(line.kind);
    final content = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (showName)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    speaker,
                    style: theme.bodyFont.copyWith(
                      color: theme.accentText,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              if (kindTag != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    kindTag,
                    style: theme.bodyFont.copyWith(
                      color: theme.textMuted,
                      fontSize: 10.5,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
              Text(
                withPlaceholders(line.content, nickname),
                style: theme.bodyFont.copyWith(
                  fontFamily: readingFontFamily,
                  color: narration && !plain
                      ? theme.textSecondary
                      : theme.textPrimary,
                  fontStyle: narration && !plain
                      ? FontStyle.italic
                      : FontStyle.normal,
                  fontSize: narration && !plain ? 14.5 : 15.5,
                  height: 1.7,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 26,
          child: Padding(
            padding: EdgeInsets.only(
              top: showName ? 20 : (kindTag != null ? 18 : 4),
            ),
            child: Text(
              '${(line.shownIndex ?? line.lineIndex) + 1}',
              textAlign: TextAlign.right,
              style: theme.bodyFont.copyWith(
                color: theme.textSecondary.withValues(alpha: 0.5),
                fontSize: 9.5,
              ),
            ),
          ),
        ),
      ],
    );
    if (!marked) return content;
    return Container(
      padding: const EdgeInsets.only(left: 8),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: theme.accentPrimary, width: 3),
        ),
      ),
      child: content,
    );
  }
}

/// A row of the lazy list: the lines irst to last (positions in the text);
/// more than one only for the cited block.
class _Row {
  const _Row(this.first, this.last);

  final int first;
  final int last;
}
