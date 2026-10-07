import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/agent/agent_provider.dart';
import '../../core/llm/llm_provider.dart' show deepThinkingProvider;
import '../../shared/l10n/l10n.dart';
import '../../shared/providers/handoff_provider.dart';
import '../../shared/providers/settings_provider.dart';
import '../../shared/providers/theme_provider.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/smooth_page_route.dart';
import 'chat_history_page.dart';
import 'reading_history_page.dart';
import 'widgets/ask_composer.dart';
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

class _AiChatPageState extends ConsumerState<AiChatPage>
    with SingleTickerProviderStateMixin {
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  // Ask tab first; the wiki handoff sets the mode, not the tab.
  late final TabController _tabController = TabController(length: 2, vsync: this)
    ..addListener(() {
      if (!_tabController.indexIsChanging && mounted) setState(() {});
    });
  bool _handledInitialWikiContext = false;

  /// R17d: the list never follows a streaming answer — the thinking, the
  /// steps and the answer grow below and the reader scrolls at their own
  /// pace. Only a new question scrolls (once) to the end. The ↓ button
  /// shows whenever the end is out of view.
  bool _showJumpToEnd = false;

  @override
  void dispose() {
    _tabController.dispose();
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// Called on scrolling and on content size changes.
  bool _onScrollMetrics(ScrollMetrics metrics) {
    final away = metrics.maxScrollExtent - metrics.pixels > 48;
    if (away != _showJumpToEnd) setState(() => _showJumpToEnd = away);
    return false;
  }

  /// Animates to the end; [afterFrame] when the content just changed and
  /// is not laid out yet.
  void _scrollToBottom({bool afterFrame = false}) {
    void go() {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }

    if (afterFrame) {
      WidgetsBinding.instance.addPostFrameCallback((_) => go());
    } else {
      go();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider);
    final isConfigured = ref.watch(apiConfigProvider).isValid;
    _dispatchInitialWikiContext(isConfigured);
    // The library's "ask about it": the text goes into the question box for
    // the user to finish; nothing is sent.
    ref.listen<String?>(askDraftProvider, (_, draft) {
      if (draft == null) return;
      ref.read(askDraftProvider.notifier).state = null;
      _tabController.animateTo(0);
      _inputController.value = TextEditingValue(
        text: draft,
        selection: TextSelection.collapsed(offset: draft.length),
      );
    });

    // R15: one bar — the Ask / Roleplay switch where the title was, the
    // conversation actions on the right (Ask tab only).
    final onAsk = _tabController.index == 0;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: theme.bgSecondary,
        elevation: 0,
        titleSpacing: 4,
        title: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          dividerColor: Colors.transparent,
          indicatorColor: theme.accentPrimary,
          labelColor: theme.accentText,
          unselectedLabelColor: theme.textSecondary,
          labelStyle: theme.titleFont.copyWith(
            fontSize: 17,
            fontWeight: FontWeight.bold,
          ),
          unselectedLabelStyle: theme.titleFont.copyWith(fontSize: 17),
          tabs: [
            Tab(text: context.t.aiTabAsk),
            Tab(text: context.t.aiTabRoleplay),
          ],
        ),
        actions: [
          if (onAsk && isConfigured) ..._buildAskActions(theme),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // ── Ask Tab (unified: summarize / verify / investigate) ──
          isConfigured ? _buildAskTab(theme) : _buildConfigRequiredTab(theme),

          isConfigured ? const RoleplayTab() : _buildConfigRequiredTab(theme),
        ],
      ),
    );
  }

  /// History and new-conversation buttons plus a menu with retry / clear.
  List<Widget> _buildAskActions(AppThemeTokens theme) {
    final chatHistory = ref.watch(askChatProvider);
    final chatNotifier = ref.read(askChatProvider.notifier);
    final isSending = chatHistory.isNotEmpty && chatHistory.last.isStreaming;
    return [
      IconButton(
        onPressed: isSending
            ? null
            : () => Navigator.of(context).push(
                  smoothPageRoute<void>(
                    builder: (_) => const ChatHistoryPage(),
                  ),
                ),
        tooltip: context.t.aiHistoryTitle,
        icon: const Icon(Icons.history_rounded),
      ),
      IconButton(
        key: const ValueKey('ask-reading-history'),
        onPressed: () => Navigator.of(context).push(
          smoothPageRoute<void>(
            builder: (_) => const ReadingHistoryPage(),
          ),
        ),
        tooltip: context.t.readingHistoryTitle,
        icon: const Icon(Icons.menu_book_outlined),
      ),
      IconButton(
        onPressed: isSending ? null : chatNotifier.newSession,
        tooltip: context.t.aiNewConversation,
        icon: const Icon(Icons.add_comment_outlined),
      ),
      if (chatHistory.isNotEmpty)
        PopupMenuButton<String>(
          tooltip: context.t.aiMoreActions,
          icon: const Icon(Icons.more_vert_rounded),
          color: theme.cardSurface,
          onSelected: (value) {
            if (value == 'retry') chatNotifier.retryLast();
            if (value == 'clear') _confirmClearHistory(context, chatNotifier);
          },
          itemBuilder: (context) => [
            PopupMenuItem(
              value: 'retry',
              enabled: !isSending,
              child: ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.refresh_rounded),
                title: Text(context.t.aiRetry),
              ),
            ),
            PopupMenuItem(
              value: 'clear',
              child: ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.delete_sweep_rounded, color: theme.danger),
                title: Text(context.t.aiClearHistory),
              ),
            ),
          ],
        ),
    ];
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
              color: theme.onAccent,
            ),
            label: Text(context.t.aiSettingsGoTo),
            style: FilledButton.styleFrom(
              backgroundColor: theme.accentPrimary,
              foregroundColor: theme.onAccent,
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
      // A new question (not a streaming update): bring it into view once.
      if ((prev?.length ?? 0) < next.length) _scrollToBottom(afterFrame: true);
    });

    // R15: the conversation fills the tab; actions live in the app bar. The
    // question box may grow to half or all of the tab (its height budget).
    return LayoutBuilder(
      builder: (context, constraints) => Column(
      children: [
        Expanded(
          child: chatHistory.isEmpty
              ? _buildEmptyState(theme)
              : Stack(
                  children: [
                    NotificationListener<ScrollMetricsNotification>(
                      onNotification: (n) => n.depth == 0 &&
                          _onScrollMetrics(n.metrics),
                      child: NotificationListener<ScrollUpdateNotification>(
                        onNotification: (n) => n.depth == 0 &&
                            _onScrollMetrics(n.metrics),
                        child: ListView.builder(
                          key: const ValueKey('ask-chat-list'),
                          controller: _scrollController,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          itemCount: chatHistory.length,
                          itemBuilder: (context, index) {
                            return ChatBubble(message: chatHistory[index]);
                          },
                        ),
                      ),
                    ),
                    if (_showJumpToEnd)
                      Positioned(
                        right: 16,
                        bottom: 12,
                        child: Material(
                          color: theme.accentPrimary,
                          shape: const CircleBorder(),
                          elevation: 3,
                          shadowColor: Colors.black.withValues(alpha: 0.3),
                          child: IconButton(
                            key: const ValueKey('scroll-to-bottom'),
                            tooltip: context.t.aiScrollToBottom,
                            onPressed: _scrollToBottom,
                            icon: Icon(
                              Icons.arrow_downward_rounded,
                              color: theme.onAccent,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
        ),
        AskComposer(
          controller: _inputController,
          theme: theme,
          isSending: isSending,
          onSend: isSending ? chatNotifier.cancel : _handleAskSend,
          hintText: context.t.aiAskInputPlaceholder,
          maxHeight: constraints.maxHeight,
          leading: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDeepThinkingToggle(theme),
              const SizedBox(width: 6),
              _buildAnswerOptions(theme),
            ],
          ),
        ),
      ],
      ),
    );
  }

  /// R16: "深度思考" — lets the answer writer think (low effort) for the
  /// next questions; off by default. Retrieval is the same either way.
  Widget _buildDeepThinkingToggle(AppThemeTokens theme) {
    final on = ref.watch(deepThinkingProvider);
    return Tooltip(
      message: context.t.aiDeepThinkingTooltip,
      child: Semantics(
        button: true,
        toggled: on,
        label: context.t.aiDeepThinking,
        child: InkWell(
          key: const ValueKey('deep-thinking-toggle'),
          borderRadius: BorderRadius.circular(16),
          onTap: () => ref.read(deepThinkingProvider.notifier).state = !on,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: on
                  ? theme.accentPrimary.withValues(alpha: 0.18)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: on
                    ? theme.accentText.withValues(alpha: 0.4)
                    : theme.divider,
                width: 0.5,
              ),
            ),
            child: Icon(
              Icons.psychology_alt_rounded,
              size: 18,
              color: on ? theme.accentText : theme.textSecondary,
            ),
          ),
        ),
      ),
    );
  }

  /// R18 passes after the draft, both optional: "复核" (a reader's review)
  /// and "提要" (a digest of a long answer). One small button with a menu, so
  /// the toolbar stays short; lit while either pass is on.
  Widget _buildAnswerOptions(AppThemeTokens theme) {
    final options = ref.watch(answerOptionsProvider);
    final on = options.review || options.digest;
    PopupMenuItem<String> item(String value, bool checked, String title,
            String hint,) =>
        CheckedPopupMenuItem<String>(
          key: ValueKey('answer-option-$value'),
          value: value,
          checked: checked,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: theme.bodyFont.copyWith(fontSize: 14)),
              const SizedBox(height: 2),
              Text(
                hint,
                style: theme.bodyFont
                    .copyWith(fontSize: 11.5, color: theme.textSecondary),
              ),
            ],
          ),
        );
    return PopupMenuButton<String>(
      key: const ValueKey('answer-options'),
      tooltip: context.t.aiAnswerOptions,
      color: theme.surfaceElevated,
      constraints: const BoxConstraints(maxWidth: 300),
      onSelected: (value) => ref.read(answerOptionsProvider.notifier).set(
            value == 'review'
                ? options.copyWith(review: !options.review)
                : options.copyWith(digest: !options.digest),
          ),
      itemBuilder: (context) => [
        item('review', options.review, context.t.aiAnswerReview,
            context.t.aiAnswerReviewHint,),
        item('digest', options.digest, context.t.aiAnswerDigest,
            context.t.aiAnswerDigestHint,),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: on
              ? theme.accentPrimary.withValues(alpha: 0.18)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: on ? theme.accentText.withValues(alpha: 0.4) : theme.divider,
            width: 0.5,
          ),
        ),
        child: Icon(
          Icons.tune_rounded,
          size: 18,
          color: on ? theme.accentText : theme.textSecondary,
        ),
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
            const SizedBox(height: 6),
            Text(
              context.t.aiAskSource,
              style: theme.bodyFont
                  .copyWith(color: theme.textSecondary, fontSize: 11),
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

  void _handleAskSend() {
    final text = _inputController.text.trim();
    if (text.isEmpty) return;

    _inputController.clear();
    ref.read(askChatProvider.notifier).sendMessage(text);
  }

  void _dispatchInitialWikiContext(bool isConfigured) {
    final wikiContext = widget.initialWikiContext;
    if (_handledInitialWikiContext || wikiContext == null || !isConfigured) {
      return;
    }
    _handledInitialWikiContext = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // The prompt itself says whether to summarize or to check a claim.
      ref.read(askChatProvider.notifier).sendMessage(
            buildWikiAiPrompt(wikiContext),
          );
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
