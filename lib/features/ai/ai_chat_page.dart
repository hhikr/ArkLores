import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/agent/agent_provider.dart';
import '../../core/llm/llm_provider.dart' show embeddingClientProvider;
import '../../shared/l10n/l10n.dart';
import '../../shared/providers/settings_provider.dart';
import '../../shared/providers/theme_provider.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/theme/motion.dart';
import '../../shared/widgets/ef_widgets.dart';
import '../../shared/widgets/page_frame.dart';
import '../../shared/widgets/smooth_page_route.dart';
import 'chat_history_page.dart';
import 'widgets/answer_options_menu.dart';
import 'widgets/ask_composer.dart';
import 'widgets/chat_bubble.dart';

/// The Ask page: the conversation fills the page under the top bar (its
/// name and the conversation actions), the question box sits at the bottom.
class AiChatPage extends ConsumerStatefulWidget {
  const AiChatPage({super.key});

  @override
  ConsumerState<AiChatPage> createState() => _AiChatPageState();
}

class _AiChatPageState extends ConsumerState<AiChatPage> {
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  /// The conversation area takes the focus when it is touched (reading,
  /// opening a source, the buttons). A page opened from there gives the
  /// focus back to it on return, not to the question box, so the keyboard
  /// does not come up.
  final FocusNode _chatFocus = FocusNode(debugLabel: 'ask-chat');

  /// Height of the question box (with what it leaves for the tab bar below
  /// it), for the list's bottom padding.
  double _composerHeight = 0;

  /// R17d: the list never follows a streaming answer — the thinking, the
  /// steps and the answer grow below and the reader scrolls at their own
  /// pace. Only a new question scrolls (once) to the end. The ↓ button
  /// shows whenever the end is out of view.
  bool _showJumpToEnd = false;

