import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/gamedata/story_catalog.dart' show fallbackStoryLabel;
import '../../core/gamedata/story_coverage_models.dart' show StoryLineEntry;
import '../../core/userdata/library_ref.dart';
import '../../core/userdata/user_data_provider.dart';
import '../../core/userdata/user_data_store.dart' show reanchorLine;
import '../../shared/l10n/l10n.dart';
import '../../shared/providers/theme_provider.dart';
import '../../shared/theme/app_theme.dart';
import 'story_labels_provider.dart';

/// R17b: the whole text of one story, opened from a citation. Scrolls to the
/// cited lines ([highlightStart]–[highlightEnd], 0-based line_index),
/// flashes them twice, then keeps them highlighted.
///
/// R18b layout: the text starts at the page gutter (line numbers sit small
/// on the right), a speaker's name is shown only when the speaker changes,
/// the cited lines are one rounded block, and the app bar can jump back to
/// them.
class StoryReaderPage extends ConsumerStatefulWidget {
  const StoryReaderPage({
    super.key,
    required this.storyId,
    required this.highlightStart,
    required this.highlightEnd,
    this.snippet,
  });

  final String storyId;
  final int highlightStart;
  final int highlightEnd;

  /// Set when opened from the reading history: the text of the anchor line
  /// ([highlightStart]), used to find it again if the story changed.
  final String? snippet;

  @override
  ConsumerState<StoryReaderPage> createState() => _StoryReaderPageState();
}

class _StoryReaderPageState extends ConsumerState<StoryReaderPage>
    with SingleTickerProviderStateMixin {
  final GlobalKey _targetKey = GlobalKey();
  bool _scrolled = false;
  bool _recorded = false;

  /// The highlighted range; moved by [_anchor] when the story changed.
  late int _start = widget.highlightStart;
  late int _stop = widget.highlightEnd;
  bool _anchored = false;
  bool _moved = false;

  /// Finds the history anchor again in the current text (once).
  void _anchor(List<StoryLineEntry> lines) {
    if (_anchored) return;
    _anchored = true;
    final snippet = widget.snippet;
    if (snippet == null) return;
    final found = reanchorLine(
      [for (final l in lines) l.content],
      widget.highlightStart,
      snippet,
    );
    if (found == null) return;
    _start = _stop = lines[found.index].lineIndex;
    _moved = !found.exact;
  }

  /// Writes this visit to the reading history (once, after the text loaded;
  /// the history is a convenience, so a failure is ignored).
  void _recordLater(List<StoryLineEntry> lines) {
    if (_recorded) return;
    _recorded = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => _record(lines));
  }

  Future<void> _record(List<StoryLineEntry> lines) async {
    try {
      final entry = await ref.read(storyCatalogEntryProvider(widget.storyId).future);
      final title = entry?.label ?? fallbackStoryLabel(widget.storyId);
      final store = await ref.read(userDataStoreProvider.future);
      final anchor = lines.firstWhere(
        (l) => l.lineIndex == _start,
        orElse: () => lines.first,
      );
      await store.recordOpen(
        LibraryRef.story(widget.storyId),
        title: title,
        lineIndex: anchor.lineIndex,
        snippet: anchor.content,
      );
      ref.invalidate(recentReadingProvider);
    } catch (_) {}
  }

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
    _flash.dispose();
    super.dispose();
  }

  bool _isTarget(int index) =>
      index >= _start && index <= _stop;

  Future<void> _jumpToTarget() async {
    final target = _targetKey.currentContext;
    if (target == null || !mounted) return;
    await Scrollable.ensureVisible(
      target,
      alignment: 0.25,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
    if (mounted) _flash.forward(from: 0);
  }

  void _scrollToTarget() {
    if (_scrolled) return;
    _scrolled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToTarget());
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider);
    final entry = ref.watch(storyCatalogEntryProvider(widget.storyId)).valueOrNull;
    final fallback = fallbackStoryLabel(widget.storyId);
    final cut = fallback.indexOf(' · ');
    final collection = entry?.collectionLabel ??
        (cut < 0 ? fallback : fallback.substring(0, cut));
    final chapter =
        entry?.chapterLabel ?? (cut < 0 ? '' : fallback.substring(cut + 3));
    final lines = ref.watch(storyFullLinesProvider(widget.storyId));

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
          final range = _start == _stop
              ? context.t.aiCitationLine(_start + 1)
              : context.t.aiCitationLines(_start + 1, _stop + 1);
          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: SingleChildScrollView(
                key: const ValueKey('story-reader-scroll'),
                padding: const EdgeInsets.fromLTRB(6, 4, 6, 40),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_moved)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(10, 4, 10, 8),
                        child: Text(
                          context.t.aiStoryReaderMoved,
                          style: theme.bodyFont.copyWith(
                            color: theme.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    _header(theme, collection, chapter, range),
                    ..._body(theme, lines),
                    _end(theme),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _header(
    AppThemeTokens theme,
    String collection,
    String chapter,
    String range,
  ) =>
      Padding(
        padding: const EdgeInsets.fromLTRB(10, 4, 10, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: theme.accentPrimary.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '${context.t.aiStoryReaderTitle} · $range',
                style: theme.bodyFont.copyWith(
                  color: theme.accentText,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
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
    for (final line in lines) {
      final speaker = (line.speaker ?? '').trim();
      final showName = speaker.isNotEmpty && speaker != previousSpeaker;
      final gap = speaker != previousSpeaker ? 10.0 : 2.0;
      previousSpeaker = speaker;
      final row = _line(theme, line, speaker: speaker, showName: showName);
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
      out.add(Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: row,
      ),);
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

  Widget _end(AppThemeTokens theme) => Padding(
        padding: const EdgeInsets.only(top: 28),
        child: Row(
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
      );

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
  }) {
    final narration = speaker.isEmpty;
    return Row(
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
            padding: EdgeInsets.only(top: showName ? 20 : 4),
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
  }
}
