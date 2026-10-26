import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/gamedata/game.dart';
import '../../core/gamedata/story_catalog.dart' show fallbackStoryLabel;
import '../../core/gamedata/story_coverage_models.dart'
    show StoryLineEntry, storyKindLabel;
import '../../core/gamedata/story_vectors.dart'
    show
        headingLineKinds,
        sectionLineKind,
        stageLineKind,
        summaryLineKind,
        unplacedLineKind;
import '../../core/library/library_labels.dart';
import '../../core/library/library_provider.dart';
import '../../core/library/library_queries.dart' show LibraryEntry;
import '../../core/library/placeholders.dart';
import '../../core/library/portrait_provider.dart';
import '../../core/userdata/library_ref.dart';
import '../../core/userdata/user_data_provider.dart';
import '../../core/userdata/user_data_store.dart'
    show UserDataStore, readingEndDwell, readingEndLines, reanchorLine;
import '../../shared/l10n/l10n.dart';
import '../../shared/providers/bars_provider.dart';
import '../../shared/providers/settings_provider.dart';
import '../../shared/providers/theme_provider.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/theme/motion.dart';
import '../../shared/widgets/dock_scaffold.dart';
import '../../shared/widgets/ef_widgets.dart';
import '../../shared/widgets/smooth_page_route.dart';
import '../../shared/widgets/theme_aware_card.dart';
import '../library/portrait_preview.dart';
import '../library/portrait_sheet.dart';
import '../library/portrait_speaker_name.dart';
import '../library/reading_text.dart'
    show FoldSection, ReadingText, readingStyle;
import 'story_find_sheet.dart';
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
class StoryReaderPage extends ConsumerWidget {
  const StoryReaderPage({
    super.key,
    required this.storyId,
    this.highlightStart,
    this.highlightEnd,
    this.resumeLine,
    this.snippet,
    this.portraitOrigin = PortraitOrigin.materials,
  });

  final String storyId;
  final int? highlightStart;
  final int? highlightEnd;

  /// The line the reader was at (history); highlighted lines win over it.
  final int? resumeLine;

  /// The text of the anchor line, to find it again in a changed story.
  final String? snippet;
  final PortraitOrigin portraitOrigin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reading = ref.watch(storyReadingProvider(storyId));
    final r = reading.valueOrNull;
    if (r == null) {
      final theme = ref.watch(themeProvider);
      return DockScaffold(
        title: '',
        backgroundColor: theme.bgPrimary,
        body: reading.isLoading
            ? const LoadingView()
            : Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: EmptyState(text: context.t.aiCitedLinesUnavailable),
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
      portraitSources: r.portraitSources,
      shift: r.offset,
      highlightStart:
          highlightStart == null ? null : highlightStart! + r.offset,
      highlightEnd: highlightEnd == null ? null : highlightEnd! + r.offset,
      resumeLine: resumeLine == null ? null : resumeLine! + r.offset,
      snippet: snippet,
      portraitOrigin: portraitOrigin,
    );
  }
}

class _StoryReaderBody extends ConsumerStatefulWidget {
  const _StoryReaderBody({
    super.key,
    required this.storyId,
    required this.text,
    this.portraitSources = const {},
    this.shift = 0,
    this.highlightStart,
    this.highlightEnd,
    this.resumeLine,
    this.snippet,
    this.portraitOrigin = PortraitOrigin.materials,
  });

  final String storyId;

  /// The whole text: the story, then the dialogue attached to it.
  final List<StoryLineEntry> text;
  final Map<int, ({String storyId, int lineIndex})> portraitSources;

  /// Where the story asked for begins in [text]; the numbers the reader shows
  /// for a cited range are its own.
  final int shift;
  final int? highlightStart;
  final int? highlightEnd;
  final int? resumeLine;
  final String? snippet;
  final PortraitOrigin portraitOrigin;

  @override
  ConsumerState<_StoryReaderBody> createState() => _StoryReaderPageState();
}

