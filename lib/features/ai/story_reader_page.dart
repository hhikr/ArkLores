import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/gamedata/story_catalog.dart' show fallbackStoryLabel;
import '../../core/gamedata/story_coverage_models.dart'
    show StoryLineEntry, storyKindLabel;
import '../../core/library/library_labels.dart';
import '../../core/library/library_provider.dart';
import '../../core/library/library_queries.dart' show LibraryEntry;
import '../../core/userdata/library_ref.dart';
import '../../core/userdata/user_data_provider.dart';
import '../../core/userdata/user_data_store.dart'
    show UserDataStore, reanchorLine;
import '../../shared/l10n/l10n.dart';
import '../../shared/providers/theme_provider.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/smooth_page_route.dart';
import 'story_labels_provider.dart';

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
class StoryReaderPage extends ConsumerStatefulWidget {
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
  ConsumerState<StoryReaderPage> createState() => _StoryReaderPageState();
}

class _StoryReaderPageState extends ConsumerState<StoryReaderPage>
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
    unawaited(_saveProgress());
    _flash.dispose();
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

  /// First and last line on screen, by position in the list: lines are in
  /// one column, so their vertical positions are in order and a binary
  /// search finds the edges.
  (int, int)? _visibleRange() {
    final viewport = _scrollKey.currentContext?.findRenderObject();
    if (viewport is! RenderBox || !viewport.attached || _lines.isEmpty) {
      return null;
    }
    final top = viewport.localToGlobal(Offset.zero).dy + 8;
    final bottom = viewport.localToGlobal(Offset(0, viewport.size.height)).dy;

    double? edge(int i, {required bool end}) {
      final box = _lineKeys[i]?.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.attached) return null;
      return box.localToGlobal(Offset(0, end ? box.size.height : 0)).dy;
    }

    // First line whose bottom edge is below the top of the viewport.
    var lo = 0, hi = _lines.length - 1;
    while (lo < hi) {
      final mid = (lo + hi) ~/ 2;
      final y = edge(mid, end: true);
      if (y == null) return null;
      if (y > top) {
        hi = mid;
      } else {
        lo = mid + 1;
      }
    }
    final first = lo;
    // Last line whose top edge is above the bottom of the viewport.
    lo = first;
    hi = _lines.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) ~/ 2;
      final y = edge(mid, end: false);
      if (y == null) return null;
      if (y < bottom) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return (first, lo);
  }

  Future<void> _saveProgress() async {
    final store = _store;
    final range = _visibleRange();
    if (store == null || range == null) return;
    final first = _lines[range.$1];
    final last = _lines[range.$2];
    try {
      await store.updateProgress(
        LibraryRef.story(widget.storyId),
        lineIndex: first.lineIndex,
        snippet: first.content,
        totalLines: _lines.length,
        reached: last.lineIndex,
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

  Future<void> _jumpToTarget() async {
    final target =
        _cited ? _targetKey.currentContext : _resumeKey()?.currentContext;
    if (target == null || !mounted) return;
    await Scrollable.ensureVisible(
      target,
      alignment: _cited ? 0.25 : 0.08,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
    if (mounted && _cited) _flash.forward(from: 0);
  }

  GlobalKey? _resumeKey() {
    final at = _resume;
    if (at == null) return null;
    final i = _lines.indexWhere((l) => l.lineIndex == at);
    return i < 0 ? null : _keyOf(i);
  }

  void _scrollToTarget() {
    if (_scrolled) return;
    _scrolled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (_cited || _resume != null) await _jumpToTarget();
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
    final lines = ref.watch(storyFullLinesProvider(widget.storyId));
    final canJump = _cited || _resume != null;

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
      body: lines.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => _unavailable(theme),
        data: (lines) {
          if (lines.isEmpty) return _unavailable(theme);
          _anchor(lines);
          _recordLater(lines);
          _scrollToTarget();
          final range = !_cited
              ? null
              : _start == _stop
                  ? context.t.aiCitationLine(_start! + 1)
                  : context.t.aiCitationLines(_start! + 1, _stop! + 1);
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
                child: SingleChildScrollView(
                  key: const ValueKey('story-reader-scroll'),
                  padding: const EdgeInsets.fromLTRB(6, 4, 6, 40),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _header(
                        theme,
                        collection,
                        chapter,
                        range,
                        entry?.synopsis,
                      ),
                      ..._body(theme, lines),
                      _end(theme),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
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
                      synopsis.trim(),
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

  /// The lines, with the cited ones grouped into one highlighted block.
  List<Widget> _body(AppThemeTokens theme, List<StoryLineEntry> lines) {
    final out = <Widget>[];
    final cited = <Widget>[];
    String? previousSpeaker;
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final speaker = (line.speaker ?? '').trim();
      final showName = speaker.isNotEmpty && speaker != previousSpeaker;
      final gap = speaker != previousSpeaker ? 10.0 : 2.0;
      previousSpeaker = speaker;
      final isResume = !_cited && line.lineIndex == _resume;
      final row = Container(
        key: _keyOf(i),
        child: _line(
          theme,
          line,
          speaker: speaker,
          showName: showName,
          marked: isResume,
        ),
      );
      if (_isTarget(line.lineIndex)) {
        if (cited.isNotEmpty) cited.add(SizedBox(height: gap));
        cited.add(
          KeyedSubtree(
            key: ValueKey('story-line-target-${line.lineIndex}'),
            child: row,
          ),
        );
        continue;
      }
      if (cited.isNotEmpty) {
        out
          ..add(const SizedBox(height: 8))
          ..add(_citedBlock(theme, List.of(cited)))
          ..add(const SizedBox(height: 8));
        cited.clear();
      } else if (out.isNotEmpty) {
        out.add(SizedBox(height: gap));
      }
      out.add(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: isResume
              ? KeyedSubtree(
                  key: ValueKey('story-line-resume-${line.lineIndex}'),
                  child: row,
                )
              : row,
        ),
      );
    }
    if (cited.isNotEmpty) {
      out
        ..add(const SizedBox(height: 8))
        ..add(_citedBlock(theme, cited));
    }
    return out;
  }

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

  Widget _line(
    AppThemeTokens theme,
    StoryLineEntry line, {
    required String speaker,
    required bool showName,
    bool marked = false,
  }) {
    final narration = speaker.isEmpty;
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
              if (storyKindLabel(line.kind) != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    storyKindLabel(line.kind)!,
                    style: theme.bodyFont.copyWith(
                      color: theme.textMuted,
                      fontSize: 10.5,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
              Text(
                line.content,
                style: theme.bodyFont.copyWith(
                  color: narration ? theme.textSecondary : theme.textPrimary,
                  fontStyle: narration ? FontStyle.italic : FontStyle.normal,
                  fontSize: narration ? 14 : 15,
                  height: 1.6,
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
              top: showName ? 20 : (storyKindLabel(line.kind) != null ? 18 : 4),
            ),
            child: Text(
              '${line.lineIndex + 1}',
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
