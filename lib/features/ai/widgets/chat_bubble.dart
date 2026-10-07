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
import '../evidence_observation.dart';
import '../investigation_ui.dart';
import '../story_labels_provider.dart';
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
          if (msg.stats != null) _buildStatsLine(theme, msg.stats!),
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
        borderRadius: BorderRadius.circular(16),
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
          Icons.check_circle_rounded,
          Colors.green,
          context.t.aiVerdictSupported
        ),
      FactCheckVerdict.refuted => (
          Icons.cancel_rounded,
          theme.danger,
          context.t.aiVerdictRefuted
        ),
      FactCheckVerdict.uncertain => (
          Icons.help_rounded,
          Colors.amber.shade800,
          context.t.aiVerdictUncertain
        ),
      FactCheckVerdict.unavailable => (
          Icons.remove_circle_outline_rounded,
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
      if (msg.steps.isNotEmpty)
        context.t.aiStepsStatus(context.t.aiReasoningComplete, msg.steps.length),
    ];
    final icon = status == StoryAnswerStatus.answered
        ? Icons.check_circle_outline_rounded
        : Icons.error_outline_rounded;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          key: const ValueKey('answer-header'),
          onTap: msg.steps.isEmpty
              ? null
              : () => setState(() => _showSteps = !_showSteps),
          borderRadius: BorderRadius.circular(6),
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
                        ? Icons.expand_less_rounded
                        : Icons.chevron_right_rounded,
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
          borderRadius: BorderRadius.circular(6),
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
                        ? Icons.expand_less_rounded
                        : Icons.chevron_right_rounded,
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
                      ? Icons.expand_less_rounded
                      : Icons.chevron_right_rounded,
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
              borderRadius: BorderRadius.circular(8),
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
    if (ids.isEmpty && records.isEmpty) return const SizedBox.shrink();
    final entries = ids.isEmpty
        ? const <String, StoryCatalogEntry>{}
        : ref
                .watch(storyCatalogEntriesProvider(storyLabelsKey(ids)))
                .valueOrNull ??
            const <String, StoryCatalogEntry>{};
    final groups = groupCitations(cited, entries);
    final total =
        groups.fold<int>(0, (n, g) => n + g.citationCount) + records.length;
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
                  isOpen ? Icons.expand_more_rounded : Icons.chevron_right_rounded,
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
        InkWell(
          key: ValueKey('cite:$key'),
          onTap: onTap ?? () => _toggle(key),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: selected
                  ? theme.accentPrimary.withValues(alpha: 0.15)
                  : theme.bgSecondary,
              borderRadius: BorderRadius.circular(8),
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
        leading: Icon(Icons.source_rounded, color: theme.accentText),
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
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.divider, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _showSteps = !_showSteps),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Row(
                children: [
                  Icon(
                    _showSteps
                        ? Icons.visibility_rounded
                        : Icons.visibility_off_rounded,
                    size: 14,
                    color: theme.accentText,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      context.t.aiStepsStatus(statusText, stepsCount),
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

  Widget _buildStepsList(AppThemeTokens theme) => Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Divider(height: 10),
            ...widget.message.steps.map((step) => _buildStepRow(theme, step)),
          ],
        ),
      );

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
          borderRadius: BorderRadius.circular(4),
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
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(label,
            style: theme.bodyFont.copyWith(
                color: theme.accentText,
                fontSize: 10,
                fontWeight: FontWeight.bold,),),
      );

  Widget _buildStepRow(AppThemeTokens theme, ReActStep step) {
    IconData icon;
    Color color;
    String prefix;

    switch (step.type) {
      case ReActEventType.thought:
        icon = Icons.lightbulb_outline_rounded;
        color = theme.accentText;
        prefix = 'Thought';
        break;
      case ReActEventType.toolCall:
        icon = Icons.construction_rounded;
        color = theme.accentSecondary;
        prefix = 'Action [${step.toolName}]';
        break;
      case ReActEventType.toolObservation:
        icon = Icons.analytics_outlined;
        color = theme.wikiBadgeColor;
        prefix = 'Observation';
        break;
      case ReActEventType.error:
        icon = Icons.error_outline_rounded;
        color = theme.danger;
        prefix = 'Error';
        break;
      default:
        icon = Icons.info_outline_rounded;
        color = theme.textSecondary;
        prefix = 'Step';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 12, color: color),
              const SizedBox(width: 6),
              Text(
                prefix,
                style: theme.titleFont.copyWith(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Padding(
            padding: const EdgeInsets.only(left: 18),
            child: Text(
              step.content.trim(),
              style: theme.bodyFont.copyWith(
                color: theme.textSecondary,
                fontSize: 11,
                height: 1.4,
              ),
              maxLines: step.type == ReActEventType.toolObservation ? 4 : 20,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
