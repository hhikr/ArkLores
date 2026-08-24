import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/agent/agent_provider.dart';
import '../../core/agent/question_router.dart';
import '../../shared/l10n/l10n.dart';
import '../../shared/providers/settings_provider.dart';
import '../../shared/providers/theme_provider.dart';
import '../../shared/theme/app_theme.dart';
import 'widgets/chat_bubble.dart';
import 'widgets/roleplay_tab.dart';
import 'wiki_ai_context.dart';

/// The main AI Chat Page hosting the three AI modes (FactCheck, Summary, Roleplay).
///
/// Features a TabBar for fact-check, summary, and roleplay modes.
class AiChatPage extends ConsumerStatefulWidget {

  const AiChatPage({super.key, this.initialWikiContext});
  final WikiAiContext? initialWikiContext;

  @override
  ConsumerState<AiChatPage> createState() => _AiChatPageState();
}

class _AiChatPageState extends ConsumerState<AiChatPage> {
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _handledInitialWikiContext = false;

  int get _initialTabIndex => 0; // Ask tab; wiki handoff sets the mode.

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider);
    final isConfigured = ref.watch(apiConfigProvider).isValid;
    _dispatchInitialWikiContext(isConfigured);

    return DefaultTabController(
      length: 2,
      initialIndex: _initialTabIndex,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: theme.bgSecondary,
          elevation: 0,
          title: Text(
            context.t.aiChatTitle,
            style: theme.titleFont.copyWith(fontSize: 20),
          ),
          bottom: TabBar(
            indicatorColor: theme.accentPrimary,
            labelColor: theme.accentPrimary,
            unselectedLabelColor: theme.textSecondary,
            labelStyle: theme.titleFont.copyWith(fontWeight: FontWeight.bold),
            unselectedLabelStyle: theme.titleFont,
            tabs: [
              Tab(text: context.t.aiTabAsk),
              Tab(text: context.t.aiTabRoleplay),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            // ── Ask Tab (unified: summarize / verify / investigate) ──
            isConfigured ? _buildAskTab(theme) : _buildConfigRequiredTab(theme),

            isConfigured ? const RoleplayTab() : _buildConfigRequiredTab(theme),
          ],
        ),
      ),
    );
  }

  Widget _buildConfigRequiredTab(AppThemeTokens theme) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.vpn_key_off_rounded,
            size: 64,
            color: theme.danger.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 16),
          Text(
            'API Key Required',
            style: theme.titleFont
                .copyWith(fontSize: 20, color: theme.textPrimary),
          ),
          const SizedBox(height: 12),
          Text(
            context.t.aiSettingsRequired,
            style: theme.bodyFont.copyWith(color: theme.textSecondary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () {
              Navigator.pushNamed(context, '/api-settings');
            },
            icon: Icon(
              Icons.settings_rounded,
              size: 21,
              color: theme.isDark ? Colors.black : Colors.white,
            ),
            label: Text(context.t.aiSettingsGoTo),
            style: FilledButton.styleFrom(
              backgroundColor: theme.accentPrimary,
              foregroundColor: theme.isDark ? Colors.black : Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              textStyle: theme.titleFont.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  /// Unified Ask tab: mode selector + chat list + input. The same message
  /// list renders summary answers, fact-check verdicts and investigation
  /// cards (chat_bubble dispatches by content).
  Widget _buildAskTab(AppThemeTokens theme) {
    final chatHistory = ref.watch(askChatProvider);
    final chatNotifier = ref.read(askChatProvider.notifier);
    final isSending = chatHistory.isNotEmpty && chatHistory.last.isStreaming;

    ref.listen(askChatProvider, (prev, next) {
      if (prev?.length != next.length ||
          (next.isNotEmpty && next.last.isStreaming)) {
        _scrollToBottom();
      }
    });

    return Column(
      children: [
        _buildModeSelector(theme),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: theme.bgSecondary.withValues(alpha: 0.5),
          child: Row(
            children: [
              Icon(Icons.auto_awesome_rounded,
                  size: 16, color: theme.accentPrimary,),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  context.t.aiAskSource,
                  style: theme.bodyFont
                      .copyWith(color: theme.textSecondary, fontSize: 12),
                ),
              ),
              if (chatHistory.isNotEmpty)
                IconButton(
                  onPressed: isSending ? null : chatNotifier.retryLast,
                  tooltip: context.t.aiRetry,
                  icon: const Icon(Icons.refresh_rounded),
                  visualDensity: VisualDensity.compact,
                ),
              if (chatHistory.isNotEmpty)
                IconButton(
                  onPressed: () =>
                      _confirmClearHistory(context, chatNotifier),
                  tooltip: context.t.aiClearHistory,
                  icon: Icon(Icons.delete_sweep_rounded, color: theme.danger),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
        ),
        Expanded(
          child: chatHistory.isEmpty
              ? _buildEmptyState(theme)
              : ListView.builder(
                  controller: _scrollController,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  itemCount: chatHistory.length,
                  itemBuilder: (context, index) {
                    return ChatBubble(message: chatHistory[index]);
                  },
                ),
        ),
        _buildInputArea(
          theme,
          isSending,
          onSend: isSending ? chatNotifier.cancel : _handleAskSend,
          hintText: context.t.aiAskInputPlaceholder,
          isCancel: isSending,
        ),
      ],
    );
  }

  /// Mode picker: Auto (LLM-routed) or one of the three pinned workflows.
  Widget _buildModeSelector(AppThemeTokens theme) {
    final mode = ref.watch(aiModeProvider);
    final desc = switch (mode) {
      AiMode.auto => context.t.aiModeAutoDesc,
      AiMode.summarize => context.t.aiModeSummarizeDesc,
      AiMode.verify => context.t.aiModeVerifyDesc,
      AiMode.investigate => context.t.aiModeInvestigateDesc,
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
      color: theme.bgSecondary.withValues(alpha: 0.3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final candidate in AiMode.values)
                ChoiceChip(
                  label: Text(
                    switch (candidate) {
                      AiMode.auto => context.t.aiModeAuto,
                      AiMode.summarize => context.t.aiModeSummarize,
                      AiMode.verify => context.t.aiModeVerify,
                      AiMode.investigate => context.t.aiModeInvestigate,
                    },
                  ),
                  selected: candidate == mode,
                  onSelected: (_) {
                    ref.read(aiModeProvider.notifier).state = candidate;
                  },
                  labelStyle: theme.bodyFont.copyWith(fontSize: 12),
                  selectedColor: theme.accentPrimary.withValues(alpha: 0.2),
                  backgroundColor: theme.bgPrimary,
                  side: BorderSide(color: theme.divider, width: 0.5),
                  visualDensity: VisualDensity.compact,
                  showCheckmark: false,
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            desc,
            style: theme.bodyFont.copyWith(
              color: theme.textSecondary,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(AppThemeTokens theme) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(
              Icons.auto_awesome_rounded,
              size: 48,
              color: theme.accentPrimary.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 12),
            Text(
              context.t.aiTabAsk,
              style: theme.titleFont
                  .copyWith(fontSize: 20, color: theme.textPrimary),
            ),
            const SizedBox(height: 8),
            Text(
              context.t.aiAskEmpty,
              style: theme.bodyFont
                  .copyWith(color: theme.textSecondary, fontSize: 13),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                _buildSuggestionChip(theme, context.t.aiAskSuggestionAmiya),
                _buildSuggestionChip(theme, context.t.aiAskSuggestionVerify),
                _buildSuggestionChip(theme, context.t.aiAskSuggestionInvestigate),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSuggestionChip(AppThemeTokens theme, String text) {
    return ActionChip(
      label: Text(text),
      labelStyle:
          theme.bodyFont.copyWith(fontSize: 12, color: theme.textPrimary),
      backgroundColor: theme.bgSecondary,
      side: BorderSide(color: theme.divider, width: 0.5),
      onPressed: () {
        _inputController.text = text;
      },
    );
  }

  Widget _buildInputArea(
    AppThemeTokens theme,
    bool isSending, {
    required VoidCallback onSend,
    required String hintText,
    bool isCancel = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.bgSecondary,
        border: Border(top: BorderSide(color: theme.divider, width: 0.5)),
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: theme.bgPrimary,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: theme.divider, width: 0.5),
                ),
                child: TextField(
                  controller: _inputController,
                  style: theme.bodyFont.copyWith(color: theme.textPrimary),
                  cursorColor: theme.accentPrimary,
                  textInputAction: TextInputAction.send,
                  onSubmitted: isSending ? null : (_) => onSend(),
                  decoration: InputDecoration(
                    hintText: hintText,
                    hintStyle: theme.bodyFont
                        .copyWith(color: theme.textSecondary, fontSize: 13),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10,),
                    border: InputBorder.none,
                    isDense: true,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: onSend,
              icon: Icon(
                isCancel ? Icons.stop_rounded : Icons.send_rounded,
                color: isCancel ? theme.danger : theme.accentPrimary,
              ),
              tooltip: isCancel ? context.t.aiCancel : context.t.aiSend,
            ),
          ],
        ),
      ),
    );
  }

  void _handleAskSend() {
    final text = _inputController.text.trim();
    if (text.isEmpty) return;

    _inputController.clear();
    ref.read(askChatProvider.notifier).sendMessage(
          text,
          mode: ref.read(aiModeProvider),
        );
  }

  void _dispatchInitialWikiContext(bool isConfigured) {
    final wikiContext = widget.initialWikiContext;
    if (_handledInitialWikiContext || wikiContext == null || !isConfigured) {
      return;
    }
    _handledInitialWikiContext = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final prompt = buildWikiAiPrompt(wikiContext);
      final mode = switch (wikiContext.target) {
        WikiAiTarget.summary => AiMode.summarize,
        WikiAiTarget.factCheck => AiMode.verify,
      };
      ref.read(aiModeProvider.notifier).state = mode;
      ref.read(askChatProvider.notifier).sendMessage(prompt, mode: mode);
    });
  }

  void _confirmClearHistory(BuildContext context, AskChatNotifier notifier) {
    final theme = ref.read(themeProvider);

    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: theme.cardSurface,
          shape: RoundedRectangleBorder(
            borderRadius: theme.cardRadius,
            side: BorderSide(color: theme.cardBorder, width: 1),
          ),
          title: Text(
            context.t.aiClearHistory,
            style: theme.titleFont.copyWith(fontSize: 18),
          ),
          content: Text(
            context.t.aiClearHistoryConfirm,
            style: theme.bodyFont.copyWith(color: theme.textPrimary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                context.t.materialsCancel,
                style: theme.bodyFont.copyWith(color: theme.textSecondary),
              ),
            ),
            TextButton(
              onPressed: () {
                notifier.clearChat();
                Navigator.pop(context);
              },
              child: Text(
                context.t.aiClearConfirmBtn,
                style: theme.bodyFont.copyWith(
                  color: theme.danger,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
