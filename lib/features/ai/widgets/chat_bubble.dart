import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/agent/agent_provider.dart';
import '../../../core/agent/fact_check_agent.dart';
import '../../../core/agent/react_loop.dart';
import '../../../core/llm/llm_client.dart';
import '../../../shared/providers/theme_provider.dart';
import '../../../shared/l10n/l10n.dart';
import '../../../shared/theme/app_theme.dart';

/// Renders a single chat bubble with support for ReAct steps disclosure
/// and lazy loading of citations.
class ChatBubble extends ConsumerStatefulWidget {
  final ChatMessage message;

  const ChatBubble({super.key, required this.message});

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

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!isUser) ...[
            _buildAvatar(theme, isRobot: true),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment:
                  isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                // ── Assistant ReAct Steps (collapsible) ──────
                if (!isUser && msg.steps.isNotEmpty) ...[
                  _buildReActStepsSection(theme),
                  const SizedBox(height: 4),
                ],
                if (!isUser && msg.factCheckVerdict != null) ...[
                  _buildVerdictBanner(theme, msg.factCheckVerdict!),
                  const SizedBox(height: 6),
                ],

                // ── Message Content Box ──────────────────────
                if (isUser)
                  _buildUserContentBox(theme)
                else
                  _buildAssistantContentBox(theme),
              ],
            ),
          ),
          if (isUser) ...[
            const SizedBox(width: 8),
            _buildAvatar(theme, isRobot: false),
          ],
        ],
      ),
    );
  }

  Widget _buildAvatar(AppThemeTokens theme, {required bool isRobot}) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: isRobot
            ? theme.accentPrimary.withValues(alpha: 0.15)
            : theme.bgSecondary,
        shape: BoxShape.circle,
        border: Border.all(
          color: isRobot
              ? theme.accentPrimary.withValues(alpha: 0.4)
              : theme.divider,
          width: 1,
        ),
      ),
      child: Center(
        child: Icon(
          isRobot ? Icons.psychology_rounded : Icons.person_rounded,
          size: 20,
          color: isRobot ? theme.accentPrimary : theme.textPrimary,
        ),
      ),
    );
  }

  Widget _buildUserContentBox(AppThemeTokens theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: theme.accentPrimary.withValues(alpha: 0.15),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(12),
          bottomLeft: Radius.circular(12),
          bottomRight: Radius.circular(12),
        ),
        border: Border.all(
          color: theme.accentPrimary.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Text(
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
    if (content == '[FACT_CHECK_ERROR]') {
      content = context.t.importErrorOccurred;
    } else if (content == '[FACT_CHECK_CANCELED]') {
      content = context.t.aiCancel;
    } else if (content == '[ROLEPLAY_ERROR]') {
      content = context.t.aiRoleplayError;
    } else if (content == '[ROLEPLAY_CANCELED]') {
      content = context.t.aiRoleplayCanceled;
    }

    // Scan for citation UUIDs
    final uuidRegex = RegExp(
        r'\[([a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12})\]');
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: theme.cardSurface,
            borderRadius: const BorderRadius.only(
              topRight: Radius.circular(12),
              bottomLeft: Radius.circular(12),
              bottomRight: Radius.circular(12),
            ),
            border: Border.all(
              color: theme.cardBorder,
              width: 1,
            ),
          ),
          child: formattedContent.trim().isEmpty && msg.isStreaming
              ? _buildTypingIndicator(theme)
              : MarkdownBody(
                  data: formattedContent,
                  styleSheet:
                      MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
                    p: theme.bodyFont
                        .copyWith(color: theme.textPrimary, height: 1.5),
                    h1: theme.titleFont
                        .copyWith(color: theme.textPrimary, fontSize: 18),
                    h2: theme.titleFont
                        .copyWith(color: theme.textPrimary, fontSize: 16),
                    h3: theme.titleFont
                        .copyWith(color: theme.textPrimary, fontSize: 14),
                    a: theme.bodyFont.copyWith(color: theme.accentPrimary),
                    listBullet:
                        theme.bodyFont.copyWith(color: theme.textPrimary),
                    code: theme.bodyFont.copyWith(
                      color: theme.accentSecondary,
                      backgroundColor: theme.bgPrimary,
                    ),
                    blockquote:
                        theme.bodyFont.copyWith(color: theme.textSecondary),
                    blockquoteDecoration: BoxDecoration(
                      color: theme.bgPrimary,
                      border: Border(
                        left: BorderSide(color: theme.accentPrimary, width: 3),
                      ),
                    ),
                  ),
                ),
        ),
        if (citationIds.isNotEmpty) const SizedBox(height: 8),
        if (msg.factCheckVerdict != null && _evidenceObservations.isNotEmpty)
          _buildEvidenceSection(theme),
      ],
    );
  }

  List<String> get _evidenceObservations => widget.message.steps
      .where((step) =>
          step.type == ReActEventType.toolObservation &&
          step.content.contains('Source Kind: GameData'))
      .map((step) => step.content)
      .toList(growable: false);

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
                )),
          ],
        ),
      ),
    );
  }

  Widget _buildEvidenceSection(AppThemeTokens theme) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: ExpansionTile(
        initiallyExpanded: _showEvidence,
        onExpansionChanged: (value) => setState(() => _showEvidence = value),
        tilePadding: const EdgeInsets.symmetric(horizontal: 10),
        childrenPadding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
        leading: Icon(Icons.source_rounded, color: theme.accentPrimary),
        title: Text(
          context.t.aiEvidenceTitle(_evidenceObservations.length),
          style: theme.titleFont.copyWith(fontSize: 13),
        ),
        children: [
          for (final observation in _evidenceObservations)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(top: 6),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: theme.bgPrimary,
                border: Border.all(color: theme.divider),
                borderRadius: BorderRadius.circular(4),
              ),
              child: SelectableText(
                observation,
                style: theme.bodyFont.copyWith(
                  color: theme.textSecondary,
                  fontSize: 11,
                  height: 1.4,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTypingIndicator(AppThemeTokens theme) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Thinking',
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
    var statusText = 'Completed reasoning';
    var isThinking = false;
    if (widget.message.isStreaming) {
      isThinking = true;
      if (widget.message.steps.isNotEmpty) {
        final lastStep = widget.message.steps.last;
        if (lastStep.type == ReActEventType.toolCall) {
          statusText = 'Using tool: ${lastStep.toolName}';
        } else if (lastStep.type == ReActEventType.thought) {
          statusText = 'Reasoning...';
        } else {
          statusText = 'Processing...';
        }
      } else {
        statusText = 'Thinking...';
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
                    color: theme.accentPrimary,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      '$statusText ($stepsCount steps)',
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
          if (_showSteps)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Divider(height: 10),
                  ...widget.message.steps
                      .map((step) => _buildStepRow(theme, step)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStepRow(AppThemeTokens theme, ReActStep step) {
    IconData icon;
    Color color;
    String prefix;

    switch (step.type) {
      case ReActEventType.thought:
        icon = Icons.lightbulb_outline_rounded;
        color = theme.accentPrimary;
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