  @override
  void dispose() {
    _chatFocus.dispose();
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
      final d = Motion.of(context, Motion.shutter);
      final end = _scrollController.position.maxScrollExtent;
      if (d == Duration.zero) {
        _scrollController.jumpTo(end);
      } else {
        _scrollController.animateTo(end, duration: d, curve: Motion.snap);
      }
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
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: isConfigured
          ? _buildAskTab(theme)
          : Stack(
              children: [
                _buildConfigRequiredTab(theme),
                MainTopBar(leading: _title()),
              ],
            ),
    );
  }

  /// The page's name in the top bar, after a back button when it was
  /// opened as a page of its own (from a wiki page).
  Widget _title() => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (ModalRoute.of(context)?.canPop ?? false)
            SquareIconButton(
              icon: Icons.arrow_back_sharp,
              tooltip: MaterialLocalizations.of(context).backButtonTooltip,
              filled: true,
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          Flexible(child: TopBarTitle(title: context.t.aiTabAsk, code: 'ask')),
        ],
      );

  /// The conversation actions in the top bar: the conversations, a new
  /// conversation, and a menu with retry / clear.
  Widget _buildActions(AppThemeTokens theme) {
    final chatHistory = ref.watch(askChatProvider);
    final chatNotifier = ref.read(askChatProvider.notifier);
    final isSending = chatHistory.isNotEmpty && chatHistory.last.isStreaming;
    return Row(
      key: const ValueKey('ask-floating-actions'),
      mainAxisSize: MainAxisSize.min,
      children: [
        SquareIconButton(
          key: const ValueKey('ask-chat-history'),
          onPressed: isSending
              ? null
              : () => Navigator.of(context).push(
                    smoothPageRoute<void>(
                      builder: (_) => const ChatHistoryPage(),
                    ),
                  ),
          tooltip: context.t.aiHistoryTitle,
          icon: Icons.history_sharp,
        ),
        SquareIconButton(
          key: const ValueKey('ask-new-conversation'),
          onPressed: isSending ? null : chatNotifier.newSession,
          tooltip: context.t.aiNewConversation,
          icon: Icons.add_comment_outlined,
        ),
        if (chatHistory.isNotEmpty)
          PopupMenuButton<String>(
            tooltip: context.t.aiMoreActions,
            icon: const Icon(Icons.more_vert_sharp),
            onSelected: (value) {
              if (value == 'retry') chatNotifier.retryLast();
              if (value == 'clear') _confirmClearHistory(chatNotifier);
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'retry',
                enabled: !isSending,
                height: 48,
                child: Row(
                  children: [
                    const Icon(Icons.refresh_sharp, size: 20),
                    const SizedBox(width: 12),
                    Text(context.t.aiRetry),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'clear',
                height: 48,
                child: Row(
                  children: [
                    Icon(Icons.delete_sweep_sharp,
                        size: 20, color: theme.danger,),
                    const SizedBox(width: 12),
                    Text(
                      context.t.aiClearHistory,
                      style: TextStyle(color: theme.danger),
                    ),
                  ],
                ),
              ),
            ],
          ),
      ],
    );
  }

  Widget _buildConfigRequiredTab(AppThemeTokens theme) {
    return Center(
      child: SingleChildScrollView(
        padding: pagePadding(context, const EdgeInsets.all(24)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: EmptyState(
            title: context.t.aiConfigRequiredTitle,
            text: context.t.aiSettingsRequired,
            action: AppButton(
              context.t.aiSettingsGoTo,
              kind: ButtonKind.go,
              icon: Icons.settings_sharp,
              onPressed: () => Navigator.pushNamed(context, '/api-settings'),
            ),
          ),
        ),
      ),
    );
  }

  /// The conversation (under the top bar) and the question box. Touching the
  /// conversation moves the focus off the question box ([_chatFocus]).
  Widget _buildAskTab(AppThemeTokens theme) {
    final chatHistory = ref.watch(askChatProvider);
    final chatNotifier = ref.read(askChatProvider.notifier);
    final isSending = chatHistory.isNotEmpty && chatHistory.last.isStreaming;

    ref.listen(askChatProvider, (prev, next) {
      // A new question (not a streaming update): bring it into view once.
      if ((prev?.length ?? 0) < next.length) _scrollToBottom(afterFrame: true);
    });

    // The list scrolls under the top bar and the question box; its padding
    // follows the box's height. The box may grow to half or all of the page
    // (its height budget).
    return LayoutBuilder(
      builder: (context, constraints) => Stack(
        children: [
          Positioned.fill(
            child: Focus(
              focusNode: _chatFocus,
              child: Listener(
                behavior: HitTestBehavior.translucent,
                onPointerDown: (_) {
                  if (!_chatFocus.hasFocus) _chatFocus.requestFocus();
                },
                child: chatHistory.isEmpty
                    ? _buildEmptyState(theme)
                    : _buildChatList(theme, chatHistory),
              ),
            ),
          ),
          MainTopBar(leading: _title(), trailing: _buildActions(theme)),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _SizeReporter(
              onHeight: (height) {
                if ((height - _composerHeight).abs() > 0.5) {
                  setState(() => _composerHeight = height);
                }
              },
              child: AskComposer(
                controller: _inputController,
                theme: theme,
                isSending: isSending,
                onSend: isSending ? chatNotifier.cancel : _handleAskSend,
                hintText: context.t.aiAskInputPlaceholder,
                maxHeight: constraints.maxHeight,
                leading: (card) => AnswerOptionsMenu(theme: theme, above: card),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The messages, with the ↓ button while the end is out of view.
  Widget _buildChatList(AppThemeTokens theme, List<ChatMessage> chatHistory) {
    final top = MediaQuery.paddingOf(context).top + topBarInset;
    return Stack(
      children: [
        NotificationListener<ScrollMetricsNotification>(
          onNotification: (n) => n.depth == 0 && _onScrollMetrics(n.metrics),
          child: NotificationListener<ScrollUpdateNotification>(
            onNotification: (n) => n.depth == 0 && _onScrollMetrics(n.metrics),
            child: ListView.builder(
              key: const ValueKey('ask-chat-list'),
              controller: _scrollController,
              padding: EdgeInsets.fromLTRB(
                16,
                top + 12,
                16,
                12 + _composerHeight,
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
            right: 12,
            bottom: 8 + _composerHeight,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: theme.cardSurface,
                border: Border.all(color: theme.divider),
              ),
              child: SquareIconButton(
                key: const ValueKey('scroll-to-bottom'),
                tooltip: context.t.aiScrollToBottom,
                onPressed: _scrollToBottom,
                icon: Icons.arrow_downward_sharp,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildEmptyState(AppThemeTokens theme) {
    final suggestions = [
      context.t.aiAskSuggestionAmiya,
      context.t.aiAskSuggestionVerify,
      context.t.aiAskSuggestionInvestigate,
    ];
    return ListView(
      padding: EdgeInsets.fromLTRB(
        16,
        MediaQuery.paddingOf(context).top + topBarInset + 24,
        16,
        24 + _composerHeight,
      ),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'ASK',
                  style: sairaStyle(
                    size: 56,
                    weight: 800,
                    width: 125,
                    color: theme.textPrimary,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  context.t.aiAskEmpty,
                  style: theme.text(17, height: 1.6),
                ),
                const SizedBox(height: 8),
                Text(
                  context.t.aiAskSource,
                  style:
                      theme.text(14, color: theme.textSecondary, height: 1.55),
                ),
                // 0.14: search runs on meaning only with an embedding service.
                if (ref.watch(embeddingClientProvider) == null) ...[
                  const SizedBox(height: 16),
                  NoticeBox(
                    context.t.aiNoVectorWarning,
                    key: const ValueKey('ask-no-vector-warning'),
                  ),
                ],
                SectionTitle(
                  title: context.t.aiAskTry,
                  code: 'try',
                  size: 17,
                ),
                for (final (i, s) in suggestions.indexed) ...[
                  Divider(height: 1, color: theme.divider),
                  Semantics(
                    button: true,
                    child: PressRow(
                      onTap: () {
                        _inputController.value = TextEditingValue(
                          text: s,
                          selection: TextSelection.collapsed(offset: s.length),
                        );
                      },
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 52),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(8, 10, 4, 10),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 36,
                                child: Text(
                                  (i + 1).toString().padLeft(2, '0'),
                                  style: theme.field(
                                    color: theme.textMuted,
                                    size: 14,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  s,
                                  style:
                                      theme.text(15.5, weight: FontWeight.w500),
                                ),
                              ),
                              Icon(
                                Icons.north_west_sharp,
                                size: 18,
                                color: theme.textMuted,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
                Divider(height: 1, color: theme.divider),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _handleAskSend() {
    final text = _inputController.text.trim();
    if (text.isEmpty) return;

    _inputController.clear();
    ref.read(askChatProvider.notifier).sendMessage(text);
  }

  Future<void> _confirmClearHistory(AskChatNotifier notifier) async {
    final ok = await confirmAction(
      context,
      title: context.t.aiClearHistory,
      message: context.t.aiClearHistoryConfirm,
      confirm: context.t.aiClearConfirmBtn,
      cancel: context.t.materialsCancel,
      danger: true,
    );
    if (ok) notifier.clearChat();
  }
}

/// Reports its child's height after each layout (the question box grows
/// with its text).
class _SizeReporter extends SingleChildRenderObjectWidget {
  const _SizeReporter({required this.onHeight, required super.child});

  final ValueChanged<double> onHeight;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderSizeReporter(onHeight);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderSizeReporter renderObject,
  ) =>
      renderObject.onHeight = onHeight;
}

class _RenderSizeReporter extends RenderProxyBox {
  _RenderSizeReporter(this.onHeight);

  ValueChanged<double> onHeight;
  double? _last;

  @override
  void performLayout() {
    super.performLayout();
    final height = size.height;
    if (height == _last) return;
    _last = height;
    WidgetsBinding.instance.addPostFrameCallback((_) => onHeight(height));
  }
}
