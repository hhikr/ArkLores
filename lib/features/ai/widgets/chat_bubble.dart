import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/agent/agent_provider.dart';
import '../../../core/agent/react_event.dart';
import '../../../core/agent/story_answer.dart';
import '../../../core/agent/turn_stats.dart';
import '../../../core/gamedata/story_catalog.dart' show StoryCatalogEntry;
import '../../../core/llm/llm_client.dart';
import '../../../shared/l10n/l10n.dart';
import '../../../shared/providers/theme_provider.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../shared/widgets/press_feedback.dart';
import '../evidence_observation.dart';
import '../investigation_ui.dart';
import '../story_labels_provider.dart';
import '../work_steps.dart';
import 'story_answer_body.dart';

/// Renders a single chat bubble with support for ReAct steps disclosure
/// and lazy loading of citations.
class ChatBubble extends ConsumerStatefulWidget {

  const ChatBubble({super.key, required this.message});
  final ChatMessage message;

  @override
  ConsumerState<ChatBubble> createState() => _ChatBubbleState();
}

class _ChatBubbleState extends ConsumerState<ChatBubble> {
  bool _showSteps = false;
  bool _showEvidence = false;

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider);
    final msg = widget.message;
    final isUser = msg.role == MessageRole.user;

    // R15: no avatars. The user's message is a right-aligned bubble; the
    // answer uses the full width without a frame, with its status, steps
    // and evidence folded into single lines above / below it.
    if (isUser) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Align(
          alignment: Alignment.centerRight,
          child: LayoutBuilder(
            builder: (context, constraints) => ConstrainedBox(
              constraints: BoxConstraints(maxWidth: constraints.maxWidth * 0.8),
              child: _buildUserContentBox(theme),
            ),
          ),
        ),
      );
    }
    final storyAnswer = isStoryAnswer(msg.content);
    // R16: while the story pipeline runs, one live line says what it is
    // doing; the status envelope replaces it when the answer is checked.
    final live = msg.isStreaming && msg.liveStatus.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (storyAnswer)
            _buildStoryAnswerHeader(theme)
          else if (live)
            _buildLiveHeader(theme)
          else if (msg.steps.isNotEmpty)
            _buildReActStepsSection(theme),
          if (msg.reasoning.isNotEmpty) _buildReasoningPanel(theme),
          if (storyAnswer || live || msg.steps.isNotEmpty)
            const SizedBox(height: 6),
          if (msg.factCheckVerdict != null) ...[
            _buildVerdictBanner(theme, msg.factCheckVerdict!),
            const SizedBox(height: 6),
          ],
          _buildAssistantContentBox(theme),
          if (storyAnswer) _buildCitationTree(theme),
          if (!msg.isStreaming && (msg.canDigest || msg.canReview))
            _buildAnswerActions(theme),
          if (msg.stats != null) _buildStatsLine(theme, msg.stats!),
        ],
      ),
    );
  }

  /// 0.14: what can be asked for once the answer is there — "提要" (a long
  /// answer reorganised into a few paragraphs above it) and "复核" (a
  /// reader's review, answered below as a turn of its own).
  Widget _buildAnswerActions(AppThemeTokens theme) {
    final msg = widget.message;
    // Read when pressed: showing an answer does not need the chat itself.
    AskChatNotifier chat() => ref.read(askChatProvider.notifier);
    Widget action(String key, IconData icon, String label, String hint,
            VoidCallback onTap,) =>
        Tooltip(
          message: hint,
          child: PressFeedback(
            pressedScale: 0.92,
            child: InkWell(
              key: ValueKey(key),
              onTap: withHaptic(onTap),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  border: Border.all(color: theme.divider),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 15, color: theme.accentText),
                    const SizedBox(width: 5),
                    Text(
                      label,
                      style: theme.bodyFont.copyWith(
                        fontSize: 12.5,
                        color: theme.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        children: [
          if (msg.canDigest)
            action(
              'answer-digest',
              Icons.short_text_sharp,
              context.t.aiAnswerDigest,
              context.t.aiAnswerDigestHint,
              () => chat().digestAnswer(msg.id),
            ),
          if (msg.canReview)
            action(
              'answer-review',
              Icons.fact_check_sharp,
              context.t.aiAnswerReview,
              context.t.aiAnswerReviewHint,
              () => chat().reviewAnswer(
                msg.id,
                label: context.t.aiReviewRequest,
              ),
            ),
        ],
      ),
    );
  }

  /// What the question cost, in small grey text under the answer.
  Widget _buildStatsLine(AppThemeTokens theme, TurnStats stats) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: SelectableText(
        formatUsageLine(stats),
        key: const ValueKey('usage-line'),
        style: theme.bodyFont.copyWith(
          fontSize: 11,
          height: 1.3,
          color: theme.textSecondary.withValues(alpha: 0.7),
        ),
      ),
    );
  }
  Widget _buildUserContentBox(AppThemeTokens theme) {
    return Container(
      key: const ValueKey('user-bubble'),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: theme.accentPrimary.withValues(alpha: 0.15),
        borderRadius: BorderRadius.zero,
        border: Border.all(
          color: theme.accentText.withValues(alpha: 0.35),
          width: 1,
        ),
      ),
      child: SelectableText(
        widget.message.content,
        style: theme.bodyFont.copyWith(color: theme.textPrimary),
      ),
    );
  }

  Widget _buildAssistantContentBox(AppThemeTokens theme) {
    final msg = widget.message;
    var content = msg.content.replaceFirst(
      RegExp(r'\[FACT_CHECK_VERDICT:[a-z]+\]\s*', caseSensitive: false),
      '',
    );
    // R17b: story answers are rendered block by block, each followed by its
    // evidence chain (also while streaming, then without the chains).
    String? storyBody;
    if (isStoryAnswer(content)) {
      storyBody = stripStoryAnswerMarkers(content);
    } else if (msg.isStreaming && msg.liveStatus.isNotEmpty) {
      storyBody = stripWriterCoverage(content);
    }
    if (content == '[ASK_ERROR]') {
      content = context.t.aiAskError;
    } else if (content == '[ASK_CANCELED]') {
      content = context.t.aiAskCanceled;
    }

    // Scan for citation UUIDs
    final uuidRegex = RegExp(
        r'\[([a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12})\]',);
    final matches = uuidRegex.allMatches(content);
    final citationIds = matches.map((m) => m.group(1)!).toSet().toList();

    // Map UUIDs to indices to show nice indexed footnote links [^1] instead of raw UUIDs
    String formattedContent = content;
    final Map<String, int> uuidToIdx = {};
    var index = 1;
    for (final uuid in citationIds) {
      uuidToIdx[uuid] = index++;
      formattedContent =
          formattedContent.replaceAll('[$uuid]', '[^${uuidToIdx[uuid]}]');
    }

    final styleSheet =
        MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
      p: theme.bodyFont.copyWith(color: theme.textPrimary, height: 1.5),
      h1: theme.titleFont.copyWith(color: theme.textPrimary, fontSize: 18),
      h2: theme.titleFont.copyWith(color: theme.textPrimary, fontSize: 16),
      h3: theme.titleFont.copyWith(color: theme.textPrimary, fontSize: 14),
      a: theme.bodyFont.copyWith(color: theme.accentText),
      listBullet: theme.bodyFont.copyWith(color: theme.textPrimary),
      code: theme.bodyFont.copyWith(
        color: theme.accentSecondary,
        backgroundColor: theme.bgPrimary,
      ),
      blockquote: theme.bodyFont.copyWith(color: theme.textSecondary),
      blockquoteDecoration: BoxDecoration(
        color: theme.bgPrimary,
        border: Border(
          left: BorderSide(color: theme.accentPrimary, width: 3),
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          key: const ValueKey('assistant-content'),
          width: double.infinity,
          child: formattedContent.trim().isEmpty && msg.isStreaming
              ? _buildTypingIndicator(theme)
              : storyBody != null
                  ? StoryAnswerBody(
                      content: storyBody,
                      styleSheet: styleSheet,
                      streaming: msg.isStreaming,
                    )
                  : MarkdownBody(
                      data: formattedContent,
                      styleSheet: styleSheet,
                    ),
        ),
        if (citationIds.isNotEmpty) const SizedBox(height: 8),
        if (_evidenceRecords.isNotEmpty) _buildEvidenceSection(theme),
      ],
    );
  }

  String _lineText(int start, int? end) => end == null
      ? context.t.aiCitationLine(start)
      : context.t.aiCitationLines(start, end);

  List<String> get _evidenceObservations => widget.message.steps
      .where((step) =>
          step.type == ReActEventType.toolObservation &&
          step.content.contains('Source Kind: GameData'),)
      .map((step) => step.content)
      .toList(growable: false);

  List<EvidenceRecord> get _evidenceRecords => [
        for (final observation in _evidenceObservations)
          ...parseGameDataEvidence(observation),
      ];

  Widget _buildVerdictBanner(AppThemeTokens theme, FactCheckVerdict verdict) {
    final config = switch (verdict) {
      FactCheckVerdict.supported => (
          Icons.check_circle_sharp,
          Colors.green,
          context.t.aiVerdictSupported
        ),
      FactCheckVerdict.refuted => (
          Icons.cancel_sharp,
          theme.danger,
          context.t.aiVerdictRefuted
        ),
      FactCheckVerdict.uncertain => (
          Icons.help_sharp,
          Colors.amber.shade800,
          context.t.aiVerdictUncertain
        ),
      FactCheckVerdict.unavailable => (
          Icons.remove_circle_outline_sharp,
          theme.textSecondary,
          context.t.aiVerdictUnavailable
        ),
    };
    return Semantics(
      label: context.t.aiVerdictSemantics(config.$3),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: config.$2.withValues(alpha: 0.12),
          border: Border(left: BorderSide(color: config.$2, width: 3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(config.$1, size: 18, color: config.$2),
            const SizedBox(width: 6),
            Text(config.$3,
                style: theme.titleFont.copyWith(
                  color: config.$2,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),),
          ],
        ),
      ),
    );
  }

  /// R15: one tappable line for a story answer — status, confidence and
  /// the reasoning steps (expanded on tap), instead of a status card above
  /// a separate steps box. The pre-R13 coverage line stays below it.
  Widget _buildStoryAnswerHeader(AppThemeTokens theme) {
    final msg = widget.message;
    final envelope = parseStoryAnswerEnvelope(msg.content);
    final coverage = parseCoverageReportLine(msg.content);
    final status = envelope?.status;
    final accent = status == StoryAnswerStatus.answered
        ? theme.accentText
        : theme.warning;
    final statusLabel = switch (status) {
      StoryAnswerStatus.answered => context.t.aiAnswerStatusAnswered,
      StoryAnswerStatus.partial => context.t.aiAnswerStatusPartial,
      StoryAnswerStatus.notCovered => context.t.aiAnswerStatusNotCovered,
      null => '-',
    };
    final parts = [
      statusLabel,
      if (envelope?.confidence != null)
        '${context.t.aiInvestigationConfidence} ${envelope!.confidence}',
      if (msg.steps.isNotEmpty) _workSummary(),
    ];
    final icon = status == StoryAnswerStatus.answered
        ? Icons.check_circle_outline_sharp
        : Icons.error_outline_sharp;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          key: const ValueKey('answer-header'),
          onTap: msg.steps.isEmpty
              ? null
              : () => setState(() => _showSteps = !_showSteps),
          borderRadius: BorderRadius.zero,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Icon(icon, size: 15, color: accent),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    parts.join(' · '),
                    style: theme.bodyFont.copyWith(
                      color: accent,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (msg.steps.isNotEmpty)
                  Icon(
                    _showSteps
                        ? Icons.expand_less_sharp
                        : Icons.chevron_right_sharp,
                    size: 16,
                    color: theme.textSecondary,
                  ),
              ],
            ),
          ),
        ),
        if (_showSteps) _buildStepsList(theme),
        if (coverage != null)
          Text(
            '${context.t.aiInvestigationCoverage}: '
            '${context.t.aiInvestigationRead}=${coverage.read} · '
            '${context.t.aiInvestigationMapped}=${coverage.mapped} · '
            '${context.t.aiInvestigationSkipped}=${coverage.skipped}',
            style: theme.bodyFont.copyWith(
              color: theme.textSecondary,
              fontSize: 11,
            ),
          ),
      ],
    );
  }

  /// R16: the live line of a running story question — the current step
  /// ("第 7 步 · 阅读 …" / "正在撰写答案"), tappable for the steps so far.
  Widget _buildLiveHeader(AppThemeTokens theme) {
    final msg = widget.message;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          key: const ValueKey('live-header'),
          onTap: msg.steps.isEmpty
              ? null
              : () => setState(() => _showSteps = !_showSteps),
          borderRadius: BorderRadius.zero,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    valueColor: AlwaysStoppedAnimation(theme.accentPrimary),
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    msg.liveStatus,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.bodyFont.copyWith(
                      color: theme.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (msg.steps.isNotEmpty)
                  Icon(
                    _showSteps
                        ? Icons.expand_less_sharp
                        : Icons.chevron_right_sharp,
                    size: 16,
                    color: theme.textSecondary,
                  ),
              ],
            ),
          ),
        ),
        if (_showSteps) _buildStepsList(theme),
      ],
    );
  }

  bool _showReasoning = true;
  final ScrollController _reasoningScroll = ScrollController();

  @override
  void dispose() {
    _reasoningScroll.dispose();
    super.dispose();
  }

  /// Height of the thinking window, whatever the length of the text.
  static const double reasoningWindowHeight = 168;

  /// R16: hidden reasoning streamed while the answer is written (only with
  /// "深度思考" on); muted and collapsible. R17d: a window of fixed height
  /// holding the whole text, scrolled only by the reader (new thinking grows
  /// below, nothing follows it), and kept after the answer is complete, so
  /// the answer below it never shifts.
  Widget _buildReasoningPanel(AppThemeTokens theme) {
    final text = widget.message.reasoning;
    final muted = theme.bodyFont.copyWith(
      color: theme.textSecondary,
      fontSize: 12,
      height: 1.5,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          key: const ValueKey('reasoning-header'),
          onTap: () => setState(() => _showReasoning = !_showReasoning),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(context.t.aiThinkingProcess, style: muted),
                Icon(
                  _showReasoning
                      ? Icons.expand_less_sharp
                      : Icons.chevron_right_sharp,
                  size: 16,
                  color: theme.textSecondary,
                ),
              ],
            ),
          ),
        ),
        if (_showReasoning)
          Container(
            key: const ValueKey('reasoning-text'),
            width: double.infinity,
            height: reasoningWindowHeight,
            decoration: BoxDecoration(
              color: theme.bgSecondary.withValues(alpha: 0.5),
              borderRadius: BorderRadius.zero,
              border: Border.all(color: theme.divider, width: 0.5),
            ),
            child: Scrollbar(
              controller: _reasoningScroll,
              thumbVisibility: true,
              child: SingleChildScrollView(
                key: const ValueKey('reasoning-scroll'),
                controller: _reasoningScroll,
                padding: const EdgeInsets.fromLTRB(10, 6, 14, 6),
                child: Text(text, style: muted),
              ),
            ),
          ),
      ],
    );
  }

  /// Expanded keys of the citation tree (`*` = the tree itself, then
  /// collection labels and story ids).
  final Set<String> _expanded = {};

  bool _isOpen(String key, {bool byDefault = false}) =>
      _expanded.contains(key) != byDefault;

  void _toggle(String key) => setState(() {
        if (!_expanded.remove(key)) _expanded.add(key);
      });

  /// R15: cited lines, folded by default: collection → chapter → line
  /// chips (raw id on long-press). Collections start open, chapters start
  /// open only when the collection has a single chapter. R17: tapping a
  /// chip shows the original lines from the knowledge base (the evidence
  /// itself, not the model's account of it); cited non-story records are
  /// listed after the stories, numbered as in the answer.
  Widget _buildCitationTree(AppThemeTokens theme) {
    final msg = widget.message;
    if (msg.isStreaming) return const SizedBox.shrink();
    // R18: the reorganised paragraphs only merge the detailed answer's
    // citations; count each once, from the details.
    final cited = citedPartOfAnswer(msg.content);
    final ids = extractCitedStoryIds(cited);
    final records = extractCitedRecordIds(cited);
    final wikis = extractCitedWikiPages(cited);
    if (ids.isEmpty && records.isEmpty && wikis.isEmpty) {
      return const SizedBox.shrink();
    }
    final entries = ids.isEmpty
        ? const <String, StoryCatalogEntry>{}
        : ref
                .watch(storyCatalogEntriesProvider(storyLabelsKey(ids)))
                .valueOrNull ??
            const <String, StoryCatalogEntry>{};
    final groups = groupCitations(cited, entries);
    final total = groups.fold<int>(0, (n, g) => n + g.citationCount) +
        records.length +
        wikis.fold<int>(0, (n, w) => n + w.ranges.length);
    final open = _isOpen('*');
    final muted = theme.bodyFont.copyWith(
      color: theme.textSecondary,
      fontSize: 12,
    );

    Widget row(String key, String text, {required bool isOpen, double indent = 0, TextStyle? style}) =>
        InkWell(
          key: ValueKey('cite:$key'),
          onTap: () => _toggle(key),
          child: Padding(
            padding: EdgeInsets.fromLTRB(indent, 5, 0, 5),
            child: Row(
              children: [
                Icon(
                  isOpen ? Icons.expand_more_sharp : Icons.chevron_right_sharp,
                  size: 16,
                  color: theme.textSecondary,
                ),
                const SizedBox(width: 4),
                Expanded(child: Text(text, style: style ?? muted)),
              ],
            ),
          ),
        );

    Widget chip(String key, String text,
            {required bool selected, VoidCallback? onTap,}) =>
        PressFeedback(
          pressedScale: 0.9,
          child: InkWell(
          key: ValueKey('cite:$key'),
          onTap: withHaptic(onTap ?? () => _toggle(key)),
          borderRadius: BorderRadius.zero,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: selected
                  ? theme.accentPrimary.withValues(alpha: 0.15)
                  : theme.bgSecondary,
              borderRadius: BorderRadius.zero,
              border: Border.all(
                color: selected ? theme.accentText : theme.divider,
                width: 0.5,
              ),
            ),
            child: Text(
              text,
              style: theme.bodyFont.copyWith(
                color: theme.textPrimary,
                fontSize: 11,
              ),
            ),
          ),
          ),
        );

    Widget quote(Widget child) => Container(
          width: double.infinity,
          margin: const EdgeInsets.only(top: 6),
          padding: const EdgeInsets.fromLTRB(10, 6, 8, 6),
          decoration: BoxDecoration(
            color: theme.bgPrimary,
            border: Border(
              left: BorderSide(color: theme.accentPrimary, width: 2),
            ),
          ),
          child: child,
        );

    Widget citedRecord(String id) {
      final record = ref.watch(citedRecordProvider(id));
      return quote(record.when(
        loading: () => const LinearProgressIndicator(minHeight: 2),
        error: (_, __) => Text(context.t.aiCitedLinesUnavailable, style: muted),
        data: (r) => r == null
            ? Text(context.t.aiCitedLinesUnavailable, style: muted)
            : SelectableText(
                r.content,
                style: theme.bodyFont.copyWith(
                  color: theme.textPrimary,
                  fontSize: 12,
                  height: 1.5,
                ),
              ),
      ),);
    }

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Divider(height: 1, color: theme.divider),
          row(
            '*',
            context.t.aiEvidenceSummary(total, groups.length),
            isOpen: open,
          ),
          if (open)
            for (final group in groups) ...[
              row(
                'c:${group.label}',
                '${group.label} · ${context.t.aiChapterCount(group.citationCount)}',
                isOpen: _isOpen('c:${group.label}', byDefault: true),
                indent: 14,
                style: muted.copyWith(color: theme.textPrimary),
              ),
              if (_isOpen('c:${group.label}', byDefault: true))
                for (final chapter in group.chapters) ...[
                  row(
                    's:${chapter.storyId}',
                    '${chapter.label.isEmpty ? chapter.storyId.split('/').last : chapter.label}'
                        ' · ${context.t.aiChapterCount(chapter.ranges.length)}',
                    isOpen: _isOpen(
                      's:${chapter.storyId}',
                      byDefault: group.chapters.length == 1,
                    ),
                    indent: 28,
                  ),
                  if (_isOpen(
                    's:${chapter.storyId}',
                    byDefault: group.chapters.length == 1,
                  ))
                    Padding(
                      padding: const EdgeInsets.fromLTRB(48, 2, 0, 6),
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final range in chapter.ranges)
                            Tooltip(
                              message: range.rawRef(chapter.storyId),
                              triggerMode: TooltipTriggerMode.longPress,
                              child: chip(
                                'l:${range.rawRef(chapter.storyId)}',
                                citedRangeText(range, _lineText),
                                selected: false,
                                onTap: () => openStoryReader(
                                    context, chapter.storyId, range,),
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
            ],
          if (open && records.isNotEmpty) ...[
            row(
              'records',
              context.t.aiCitedRecords(records.length),
              isOpen: _isOpen('records', byDefault: true),
              indent: 14,
              style: muted.copyWith(color: theme.textPrimary),
            ),
            if (_isOpen('records', byDefault: true))
              for (final (i, id) in records.indexed) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(28, 2, 0, 2),
                  child: Tooltip(
                    message: 'record:$id',
                    triggerMode: TooltipTriggerMode.longPress,
                    child: chip(
                      'r:$id',
                      '${context.t.aiCitedRecord} ${i + 1}'
                          '${_recordTitle(id).isEmpty ? '' : ' · ${_recordTitle(id)}'}',
                      selected: _isOpen('r:$id'),
                    ),
                  ),
                ),
                if (_isOpen('r:$id'))
                  Padding(
                    padding: const EdgeInsets.fromLTRB(28, 0, 0, 4),
                    child: citedRecord(id),
                  ),
              ],
          ],
          // 0.13: wiki pages, each with its paragraph chips (open the
          // cited paragraphs).
          if (open && wikis.isNotEmpty) ...[
            row(
              'wikis',
              context.t.aiCitedWikiPages(wikis.length),
              isOpen: _isOpen('wikis', byDefault: true),
              indent: 14,
              style: muted.copyWith(color: theme.textPrimary),
            ),
            if (_isOpen('wikis', byDefault: true))
              for (final page in wikis)
                Padding(
                  padding: const EdgeInsets.fromLTRB(28, 2, 0, 4),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        wikiPageLabel(ref, page.pageId),
                        style: muted.copyWith(color: theme.textPrimary),
                      ),
                      for (final range in page.ranges)
                        Tooltip(
                          message: '${page.pageId}:${range.start}-${range.end}',
                          triggerMode: TooltipTriggerMode.longPress,
                          child: chip(
                            'w:${page.pageId}:${range.start}',
                            range.start == range.end
                                ? context.t.aiCitationParagraph(range.start + 1)
                                : context.t.aiCitationParagraphs(
                                    range.start + 1,
                                    range.end + 1,
                                  ),
                            selected: false,
                            onTap: () =>
                                showCitedWiki(context, page.pageId, range),
                          ),
                        ),
                    ],
                  ),
                ),
          ],
        ],
      ),
    );
  }

  /// Title of a cited record once loaded (empty while loading).
  String _recordTitle(String id) =>
      ref.watch(citedRecordProvider(id)).valueOrNull?.title ?? '';
  Widget _buildEvidenceSection(AppThemeTokens theme) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: ExpansionTile(
        initiallyExpanded: _showEvidence,
        onExpansionChanged: (value) => setState(() => _showEvidence = value),
        tilePadding: const EdgeInsets.symmetric(horizontal: 10),
        childrenPadding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
        leading: Icon(Icons.source_sharp, color: theme.accentText),
        title: Text(
          context.t.aiEvidenceTitle(_evidenceRecords.length),
          style: theme.titleFont.copyWith(fontSize: 13),
        ),
        children: [
          for (final record in _evidenceRecords)
            _buildEvidenceRecord(theme, record),
        ],
      ),
    );
  }

  Widget _buildTypingIndicator(AppThemeTokens theme) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          context.t.aiThinking,
          style:
              theme.bodyFont.copyWith(color: theme.textSecondary, fontSize: 13),
        ),
        const SizedBox(width: 4),
        const SizedBox(
          width: 12,
          height: 12,
          child: CircularProgressIndicator(
            strokeWidth: 1.5,
            valueColor: AlwaysStoppedAnimation(Colors.grey),
          ),
        ),
      ],
    );
  }

  Widget _buildReActStepsSection(AppThemeTokens theme) {
    final stepsCount = widget.message.steps.length;

    // Determine current activity status
    var statusText = context.t.aiReasoningComplete;
    var isThinking = false;
    if (widget.message.isStreaming) {
      isThinking = true;
      if (widget.message.steps.isNotEmpty) {
        final lastStep = widget.message.steps.last;
        if (lastStep.type == ReActEventType.toolCall) {
          statusText = context.t.aiUsingTool(lastStep.toolName ?? '');
        } else if (lastStep.type == ReActEventType.thought) {
          statusText = context.t.aiReasoning;
        } else {
          statusText = context.t.aiProcessing;
        }
      } else {
        statusText = context.t.aiThinking;
      }
    }

    return Container(
      decoration: BoxDecoration(
        color: theme.bgSecondary,
        borderRadius: BorderRadius.zero,
        border: Border.all(color: theme.divider, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _showSteps = !_showSteps),
            borderRadius: BorderRadius.zero,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Row(
                children: [
                  Icon(
                    _showSteps
                        ? Icons.visibility_sharp
                        : Icons.visibility_off_sharp,
                    size: 14,
                    color: theme.accentText,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      isThinking
                          ? context.t.aiStepsStatus(statusText, stepsCount)
                          : _workSummary(),
                      softWrap: true,
                      style: theme.bodyFont.copyWith(
                        color: theme.textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  if (isThinking) ...[
                    const SizedBox(width: 6),
                    SizedBox(
                      width: 10,
                      height: 10,
                      child: CircularProgressIndicator(
                        strokeWidth: 1,
                        valueColor: AlwaysStoppedAnimation(theme.accentPrimary),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (_showSteps) _buildStepsList(theme),
        ],
      ),
    );
  }

  /// The work behind the answer as a timeline in the reader's words (what
  /// was searched or read, what it found); raw outputs on tap.
  Widget _buildStepsList(AppThemeTokens theme) {
    final steps = workStepsOf(widget.message.steps);
    return Container(
      key: const ValueKey('work-timeline'),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(2, 6, 4, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < steps.length; i++)
            _buildWorkRow(theme, steps[i], i, last: i == steps.length - 1),
        ],
      ),
    );
  }

  /// "查阅 n 次 · 读了 m 篇原文".
  String _workSummary() {
    final counts = workCounts(workStepsOf(widget.message.steps));
    return context.t.aiWorkSummary(counts.calls, counts.reads);
  }

  Widget _buildEvidenceRecord(AppThemeTokens theme, EvidenceRecord record) {
    final coverage = record.isDirectCandidate
        ? context.t.aiCoverageDirect
        : context.t.aiCoverageRetrieved;
    return Semantics(
      container: true,
      label: context.t.aiEvidenceSemantics(record.title, coverage),
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(top: 6),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: theme.bgPrimary,
          border: Border.all(color: theme.divider),
          borderRadius: BorderRadius.zero,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 6,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(record.title,
                    style: theme.titleFont.copyWith(
                        color: theme.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,),),
                _evidenceBadge(theme, coverage),
              ],
            ),
            if (record.section != null)
              _metadata(context.t.aiEvidenceSection, record.section!, theme),
            if (record.contentType != null)
              _metadata(
                  context.t.aiEvidenceContentType, record.contentType!, theme,),
            _metadata(
                context.t.aiEvidenceRetrievalType, record.retrievalType, theme,),
            _metadata(
                context.t.aiEvidenceRankingReason, record.rankingReason, theme,),
            if (record.sourcePath != null)
              _metadata(
                  context.t.aiEvidenceSourcePath, record.sourcePath!, theme,),
            if (record.rawId != null)
              _metadata(context.t.aiEvidenceRawId, record.rawId!, theme),
            _metadata(context.t.aiEvidenceTrustNote, record.trustNote, theme),
            if (record.excerpt.isNotEmpty) ...[
              const SizedBox(height: 6),
              SelectableText(record.excerpt,
                  style: theme.bodyFont.copyWith(
                      color: theme.textPrimary, fontSize: 12, height: 1.4,),),
            ],
          ],
        ),
      ),
    );
  }

  Widget _metadata(String label, String value, AppThemeTokens theme) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: SelectableText('$label: $value',
            style: theme.bodyFont.copyWith(
                color: theme.textSecondary, fontSize: 11, height: 1.35,),),
      );

  Widget _evidenceBadge(AppThemeTokens theme, String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: theme.accentPrimary.withValues(alpha: 0.12),
          border: Border.all(color: theme.accentText.withValues(alpha: 0.4)),
          borderRadius: BorderRadius.zero,
        ),
        child: Text(label,
            style: theme.bodyFont.copyWith(
                color: theme.accentText,
                fontSize: 10,
                fontWeight: FontWeight.bold,),),
      );

  /// Steps whose raw output is unfolded (by index in [workStepsOf]).
  final Set<int> _openSteps = {};

  /// One row of the work timeline, as the session record has it: the
  /// call's number, the tool, what it was asked (its arguments as written)
  /// and what came back (how much, and what went wrong); tap for the whole
  /// arguments and output.
  Widget _buildWorkRow(AppThemeTokens theme, WorkStep step, int index,
      {required bool last,}) {
    final open = _openSteps.contains(index);
    final small = theme.bodyFont.copyWith(fontSize: 11, height: 1.35);
    final mono = small.copyWith(fontFamily: 'monospace');
    void toggle() => setState(() {
          if (!_openSteps.remove(index)) _openSteps.add(index);
        });
    if (step.kind == WorkKind.note || step.kind == WorkKind.record) {
      final record = step.kind == WorkKind.record;
      return _timelineRow(
        theme,
        last: last,
        dot: null,
        child: InkWell(
          key: record ? ValueKey('work-record-$index') : null,
          onTap: toggle,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Text(
              record ? context.t.aiWorkRecord(step.text) : step.text,
              maxLines: open ? null : (record ? 3 : 2),
              overflow: open ? null : TextOverflow.ellipsis,
              style: small.copyWith(
                color: record ? theme.warning : theme.textMuted,
                fontStyle: record ? null : FontStyle.italic,
              ),
            ),
          ),
        ),
      );
    }
    if (step.kind == WorkKind.error) {
      return _timelineRow(
        theme,
        last: last,
        dot: Icon(Icons.error_outline_sharp, size: 13, color: theme.danger),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: SelectableText(
            step.text,
            style: theme.bodyFont.copyWith(
              fontSize: 12.5,
              height: 1.35,
              color: theme.danger,
            ),
          ),
        ),
      );
    }
    final t = context.t;
    final bad = step.failed || step.notRun;
    final result = _workResult(step);
    final args = step.argsJson;
    final flags = <(String, Color)>[
      if (step.subtask != null) (t.aiWorkHelper(step.subtask!), theme.textMuted),
      if (step.planned) (t.aiWorkPlanned, theme.textMuted),
      if (step.repeated) (t.aiWorkRepeated, theme.danger),
      if (step.notRun)
        (t.aiWorkNotRun, theme.danger)
      else if (step.failed)
        (t.aiWorkFailed, theme.danger)
      else if (step.empty)
        (t.aiWorkNone, theme.danger),
      if (step.wikiDown && !step.failed) (t.aiWorkWikiDown, theme.danger),
    ];
    final canOpen = step.done && (step.text.isNotEmpty || args.isNotEmpty);
    return _timelineRow(
      theme,
      last: last,
      dot: Icon(_workIcon(step.kind), size: 13,
          color: bad ? theme.danger : theme.accentText,),
      child: InkWell(
        key: ValueKey('work-step-$index'),
        borderRadius: BorderRadius.zero,
        onTap: canOpen ? toggle : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 2,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text('${step.number}',
                            style: small.copyWith(color: theme.textMuted),),
                        Text(
                          step.tool ?? '',
                          style: mono.copyWith(
                            fontSize: 12.5,
                            fontWeight: FontWeight.bold,
                            color: theme.textPrimary,
                          ),
                        ),
                        for (final (label, color) in flags)
                          _workFlag(theme, label, color),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (!step.done)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: SizedBox(
                        width: 10,
                        height: 10,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.2,
                          valueColor: AlwaysStoppedAnimation(theme.accentText),
                        ),
                      ),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: Text(
                        [
                          if (result.isNotEmpty) result,
                          t.aiWorkChars(step.text.length),
                        ].join(' · '),
                        style: small.copyWith(color: theme.textMuted),
                      ),
                    ),
                ],
              ),
              if (args.isNotEmpty && !open)
                Text(
                  args,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: mono.copyWith(color: theme.textMuted),
                ),
              // Why a failed step failed, in the tool's own words.
              if (bad && !open)
                Text(
                  step.text.trimLeft().split('\n').first,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: small.copyWith(color: theme.danger),
                ),
              if (open)
                Container(
                  key: ValueKey('work-raw-$index'),
                  width: double.infinity,
                  margin: const EdgeInsets.only(top: 6),
                  constraints: const BoxConstraints(maxHeight: workRawHeight),
                  decoration: BoxDecoration(
                    color: theme.bgSecondary.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.zero,
                  ),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(8),
                    child: SelectableText(
                      [
                        if (args.isNotEmpty)
                          const JsonEncoder.withIndent('  ').convert(step.args),
                        step.text.trim(),
                      ].join('\n\n'),
                      style: mono.copyWith(
                        color: theme.textSecondary,
                        fontSize: 10.5,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// How tall an unfolded step's arguments and output may be; the whole of
  /// it scrolls inside.
  static const double workRawHeight = 320;

  Widget _workFlag(AppThemeTokens theme, String label, Color color) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 5),
        decoration: BoxDecoration(
          border: Border.all(color: color.withValues(alpha: 0.7)),
          borderRadius: BorderRadius.zero,
        ),
        child: Text(
          label,
          style: theme.bodyFont.copyWith(fontSize: 10, height: 1.4, color: color),
        ),
      );
  /// A timeline row: a dot (or a short tick for notes) on a thin rail.
  Widget _timelineRow(AppThemeTokens theme,
      {required bool last, required Widget? dot, required Widget child,}) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 22,
            child: Stack(
              alignment: Alignment.topCenter,
              children: [
                Positioned(
                  top: 0,
                  bottom: last ? null : 0,
                  height: last ? 12 : null,
                  child: Container(width: 1, color: theme.divider),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: dot == null
                      ? Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Container(
                            width: 5,
                            height: 5,
                            decoration: BoxDecoration(
                              color: theme.divider,
                            ),
                          ),
                        )
                      : Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            color: theme.cardSurface,
                            border: Border.all(color: theme.divider),
                          ),
                          child: dot,
                        ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: child),
        ],
      ),
    );
  }

  IconData _workIcon(WorkKind kind) => switch (kind) {
        WorkKind.sql => Icons.storage_sharp,
        WorkKind.grep => Icons.search_sharp,
        WorkKind.read => Icons.menu_book_sharp,
        WorkKind.readRecord => Icons.description_sharp,
        WorkKind.outline => Icons.format_list_bulleted_sharp,
        WorkKind.find => Icons.travel_explore_sharp,
        WorkKind.similarNames => Icons.spellcheck_sharp,
        WorkKind.delegate => Icons.call_split_sharp,
        WorkKind.wikiSearch => Icons.public_sharp,
        WorkKind.wikiRead => Icons.article_sharp,
        WorkKind.error => Icons.error_outline_sharp,
        WorkKind.otherTool ||
        WorkKind.note ||
        WorkKind.record =>
          Icons.build_outlined,
      };
  String _workResult(WorkStep step) {
    final t = context.t;
    if (!step.isTool || !step.done) return '';
    if (step.failed) return t.aiWorkFailed;
    if (step.empty) return t.aiWorkNone;
    switch (step.kind) {
      case WorkKind.grep:
        final (hits, stories) = step.grepCounts;
        return stories == 0 ? '' : t.aiWorkHits(hits, stories);
      case WorkKind.sql:
        final rows = step.rowCount;
        return rows == null ? '' : t.aiWorkRows(rows);
      case WorkKind.find:
        final stories = step.searchStoryCount;
        return stories == null ? '' : t.aiWorkStories(stories);
      case WorkKind.read:
        final range = step.lineRange;
        return range == null ? '' : t.aiWorkLines(range.$1, range.$2);
      case WorkKind.wikiSearch:
        final pages = step.wikiPageCount;
        return pages == null ? '' : t.aiWorkWikiPages(pages);
      case WorkKind.wikiRead:
        final range = step.paragraphRange;
        return range == null
            ? ''
            : t.aiWorkParagraphs(range.$1 + 1, range.$2 + 1);
      default:
        return '';
    }
  }
}