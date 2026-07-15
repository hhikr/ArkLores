import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/agent/agent_provider.dart';
import '../../shared/l10n/l10n.dart';
import '../../shared/providers/settings_provider.dart';
import '../../shared/providers/theme_provider.dart';
import '../../shared/theme/app_theme.dart';
import 'wiki_ai_context.dart';
import 'widgets/chat_bubble.dart';
import 'widgets/roleplay_tab.dart';

/// The main AI Chat Page hosting the three AI modes (FactCheck, Summary, Roleplay).
///
/// Features a TabBar for fact-check, summary, and roleplay modes.
class AiChatPage extends ConsumerStatefulWidget {
  final WikiAiContext? initialWikiContext;

  const AiChatPage({super.key, this.initialWikiContext});

  @override
  ConsumerState<AiChatPage> createState() => _AiChatPageState();
}

class _AiChatPageState extends ConsumerState<AiChatPage> {
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _handledInitialWikiContext = false;

  int get _initialTabIndex {
    final target = widget.initialWikiContext?.target;
    if (target == WikiAiTarget.factCheck) return 0;
    return 1;
  }

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
      length: 3,
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
              Tab(text: context.t.aiTabFactCheck),
              Tab(text: context.t.aiTabSummary),
              Tab(text: context.t.aiTabRoleplay),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            isConfigured
                ? _buildFactCheckTab(theme)
                : _buildConfigRequiredTab(theme),

            // ── Summary Tab (Functional) ─────────────────────
            isConfigured
                ? _buildSummaryChatTab(theme)
                : _buildConfigRequiredTab(theme),

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
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pushNamed(context, '/api-settings');
            },
            icon: const Icon(Icons.settings_rounded),
            label: Text(context.t.aiSettingsGoTo),
            style: ElevatedButton.styleFrom(
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

  Widget _buildSummaryChatTab(AppThemeTokens theme) {
    final chatHistory = ref.watch(summaryChatProvider);
    final chatNotifier = ref.read(summaryChatProvider.notifier);
    final isSending = chatHistory.isNotEmpty && chatHistory.last.isStreaming;

    // Listen to changes in chat history to scroll to bottom
    ref.listen(summaryChatProvider, (prev, next) {
      if (prev?.length != next.length ||
          (next.isNotEmpty && next.last.isStreaming)) {
        _scrollToBottom();
      }
    });

    return Column(
      children: [
        // ── Active profile display & Clear history ───────
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: theme.bgSecondary.withValues(alpha: 0.5),
          child: Row(
            children: [
              Icon(Icons.storage_rounded, size: 14, color: theme.textSecondary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  context.t.aiSummarySource,
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
                  icon: Icon(Icons.delete_sweep_rounded,
                      color: theme.danger, size: 18),
                  tooltip: context.t.aiClearHistory,
                  onPressed: () => _confirmClearHistory(context, chatNotifier),
                  constraints: const BoxConstraints(),
                  padding: EdgeInsets.zero,
                ),
            ],
          ),
        ),

        // ── Chat List ────────────────────────────────────
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

        // ── Input box ────────────────────────────────────
        _buildInputArea(
          theme,
          isSending,
          onSend: isSending ? chatNotifier.cancel : _handleSummarySend,
          hintText: context.t.aiSummaryInputPlaceholder,
          isCancel: isSending,
        ),
      ],
    );
  }

  Widget _buildEmptyState(AppThemeTokens theme) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(
              Icons.summarize_rounded,
              size: 48,
              color: theme.accentPrimary.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 12),
            Text(
              context.t.aiTabSummary,
              style: theme.titleFont
                  .copyWith(fontSize: 20, color: theme.textPrimary),
            ),
            const SizedBox(height: 8),
            Text(
              context.t.aiSummaryEmpty,
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
                _buildSuggestionChip(theme, context.t.aiSummarySuggestionAmiya),
                _buildSuggestionChip(
                    theme, context.t.aiSummarySuggestionKaltsit),
                _buildSuggestionChip(theme, context.t.aiSummarySuggestionRhine),
                _buildSuggestionChip(
                    theme, context.t.aiSummarySuggestionChernobog),
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

  Widget _buildFactCheckTab(AppThemeTokens theme) {
    final history = ref.watch(factCheckChatProvider);
    final notifier = ref.read(factCheckChatProvider.notifier);
    final isSending = history.isNotEmpty && history.last.isStreaming;
    ref.listen(factCheckChatProvider, (previous, next) => _scrollToBottom());

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: theme.bgSecondary.withValues(alpha: 0.5),
          child: Row(
            children: [
              Icon(Icons.verified_outlined,
                  size: 16, color: theme.accentPrimary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  context.t.aiFactCheckSource,
                  style: theme.bodyFont
                      .copyWith(color: theme.textSecondary, fontSize: 12),
                ),
              ),
              if (history.isNotEmpty)
                IconButton(
                  onPressed: notifier.retryLast,
                  tooltip: context.t.aiRetry,
                  icon: const Icon(Icons.refresh_rounded),
                  visualDensity: VisualDensity.compact,
                ),
              if (history.isNotEmpty)
                IconButton(
                  onPressed: notifier.clearChat,
                  tooltip: context.t.aiClearHistory,
                  icon: Icon(Icons.delete_sweep_rounded, color: theme.danger),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
        ),
        Expanded(
          child: history.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      context.t.aiFactCheckEmpty,
                      textAlign: TextAlign.center,
                      style: theme.bodyFont.copyWith(
                        color: theme.textSecondary,
                        fontSize: 14,
                      ),
                    ),
                  ),
                )
              : ListView.builder(
                  controller: _scrollController,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  itemCount: history.length,
                  itemBuilder: (context, index) =>
                      ChatBubble(message: history[index]),
                ),
        ),
        _buildInputArea(
          theme,
          isSending,
          onSend: isSending ? notifier.cancel : _handleFactCheckSend,
          hintText: context.t.aiFactCheckInputPlaceholder,
          isCancel: isSending,
        ),
      ],
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
                        horizontal: 16, vertical: 10),
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

  void _handleSummarySend() {
    final text = _inputController.text.trim();
    if (text.isEmpty) return;

    _inputController.clear();
    ref.read(summaryChatProvider.notifier).sendMessage(text);
  }

  void _handleFactCheckSend() {
    final text = _inputController.text.trim();
    if (text.isEmpty) return;
    _inputController.clear();
    ref.read(factCheckChatProvider.notifier).sendMessage(text);
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
      switch (wikiContext.target) {
        case WikiAiTarget.summary:
          ref.read(summaryChatProvider.notifier).sendMessage(prompt);
          break;
        case WikiAiTarget.factCheck:
          ref.read(factCheckChatProvider.notifier).sendMessage(prompt);
          break;
      }
    });
  }

  void _confirmClearHistory(
      BuildContext context, SummaryChatNotifier notifier) {
    final theme = ref.read(themeProvider);

    showDialog(
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