class _StoryReaderPageState extends ConsumerState<_StoryReaderBody>
    with SingleTickerProviderStateMixin {
  final GlobalKey _targetKey = GlobalKey();
  final GlobalKey _scrollKey = GlobalKey();

  /// Where the reader is: the first line on screen and the number of lines
  /// (shown by the title); null until the list is laid out.
  final ValueNotifier<(int, int)?> _progress = ValueNotifier(null);
  Timer? _progressTimer;

  /// The header (titles, description, synopsis), measured to re-anchor on it.
  final GlobalKey _headerKey = GlobalKey();
  final Map<int, GlobalKey> _lineKeys = {};
  final Map<int, GlobalKey> _speakerKeys = {};

  /// Whether a speaker's name opens the portrait card (an Arknights story
  /// and a knowledge base with the portrait tables).
  bool _speakersTappable = false;
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

  /// Positions of the section lines that follow one of the same kind.
  Set<int> _quietSections = const {};
  List<StoryLineEntry>? _preparedFor;
  bool _spoken = false;

  /// The text opens each part with the game's summary of it: the
  /// catalog's synopsis (the same summaries together) is not shown on top.
  bool _summarized = false;

  /// Positions of the part summaries the reader opened (the list is lazy:
  /// a summary scrolled away and back keeps its state).
  final Set<int> _openSummaries = {};

  /// Positions of the opened headings of conversations no data places
  /// (`unplaced`): what follows one is left out of the list until opened.
  final Set<int> _openUnplaced = {};
  String _nickname = '';

  /// The description of the Endfield mission this story is (or null).
  String? _intro;

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

  /// Where the pages that show reading progress get it from: told once,
  /// when the reader closes (see [_saveSoon]).
  late final ProviderContainer _container =
      ProviderScope.containerOf(context, listen: false);

  @override
  void initState() {
    super.initState();
    _container;
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _endTimer?.cancel();
    _progressTimer?.cancel();
    _scrubDone?.cancel();
    _dockAway.dispose();
    _progress.dispose();
    _scrub.dispose();
    final container = _container;
    unawaited(
      _saveProgress().whenComplete(() => invalidateReadingIn(container)),
    );
    _flash.dispose();
    _scroll.dispose();
    super.dispose();
  }

  GlobalKey _keyOf(int index) => _lineKeys.putIfAbsent(index, GlobalKey.new);

  bool get _cited => _start != null;

  bool _isTarget(int index) => _cited && index >= _start! && index <= _stop!;

  /// Finds the history anchor again in the current text (once).
  void _anchor(List<StoryLineEntry> lines) {
    if (_anchored) return;
    _anchored = true;
    _lines = lines;
    final snippet = widget.snippet;
    final line = widget.resumeLine;
    if (snippet == null || line == null || _cited) return;
    final found =
        reanchorLine([for (final l in lines) l.content], line, snippet);
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
    _summarized = lines.any((l) => l.kind == summaryLineKind);
    // A section names its kind where the kind changes; the next parts of
    // the same kind are set off by the rule alone.
    _quietSections = {};
    String? kind;
    for (final (i, l) in lines.indexed) {
      // (under a new step the first part names its kind again)
      if (headingLineKinds.contains(l.kind)) kind = null;
      if (l.kind != sectionLineKind) continue;
      if (l.content == kind) _quietSections.add(i);
      kind = l.content;
    }
    // A folded group opens when the line to show is in it.
    final at = _cited ? _start : _resume;
    final p = at == null ? -1 : lines.indexWhere((l) => l.lineIndex == at);
    if (p >= 0) {
      final h = _unplacedOver(lines, p);
      if (h != null) _openUnplaced.add(h);
    }
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
    final bottom = viewport.localToGlobal(Offset(0, viewport.size.height)).dy -
        _panelCover();
    int? first, last;
    // Keys of lines scrolled out of the lazy list are dropped (a line built
    // again gets a new one), so this looks at the lines near the screen, not
    // at every line read so far.
    _lineKeys.removeWhere((_, key) => key.currentContext == null);
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
    final atEnd = nearEnd && _endStayed;
    try {
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

  /// Shows where the reader is, at most every 120 ms while scrolling.
  void _showProgressSoon() {
    if (_scrubbing || (_progressTimer?.isActive ?? false)) return;
    _progressTimer = Timer(const Duration(milliseconds: 120), () {
      if (!mounted || _scrubbing) return;
      final range = _visibleRange();
      if (range != null) _progress.value = (range.$1, _lines.length);
    });
  }

  void _saveSoon() {
    _saveTimer?.cancel();
    // Only saved: the pages under the reader that show progress (the
    // library, a collection) are told when it closes. Told on every save,
    // they rebuilt whole under it each time the reader stopped scrolling,
    // a stall every few hundred ms.
    _saveTimer = Timer(const Duration(milliseconds: 400), _saveProgress);
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

  /// Anchors the list on the header where it stands on screen, so that what
  /// changes height in it (the synopsis opening) grows downward. Opened at a
  /// cited or resumed line the header is in the list built upward from the
  /// anchor, where an item that grows pushes its top up the screen.
  void _anchorOnHeader() {
    if (_center == 0) return;
    final view = _scrollKey.currentContext?.findRenderObject();
    final header = _headerKey.currentContext?.findRenderObject();
    if (view is! RenderBox || header is! RenderBox || !header.attached) return;
    final top = header.localToGlobal(Offset.zero, ancestor: view).dy;
    final height = view.size.height;
    if (height <= 0) return;
    if (_scroll.hasClients) _scroll.jumpTo(top < 0 ? -top : 0);
    setState(() {
      _center = 0;
      _centerAt = top < 0 ? 0 : (top / height).clamp(0.0, 1.0);
    });
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
      if (mounted) _showProgressSoon();
    });
  }

  // ─── Scrubbing ─────────────────────────────────────────────────

  final ValueNotifier<bool> _scrub = ValueNotifier(false);
  int? _scrubRow;
  bool _scrubBusy = false;
  int? _scrubTarget;

  /// Whether the floating controls are out of the way, and what moves them.
  final ValueNotifier<bool> _dockAway = ValueNotifier(false);
  late final BarsFollower _dock = BarsFollower(away: _dockAway);

  void _scrubStart() {
    if (_lines.isEmpty || _rows.isEmpty) return;
    _dock.show(ref);
    setState(() => _scrub.value = !_scrub.value);
    _scrubRow = null;
  }

  /// While the finger is on the slider the line it points at is where the
  /// reader is: the count from the screen (the first line of the row shown,
  /// a line or two off) would pull the thumb back under the finger.
  bool _scrubbing = false;
  Timer? _scrubDone;

  void _scrubMove(double value) {
    _scrubbing = true;
    _scrubDone?.cancel();
    final p = value.round();
    _scrubTarget = p;
    _progress.value = (p, _lines.length);
    if (_scrubBusy) return;
    _scrubBusy = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrubBusy = false;
      final at = _scrubTarget;
      if (at != null && mounted) _showLine(at);
    });
  }

  void _scrubEnd(double value) {
    _scrubMove(value);
    // Past the last jump's own frames (its layout and the scroll reset):
    // the thumb stays where it was let go until the text is scrolled.
    _scrubDone?.cancel();
    _scrubDone = Timer(Motion.wipe, () => _scrubbing = false);
    _saveSoon();
  }

  /// The progress panel, measured to tell how much of the text it covers.
  final GlobalKey _scrubPanelKey = GlobalKey();

  /// How far up the text the open progress panel, or else the controls,
  /// reach from the bottom of the view: where the reader is counts above.
  double _panelCover() {
    if (!_scrub.value) return _dockAway.value ? 0 : floatingDockRoom(context);
    final view = _scrollKey.currentContext?.findRenderObject();
    final panel = _scrubPanelKey.currentContext?.findRenderObject();
    if (view is! RenderBox || panel is! RenderBox || !panel.attached) {
      return 0;
    }
    final top = panel.localToGlobal(Offset.zero, ancestor: view).dy;
    return (view.size.height - top).clamp(0.0, view.size.height);
  }

  /// Anchors the list on the row holding line [p], at the top of the view
  /// (the panel is at the bottom, by the thumb).
  void _showLine(int p) {
    final r = _rows.indexWhere((row) => row.last >= p);
    final row = r < 0 ? _rows.length - 1 : r;
    if (row == _scrubRow) return;
    _scrubRow = row;
    setState(() {
      _center = row + 1;
      _centerAt = 0;
    });
    // Changing the upward sliver can preserve the old visible item. Reset
    // once after layout so consecutive jumps reach the requested row.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scrubRow == row && _scroll.hasClients) {
        _scroll.jumpTo(0);
        _showProgressSoon();
      }
    });
  }

  /// The title of the step or group line [p] is under, if any.
  String? _headingOver(int p) {
    for (var i = p; i >= 0; i--) {
      if (headingLineKinds.contains(_lines[i].kind)) {
        final title = _lines[i].content.trim();
        return title.isEmpty ? null : title;
      }
    }
    return null;
  }

  /// One line of the scrub panel at a fixed height: the text on one line
  /// (its breaks as spaces), the strut forced, the box sized to it.
  Widget _panelLine(String text, TextStyle style) {
    final size = style.fontSize ?? 14;
    return SizedBox(
      height: size * 1.5,
      child: Text(
        text.replaceAll('\n', ' '),
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
        style: style.copyWith(height: 1.5),
        strutStyle: StrutStyle(
          fontSize: size,
          height: 1.5,
          forceStrutHeight: true,
        ),
      ),
    );
  }

  /// The current reading position and the line being previewed.
  Widget _scrubPanel(AppThemeTokens theme, int p) {
    final n = _lines.length;
    final share = n < 2 ? 0.0 : p / (n - 1);
    final line = _lines[p];
    final speaker = (line.speaker ?? '').trim();
    final heading = _headingOver(p);
    return Container(
      key: const ValueKey('story-reader-scrub'),
      padding: const EdgeInsets.fromLTRB(_scrubGutter, 12, _scrubGutter, 12),
      // A floating plate like the controls under it; the slider at its
      // foot, by the thumb.
      decoration: BoxDecoration(
        color: theme.cardSurface,
        border: Border.all(color: theme.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '${p + 1}',
                style: theme.ui(22, weight: 700, color: theme.textPrimary),
              ),
              Text(
                ' / $n',
                style: theme.field(color: theme.textSecondary),
              ),
              const Spacer(),
              Text(
                '${(share * 100).round()}%',
                style: theme.field(color: theme.textSecondary),
              ),
            ],
          ),
          // Every line of the panel keeps one height whatever it holds (a
          // long line or a short one, Latin or Chinese, a step's title or
          // none), so the slider under it stays still while it is dragged.
          if (_lines.any((l) => headingLineKinds.contains(l.kind)))
            _panelLine(
              heading ?? '',
              theme.ui(13, weight: 700, color: theme.textSecondary),
            ),
          const SizedBox(height: 4),
          _panelLine(
            speaker.isEmpty ? line.content : '$speaker：${line.content}',
            theme.ui(14, color: theme.textPrimary),
          ),
          const SizedBox(height: 12),
          AppSlider(
            key: const ValueKey('story-reader-slider'),
            value: p.toDouble(),
            max: math.max(1, n - 1).toDouble(),
            semanticValue: '${p + 1} / $n',
            onChanged: n < 2 ? null : _scrubMove,
            onChangeEnd: _scrubEnd,
          ),
        ],
      ),
    );
  }

  /// Find in this text; the line picked opens marked, as a cited line.
  Future<void> _find(AppThemeTokens theme) async {
    final line = await showStoryFind(
      context,
      lines: widget.text,
      theme: theme,
      nickname: _nickname,
    );
    if (line == null || !mounted) return;
    await Navigator.of(context).pushReplacement(
      smoothPageRoute<void>(
        frosted: widget.portraitOrigin == PortraitOrigin.materials,
        builder: (_) => StoryReaderPage(
          storyId: widget.storyId,
          portraitOrigin: widget.portraitOrigin,
          highlightStart: line,
          highlightEnd: line,
        ),
      ),
    );
  }

  // ─── Build ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider);
    // Watched here, not in the list's item builder (which runs at layout).
    _speakersTappable = gameOfId(widget.storyId) == Game.arknights &&
        ref.watch(hasPortraitIndexProvider).valueOrNull == true;
    final entry =
        ref.watch(storyCatalogEntryProvider(widget.storyId)).valueOrNull;
    final fallback = fallbackStoryLabel(widget.storyId);
    final cut = fallback.indexOf(' · ');
    final collection = entry?.collectionLabel ??
        (cut < 0 ? fallback : fallback.substring(0, cut));
    final chapter =
        entry?.chapterLabel ?? (cut < 0 ? '' : fallback.substring(cut + 3));
    final canJump = _cited || _resume != null;
    // An Endfield mission's own description heads its story: the mission
    // opens straight in the reader, without a page that would show it.
    _intro = entry != null && gameOfId(entry.collectionId) == Game.endfield
        ? ref.watch(collectionIntroProvider(entry.collectionId)).valueOrNull
        : null;

    _nickname = ref.watch(nicknameProvider);
    final body = _body(theme, collection, chapter, entry?.synopsis);
    final panel = _panel(theme);
    return PopScope(
      canPop: !_scrub.value,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _scrub.value) setState(() => _scrub.value = false);
      },
      // The controls float at the bottom, under the thumb, and slide away
      // while the text is read on (back with a drag back or a tap on the
      // text); the progress panel opens over them.
      child: ValueListenableBuilder<bool>(
        valueListenable: _dockAway,
        child: body,
        builder: (context, away, body) => DockScaffold(
          backgroundColor: theme.bgPrimary,
          title: chapter.isNotEmpty ? chapter : collection,
          onTitleTap: widget.text.isEmpty ? null : _scrubStart,
          open: _scrub.value,
          away: away && !_scrub.value,
          panel: panel,
          status: ValueListenableBuilder<(int, int)?>(
            valueListenable: _progress,
            builder: (context, p, _) => p == null
                ? const SizedBox.shrink()
                : Text(
                    '${p.$1 + 1} / ${p.$2}',
                    key: const ValueKey('story-reader-progress'),
                    maxLines: 1,
                    style: theme.field(size: 12, color: theme.textSecondary),
                  ),
          ),
          // How far in: a line along the foot of the title's plate.
          progress: ValueListenableBuilder<(int, int)?>(
            valueListenable: _progress,
            builder: (context, p, _) => p == null || p.$2 == 0
                ? const SizedBox.shrink()
                : FractionallySizedBox(
                    key: const ValueKey('story-reader-progress-bar'),
                    alignment: Alignment.centerLeft,
                    widthFactor: ((p.$1 + 1) / p.$2).clamp(0.0, 1.0),
                    child: SizedBox(
                      height: 2,
                      child: ColoredBox(color: theme.trace),
                    ),
                  ),
          ),
          actions: [
            if (widget.text.isNotEmpty)
              DockAction(
                key: const ValueKey('story-reader-find'),
                tooltip: context.t.storyReaderFindHint,
                onPressed: () => _find(theme),
                icon: Icons.search_sharp,
              ),
            if (canJump)
              DockAction(
                key: const ValueKey('story-reader-jump'),
                tooltip: context.t.aiStoryReaderJumpBack,
                onPressed: _jumpToTarget,
                icon: Icons.my_location_sharp,
              ),
          ],
          body: body!,
        ),
      ),
    );
  }

  Widget _body(
    AppThemeTokens theme,
    String collection,
    String chapter,
    String? synopsis,
  ) =>
      Builder(
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
          // A tap on the text (not on a name or a button): the panel
          // shuts; with it shut, the controls come back or go away.
          return GestureDetector(
            key: const ValueKey('story-reader-blank-tap'),
            behavior: HitTestBehavior.translucent,
            onTap: () {
              if (_scrub.value) {
                setState(() => _scrub.value = false);
              } else {
                _dock.tapped(ref, canHide: true);
              }
            },
            child: _text(theme, collection, chapter, range, synopsis),
          );
        },
      );

  /// The progress panel over the controls, kept open while the reader
  /// scrolls or moves the slider; it grows up from them.
  Widget _panel(AppThemeTokens theme) => ValueListenableBuilder<bool>(
        valueListenable: _scrub,
        builder: (context, p, _) => AnimatedSwitcher(
          duration: Motion.of(context, Motion.row),
          reverseDuration: Motion.of(context, Motion.press),
          switchInCurve: Motion.snap,
          switchOutCurve: Motion.mech,
          transitionBuilder: (child, animation) => SizeTransition(
            sizeFactor: animation,
            alignment: Alignment.bottomCenter,
            child: child,
          ),
          child: !p
              ? const SizedBox(width: double.infinity)
              : ValueListenableBuilder<(int, int)?>(
                  valueListenable: _progress,
                  builder: (context, progress, _) => KeyedSubtree(
                    key: _scrubPanelKey,
                    child: _scrubPanel(
                      theme,
                      (progress?.$1 ?? 0).clamp(0, _lines.length - 1),
                    ),
                  ),
                ),
        ),
      );

  /// The text: two lazy lists that meet at the anchor item.
  Widget _text(
    AppThemeTokens theme,
    String collection,
    String chapter,
    String? range,
    String? synopsis,
  ) =>
      NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n is ScrollStartNotification && n.dragDetails != null) {
            _scrubRow = null;
          }
          if (n is ScrollUpdateNotification) {
            _showProgressSoon();
            // The reader's own drags move the controls; at either end of
            // the text they are back.
            final m = n.metrics;
            final atEnd = m.pixels <= m.minScrollExtent + 1 ||
                m.pixels >= m.maxScrollExtent - 1;
            if ((n.dragDetails != null || atEnd) && !_scrub.value) {
              _dock.moved(ref, n.scrollDelta ?? 0, atTop: atEnd);
            }
          }
          if (n is ScrollEndNotification) {
            _saveSoon();
            _showProgressSoon();
          }
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
              // Laid out: the screen and about half a screen either
              // way; the rest as it scrolls near.
              scrollCacheExtent: const ScrollCacheExtent.pixels(480),
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
                        synopsis,
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
                        synopsis,
                      ),
                      childCount: _rows.length + 2 - _center,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

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
        padding: EdgeInsets.only(
          bottom: 24 + floatingDockRoom(context),
        ),
        child: _end(theme),
      );
    }
    return _rowWidget(theme, i - 1);
  }

  Widget _chip(AppThemeTokens theme, String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        color: theme.accentPrimary,
        child:
            Text(text, style: theme.ui(13, weight: 700, color: theme.onAccent)),
      );

  Widget _header(
    AppThemeTokens theme,
    String collection,
    String chapter,
    String? range,
    String? synopsis,
  ) =>
      Padding(
        key: _headerKey,
        padding: const EdgeInsets.fromLTRB(10, 4, 10, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_moved)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: NoticeBox(context.t.aiStoryReaderMoved),
              ),
            Text(
              collection,
              style: theme.ui(14, weight: 700, color: theme.textSecondary),
            ),
            if (chapter.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(chapter, style: theme.heading(24)),
            ],
            const SizedBox(height: 10),
            const TriStrip(),
            if (range != null) ...[
              const SizedBox(height: 10),
              _chip(theme, '${context.t.aiStoryReaderTitle} / $range'),
            ] else if (_resume != null) ...[
              const SizedBox(height: 10),
              _chip(theme, context.t.storyReaderResumed(_resume! + 1)),
            ],
            // The mission's description: what the game shows before it.
            if (_intro != null && _intro!.trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              ReadingText(
                _intro!,
                key: const ValueKey('story-reader-intro'),
                size: 15.5,
              ),
            ],
            // The official synopsis tells the whole story (it is what the
            // game shows when a story is skipped): folded until asked for.
            if (synopsis != null &&
                synopsis.trim().isNotEmpty &&
                !_summarized) ...[
              const SizedBox(height: 12),
              FoldSection(
                key: const ValueKey('story-reader-synopsis'),
                title: context.t.storyReaderSynopsis,
                initiallyOpen: false,
                onToggle: (_) => _anchorOnHeader(),
                child: ReadingText(synopsis.trim(), size: 15.5),
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
      // (a folded group: its heading only)
      if (lines[i].kind == unplacedLineKind && !_openUnplaced.contains(i)) {
        rows.add(_Row(i, i));
        i++;
        while (i < lines.length && !headingLineKinds.contains(lines[i].kind)) {
          i++;
        }
        continue;
      }
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
      // The start of one conversation of a merged story (an Endfield
      // mission): a rule with its kind.
      if (line.kind == sectionLineKind) {
        final quiet = _quietSections.contains(row.first);
        return Padding(
          key: _keyOf(row.first),
          padding:
              EdgeInsets.fromLTRB(10, first ? 4 : (quiet ? 22 : 34), 10, 4),
          child: _ruled(
            theme,
            quiet ? null : line.content,
            key: ValueKey('story-reader-section-${line.lineIndex}'),
          ),
        );
      }
      if (line.kind == summaryLineKind) {
        return Padding(
          key: _keyOf(row.first),
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 0),
          child: _summary(row.first),
        );
      }
      // A story laid out along its mission's steps: a step's goal, or the
      // name of a mission played inside a step.
      if (headingLineKinds.contains(line.kind)) {
        return Padding(
          key: _keyOf(row.first),
          padding: EdgeInsets.fromLTRB(10, first ? 4 : 30, 10, 0),
          child: line.kind == unplacedLineKind
              ? _unplaced(theme, row.first)
              : _heading(theme, line),
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
        padding:
            EdgeInsets.fromLTRB(10, first ? 0 : _gapBefore(row.first), 10, 0),
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
      if (_lines[p].kind == sectionLineKind) {
        inside.add(
          Container(
            key: _keyOf(p),
            child: _ruled(
              theme,
              _quietSections.contains(p) ? null : _lines[p].content,
              key: ValueKey('story-reader-section-${_lines[p].lineIndex}'),
            ),
          ),
        );
        continue;
      }
      if (_lines[p].kind == summaryLineKind) {
        inside.add(Container(key: _keyOf(p), child: _summary(p)));
        continue;
      }
      if (headingLineKinds.contains(_lines[p].kind)) {
        inside
            .add(Container(key: _keyOf(p), child: _heading(theme, _lines[p])));
        continue;
      }
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

  /// The game's summary of the part it opens: folded like the official
  /// synopsis (it tells what the part is about before it is read).
  Widget _summary(int p) => FoldSection(
        key: ValueKey('story-reader-summary-${_lines[p].lineIndex}'),
        title: context.t.storyReaderSynopsis,
        plain: true,
        initiallyOpen: _openSummaries.contains(p),
        onToggle: (open) =>
            open ? _openSummaries.add(p) : _openSummaries.remove(p),
        child: ReadingText(_lines[p].content.trim(), size: 15.5),
      );

  /// The heading of a folded group over [p] (the nearest heading above it,
  /// when that one is `unplaced`), or null.
  int? _unplacedOver(List<StoryLineEntry> lines, int p) {
    for (var i = p; i >= 0; i--) {
      if (headingLineKinds.contains(lines[i].kind)) {
        return lines[i].kind == unplacedLineKind ? i : null;
      }
    }
    return null;
  }

  /// The heading of the conversations no data places: tapped, the group
  /// opens or folds (anchored on the heading, so it stays where it is).
  Widget _unplaced(AppThemeTokens theme, int p) {
    final open = _openUnplaced.contains(p);
    final count = _lines
        .skip(p + 1)
        .takeWhile((l) => !headingLineKinds.contains(l.kind))
        .where((l) => l.kind == sectionLineKind)
        .length;
    return Semantics(
      button: true,
      expanded: open,
      child: PressRow(
        onTap: () {
          final view = _scrollKey.currentContext?.findRenderObject();
          final box = _keyOf(p).currentContext?.findRenderObject();
          var at = 0.1;
          if (view is RenderBox &&
              box is RenderBox &&
              box.attached &&
              view.size.height > 0) {
            at = (box.localToGlobal(Offset.zero, ancestor: view).dy /
                    view.size.height)
                .clamp(0.0, 1.0);
          }
          if (_scroll.hasClients) _scroll.jumpTo(0);
          setState(() {
            open ? _openUnplaced.remove(p) : _openUnplaced.add(p);
            _rows = _makeRows(_lines);
            _center = _rows.indexWhere((r) => r.first == p) + 1;
            _centerAt = at;
          });
        },
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Row(
            key: ValueKey('story-reader-unplaced-${_lines[p].lineIndex}'),
            children: [
              Container(
                width: 4,
                height: 18,
                color: open ? theme.trace : theme.cardBorder,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${_lines[p].content}（$count）',
                  style: theme.ui(15, weight: 700, color: theme.textSecondary),
                ),
              ),
              Icon(
                open ? Icons.expand_less_sharp : Icons.expand_more_sharp,
                size: 22,
                color: theme.textPrimary,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// A step's goal (a bar and the text), or the name of a mission played
  /// inside a step (larger, a longer bar).
  Widget _heading(AppThemeTokens theme, StoryLineEntry line) {
    final stage = line.kind == stageLineKind;
    return Row(
      key: ValueKey('story-reader-${line.kind}-${line.lineIndex}'),
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(width: 4, height: stage ? 22 : 16, color: theme.trace),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            line.content,
            style: theme.ui(
              stage ? 17 : 14.5,
              weight: 700,
              color: stage ? theme.textPrimary : theme.textSecondary,
            ),
          ),
        ),
      ],
    );
  }

  /// The heading of dialogue played in the battle, attached to the story
  /// (`n/total` is the part's place among the parts).
  Widget _divider(AppThemeTokens theme, String place) {
    final parts = place.split('/');
    final many = parts.length == 2 && parts[1] != '1';
    return _ruled(
      theme,
      many
          ? '${context.t.storyReaderBattleDialogue} ${parts[0]}'
          : context.t.storyReaderBattleDialogue,
      key: const ValueKey('story-reader-battle-dialogue'),
    );
  }

  /// A label between two rules: where a part of the text begins. Without a
  /// label, a short rule (the next part of the same kind).
  Widget _ruled(AppThemeTokens theme, String? label, {required Key key}) =>
      label == null
          ? Center(
              key: key,
              child: SizedBox(
                width: 48,
                child: Divider(color: theme.divider, thickness: 1),
              ),
            )
          : Row(
              key: key,
              children: [
                Expanded(child: Divider(color: theme.divider, endIndent: 12)),
                Text(
                  label,
                  style: theme.ui(13.5, weight: 700, color: theme.textPrimary),
                ),
                Expanded(child: Divider(color: theme.divider, indent: 12)),
              ],
            );

  String _speakerOf(int p) => (_lines[p].speaker ?? '').trim();

  bool _showName(int p) =>
      _speakerOf(p).isNotEmpty &&
      (p == 0 || _speakerOf(p) != _speakerOf(p - 1));

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
              alpha: (theme.isDark ? 0.08 : 0.14) + 0.22 * _strength.value,
            ),
            border: Border(left: BorderSide(color: theme.trace, width: 3)),
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
                style: theme.ui(14, weight: 700, color: theme.textSecondary),
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
                    Icons.chevron_left_sharp,
                    key: const ValueKey('story-reader-previous'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _neighbour(
                    theme,
                    place.next,
                    context.t.storyReaderNext,
                    Icons.chevron_right_sharp,
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
    return ThemeAwareCard(
      key: key,
      padding: const EdgeInsets.fromLTRB(12, 14, 16, 12),
      onTap: () => Navigator.of(context).pushReplacement(
        smoothPageRoute<void>(
          frosted: widget.portraitOrigin == PortraitOrigin.materials,
          builder: (_) => StoryReaderPage(
            storyId: target.rawId!,
            portraitOrigin: widget.portraitOrigin,
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment:
            trailingIcon ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!trailingIcon) Icon(icon, color: theme.textPrimary, size: 22),
          Flexible(
            child: Column(
              crossAxisAlignment: trailingIcon
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.ui(13, weight: 600, color: theme.textSecondary),
                ),
                Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.heading(15),
                ),
              ],
            ),
          ),
          if (trailingIcon) Icon(icon, color: theme.textPrimary, size: 22),
        ],
      ),
    );
  }

  Widget _unavailable(AppThemeTokens theme) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: EmptyState(text: context.t.aiCitedLinesUnavailable),
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

  Widget _speakerName(AppThemeTokens theme, StoryLineEntry line, String name) {
    final style = theme.ui(14, weight: 700, color: theme.textSecondary);
    if (!_speakersTappable) return Text(name, style: style);
    return PortraitSpeakerName(
      key: _speakerKeys.putIfAbsent(line.lineIndex, GlobalKey.new),
      name: name,
      style: style,
      onTap: () {
        showPortraitPreview(
          context,
          anchorContext: _speakerKeys[line.lineIndex]?.currentContext,
          speaker: name,
          spriteFuture: ref.read(
            spriteOfLineProvider(
              widget.portraitSources[line.lineIndex] ??
                  (storyId: widget.storyId, lineIndex: line.lineIndex),
            ).future,
          ),
          fromLine: true,
          origin: widget.portraitOrigin,
        );
      },
    );
  }

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
    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (showName)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: _speakerName(theme, line, speaker),
                ),
              if (kindTag != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    kindTag,
                    style: theme.label(color: theme.textMuted),
                  ),
                ),
              Text(
                withPlaceholders(line.content, nickname),
                style: readingStyle(
                  theme,
                  size: narration && !plain ? 15.5 : 16.5,
                  color: narration && !plain
                      ? theme.textSecondary
                      : theme.textPrimary,
                ).copyWith(
                  fontStyle:
                      narration && !plain ? FontStyle.italic : FontStyle.normal,
                  height: 1.8,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 32,
          child: Padding(
            padding: EdgeInsets.only(
              top: showName ? 24 : (kindTag != null ? 20 : 6),
            ),
            child: Text(
              '${(line.shownIndex ?? line.lineIndex) + 1}',
              textAlign: TextAlign.right,
              style: theme.field(color: theme.textMuted, size: 11.5),
            ),
          ),
        ),
      ],
    );
    final target = _speakerKeys[line.lineIndex];
    final content = showName && target != null
        ? PortraitSpeakerTarget(target: target, child: row)
        : row;
    if (!marked) return content;
    // The rail stands in the margin, so the marked line stays in line with
    // the others.
    return Stack(
      clipBehavior: Clip.none,
      children: [
        content,
        Positioned(
          left: -8,
          top: 0,
          bottom: 0,
          width: traceRailWidth,
          child: ColoredBox(color: theme.trace),
        ),
      ],
    );
  }
}

/// A row of the lazy list: the lines irst to last (positions in the text);
/// more than one only for the cited block.
/// The scrub track's side margins; the finger's drag is measured against
/// the width between them.
const double _scrubGutter = 16;

class _Row {
  const _Row(this.first, this.last);

  final int first;
  final int last;
}
