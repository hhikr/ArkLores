import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/gamedata/story_catalog.dart' show fallbackStoryLabel;
import '../../core/gamedata/story_coverage_models.dart' show StoryLineEntry;
import '../../shared/l10n/l10n.dart';
import '../../shared/providers/theme_provider.dart';
import '../../shared/theme/app_theme.dart';
import 'story_labels_provider.dart';

/// R17b: the whole text of one story, opened from a citation. Scrolls to the
/// cited lines ([highlightStart]–[highlightEnd], 0-based line_index),
/// flashes them twice, then keeps them highlighted.
class StoryReaderPage extends ConsumerStatefulWidget {
  const StoryReaderPage({
    super.key,
    required this.storyId,
    required this.highlightStart,
    required this.highlightEnd,
  });

  final String storyId;
  final int highlightStart;
  final int highlightEnd;

  @override
  ConsumerState<StoryReaderPage> createState() => _StoryReaderPageState();
}

class _StoryReaderPageState extends ConsumerState<StoryReaderPage>
    with SingleTickerProviderStateMixin {
  final GlobalKey _targetKey = GlobalKey();
  bool _scrolled = false;

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
      index >= widget.highlightStart && index <= widget.highlightEnd;

  void _scrollToTarget() {
    if (_scrolled) return;
    _scrolled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final target = _targetKey.currentContext;
      if (target == null || !mounted) return;
      await Scrollable.ensureVisible(
        target,
        alignment: 0.25,
        duration: const Duration(milliseconds: 300),
      );
      if (mounted) _flash.forward(from: 0);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider);
    final entries = ref
            .watch(storyCatalogEntriesProvider(storyLabelsKey([widget.storyId])))
            .valueOrNull ??
        const {};
    final title = entries[widget.storyId]?.label ??
        fallbackStoryLabel(widget.storyId);
    final range = widget.highlightStart == widget.highlightEnd
        ? context.t.aiCitationLine(widget.highlightStart + 1)
        : context.t.aiCitationLines(
            widget.highlightStart + 1, widget.highlightEnd + 1,);
    final lines = ref.watch(storyFullLinesProvider(widget.storyId));

    return Scaffold(
      backgroundColor: theme.bgPrimary,
      appBar: AppBar(
        backgroundColor: theme.bgSecondary,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.titleFont.copyWith(fontSize: 16),
            ),
            Text(
              '${context.t.aiStoryReaderTitle} · $range',
              style: theme.bodyFont.copyWith(
                color: theme.textSecondary,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
      body: lines.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => _unavailable(theme),
        data: (lines) {
          if (lines.isEmpty) return _unavailable(theme);
          _scrollToTarget();
          final firstTarget = lines.indexWhere((l) => _isTarget(l.lineIndex));
          return SingleChildScrollView(
            key: const ValueKey('story-reader-scroll'),
            padding: const EdgeInsets.fromLTRB(12, 8, 16, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (i, line) in lines.indexed)
                  _isTarget(line.lineIndex)
                      ? AnimatedBuilder(
                          key: i == firstTarget ? _targetKey : null,
                          animation: _strength,
                          builder: (context, child) => Container(
                            key: ValueKey('story-line-target-${line.lineIndex}'),
                            decoration: BoxDecoration(
                              color: theme.accentPrimary.withValues(
                                alpha: 0.3 * _strength.value,
                              ),
                              border: Border(
                                left: BorderSide(
                                  color: theme.accentText,
                                  width: 3,
                                ),
                              ),
                            ),
                            child: child,
                          ),
                          child: _line(theme, line),
                        )
                      : _line(theme, line),
              ],
            ),
          );
        },
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

  Widget _line(AppThemeTokens theme, StoryLineEntry line) {
    final speaker = (line.speaker ?? '').trim();
    final narration = speaker.isEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 40,
            child: Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                '${line.lineIndex + 1}',
                textAlign: TextAlign.right,
                style: theme.bodyFont.copyWith(
                  color: theme.textSecondary.withValues(alpha: 0.6),
                  fontSize: 10,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  if (!narration)
                    TextSpan(
                      text: '$speaker：',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  TextSpan(text: line.content),
                ],
              ),
              style: theme.bodyFont.copyWith(
                color: narration ? theme.textSecondary : theme.textPrimary,
                fontStyle: narration ? FontStyle.italic : FontStyle.normal,
                fontSize: 14,
                height: 1.55,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
