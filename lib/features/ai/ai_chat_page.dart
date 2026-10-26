import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/agent/agent_provider.dart';
import '../../core/llm/llm_provider.dart' show embeddingClientProvider;
import '../../shared/l10n/l10n.dart';
import '../../shared/providers/bars_provider.dart';
import '../../shared/providers/settings_provider.dart';
import '../../shared/providers/theme_provider.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/theme/motion.dart';
import '../../shared/widgets/ef_widgets.dart';
import '../../shared/widgets/page_frame.dart';
import '../settings/background_access.dart';
import 'widgets/answer_options_menu.dart';
import 'widgets/ask_composer.dart';
import 'widgets/ask_context_meter.dart';
import 'widgets/chat_bubble.dart';
import 'widgets/conversations_panel.dart';

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
  /// it), for the list's bottom padding. Notifiers, not page state: only the
  /// padding and the ↓ button follow them, never the bubbles.
  final ValueNotifier<double> _composerHeight = ValueNotifier(0);

  /// What the question box grew by and the list has not yet moved for.
  final _Shift _composerShift = _Shift();

  /// R17d: the list never follows a streaming answer: the thinking, the
  /// steps and the answer grow below and the reader scrolls at their own
  /// pace. Only a new question scrolls (once) to the end. The ↓ button
  /// shows whenever the end is out of view.
  final ValueNotifier<bool> _showJumpToEnd = ValueNotifier(false);

  @override
  void dispose() {
    _chatFocus.dispose();
    _inputController.dispose();
    _scrollController.dispose();
    _composerHeight.dispose();
    _showJumpToEnd.dispose();
    super.dispose();
  }

  /// Called on scrolling and on content size changes.
  bool _onScrollMetrics(ScrollMetrics metrics) {
    _showJumpToEnd.value = metrics.maxScrollExtent - metrics.pixels > 48;
    return false;
  }

  void _composerResized(double height) {
    final delta = height - _composerHeight.value;
    if (delta.abs() <= 0.5) return;
    if (_scrollController.hasClients) {
      _composerShift.value += delta;
      // Spent by the list's next layout; dropped if that layout did not
      // change the list's extent (a short conversation).
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _composerShift.value = 0);
    }
    _composerHeight.value = height;
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
  /// opened as a page of its own (from a wiki page), or the button of the
  /// conversations panel.
  Widget _title() {
    final canPop = ModalRoute.of(context)?.canPop ?? false;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (canPop)
          SquareIconButton(
            icon: Icons.arrow_back_sharp,
            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
            filled: true,
            onPressed: () => Navigator.of(context).maybePop(),
          )
        else
          const ConversationsButton(),
        Flexible(child: TopBarTitle(title: context.t.aiTabAsk, code: 'ask')),
      ],
    );
  }

  /// The conversation actions in the top bar: a new conversation (the one
  /// shown goes on answering in the background), and a menu with retry /
  /// clear.
  Widget _buildActions(AppThemeTokens theme) {
    final key = ref.watch(shownAskProvider);
    final (count, isSending) = ref.watch(askChatProvider(key).select(_shape));
    final chatNotifier = ref.read(askChatProvider(key).notifier);
    return Row(
      key: const ValueKey('ask-floating-actions'),
      mainAxisSize: MainAxisSize.min,
      children: [
        SquareIconButton(
          key: const ValueKey('ask-new-conversation'),
          onPressed: count == 0
              ? null
              : ref.read(askSessionsProvider.notifier).startNew,
          tooltip: context.t.aiNewConversation,
          icon: Icons.add_comment_outlined,
        ),
        if (count > 0)
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
                    Icon(
                      Icons.delete_sweep_sharp,
                      size: 20,
                      color: theme.danger,
                    ),
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
    final key = ref.watch(shownAskProvider);
    final (count, isSending) = ref.watch(askChatProvider(key).select(_shape));
    final chatNotifier = ref.read(askChatProvider(key).notifier);

    ref.listen(askChatProvider(key), (prev, next) {
      // A new question (not a streaming update): bring it into view once,
      // the bars back.
      if ((prev?.length ?? 0) < next.length) {
        _bars.show(ref);
        _scrollToBottom(afterFrame: true);
      }
    });
    // Another conversation shown: its end in view.
    ref.listen(shownAskProvider, (_, __) {
      _bars.show(ref);
      _scrollToBottom(afterFrame: true);
    });

    // Built out here, not in the LayoutBuilder below: the keyboard changes
    // the page's height on every frame it moves, and a list built in there
    // would rebuild every bubble in view (their markdown too) each frame.
    final conversation = Positioned.fill(
      child: Focus(
        focusNode: _chatFocus,
        child: Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (_) {
            if (!_chatFocus.hasFocus) _chatFocus.requestFocus();
          },
          child: count == 0
              ? _buildEmptyState(theme)
              : _buildChatList(theme, count),
        ),
      ),
    );
    final topBar = MainTopBar(
      leading: _title(),
      trailing: _buildActions(theme),
      hides: true,
    );

    // The list scrolls under the top bar and the question box; its padding
    // follows the box's height. The box may grow to half or all of the page
    // (its height budget).
    return LayoutBuilder(
      builder: (context, constraints) => Stack(
        children: [
          conversation,
          topBar,
          Positioned(
            left: 0,
            right: 0,
            top: MediaQuery.paddingOf(context).top + topBarInset,
            bottom: 0,
            // Down onto the tab bar's room while the bars are away.
            child: BarsAway(
              distance: tabBarRoom(context),
              child: Align(
                alignment: Alignment.bottomCenter,
                child: _SizeReporter(
                  onHeight: _composerResized,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight: (constraints.maxHeight -
                                      MediaQuery.paddingOf(context).top -
                                      topBarInset)
                                  .clamp(0.0, double.infinity) *
                              0.55,
                        ),
                        child: const SingleChildScrollView(
                          child: AskContextMeter(),
                        ),
                      ),
                      Flexible(
                        child: LayoutBuilder(
                          builder: (context, room) => AskComposer(
                            controller: _inputController,
                            theme: theme,
                            isSending: isSending,
                            onSend: isSending
                                ? chatNotifier.cancel
                                : _handleAskSend,
                            hintText: context.t.aiAskInputPlaceholder,
                            maxHeight: room.maxHeight,
                            leading: (card) =>
                                AnswerOptionsMenu(theme: theme, above: card),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Hides the bars as the conversation is dragged on, shows them back.
  final BarsFollower _bars = BarsFollower();

  /// The messages, with the ↓ button while the end is out of view.
  Widget _buildChatList(AppThemeTokens theme, int count) {
    final top = MediaQuery.paddingOf(context).top + topBarInset;
    return Stack(
      children: [
        NotificationListener<ScrollMetricsNotification>(
          onNotification: (n) => n.depth == 0 && _onScrollMetrics(n.metrics),
          child: NotificationListener<ScrollUpdateNotification>(
            onNotification: (n) {
              if (n.depth != 0) return false;
              // Only the reader's own drags move the bars.
              if (n.dragDetails != null) {
                _bars.moved(
                  ref,
                  n.scrollDelta ?? 0,
                  atTop: n.metrics.pixels <= n.metrics.minScrollExtent,
                );
              }
              return _onScrollMetrics(n.metrics);
            },
            // A tap that ends on the text or the space between messages (a
            // button, a row or a link under the finger takes the tap for
            // itself, a drag goes to the list): the bars back, or away.
            child: GestureDetector(
              key: const ValueKey('ask-blank-tap'),
              onTap: () {
                final p = _scrollController.hasClients
                    ? _scrollController.position
                    : null;
                _bars.tapped(
                  ref,
                  canHide: p != null && p.pixels > p.minScrollExtent,
                );
              },
              child: CustomScrollView(
                key: const ValueKey('ask-chat-list'),
                controller: _scrollController,
                physics: _BottomAnchoredPhysics(_composerShift),
                slivers: [
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(16, top + 12, 16, 0),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) => _MessageAt(index),
                        childCount: count,
                      ),
                    ),
                  ),
                  // Only this space follows the question box's height.
                  ValueListenableBuilder<double>(
                    valueListenable: _composerHeight,
                    builder: (context, height, _) => SliverToBoxAdapter(
                      child: SizedBox(height: 12 + height),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        ValueListenableBuilder<bool>(
          valueListenable: _showJumpToEnd,
          builder: (context, show, _) => !show
              ? const SizedBox.shrink()
              : ValueListenableBuilder<double>(
                  valueListenable: _composerHeight,
                  builder: (context, height, _) => Positioned(
                    right: 12,
                    bottom: 8 + height,
                    child: BarsAway(
                      distance: tabBarRoom(context),
                      // A chip-grey block like the composer's own buttons;
                      // it covers what scrolls under it.
                      child: SquareIconButton(
                        key: const ValueKey('scroll-to-bottom'),
                        tooltip: context.t.aiScrollToBottom,
                        onPressed: _scrollToBottom,
                        icon: Icons.arrow_downward_sharp,
                        filled: true,
                      ),
                    ),
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
    return ValueListenableBuilder<double>(
      valueListenable: _composerHeight,
      builder: (context, height, child) => ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          MediaQuery.paddingOf(context).top + topBarInset + 24,
          16,
          24 + height,
        ),
        children: [child!],
      ),
      child: _emptyStateBody(theme, suggestions),
    );
  }

  Widget _emptyStateBody(AppThemeTokens theme, List<String> suggestions) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // One line on a narrow phone: shrinks rather than wraps.
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                'JUST ASK.',
                style: sairaStyle(
                  size: 56,
                  weight: 800,
                  width: 125,
                  color: theme.textPrimary,
                  height: 1,
                ),
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
              style: theme.text(14, color: theme.textSecondary, height: 1.55),
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
                              style: theme.text(15.5, weight: FontWeight.w500),
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
    );
  }

  Future<void> _handleAskSend() async {
    final text = _inputController.text.trim();
    if (text.isEmpty) return;

    _inputController.clear();
    // The first question: why the app asks to run in the background, before
    // the answer that needs it.
    await explainBackgroundOnce(context, ref);
    if (!mounted) return;
    unawaited(
      ref
          .read(askChatProvider(ref.read(shownAskProvider)).notifier)
          .sendMessage(text),
    );
  }

  bool _backgroundChecked = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // A reader who has asked before is told once, when Ask is first shown
    // (hidden tabs have their tickers off).
    if (_backgroundChecked || !TickerMode.valuesOf(context).enabled) return;
    _backgroundChecked = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final saved = await ref
          .read(chatSessionStoreProvider)
          .count()
          .catchError((Object _) => 0);
      if (saved > 0 && mounted) await explainBackgroundOnce(context, ref);
    });
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

/// What the page itself shows of the conversation: how many messages, and
/// whether the last one is still being written. A streaming answer changes
/// its message many times a second; only that message's bubble rebuilds
/// ([_MessageAt]), not the page, the question box or the other bubbles.
(int, bool) _shape(List<ChatMessage> messages) =>
    (messages.length, messages.isNotEmpty && messages.last.isStreaming);

/// The bubble of the message at [index], rebuilt when that message changes
/// (an unchanged message is the same object, see `updateMessage`).
class _MessageAt extends ConsumerWidget {
  const _MessageAt(this.index);

  final int index;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final message = ref.watch(
      askChatProvider(ref.watch(shownAskProvider))
          .select((s) => index < s.length ? s[index] : null),
    );
    if (message == null) return const SizedBox.shrink();
    return ChatBubble(key: ValueKey(message.id), message: message);
  }
}

class _Shift {
  double value = 0;

  /// The view's height the list last moved for. The position's own old
  /// metrics are not enough: one layout may ask several times (the list's
  /// estimated length changes as it lays out more bubbles), and each time
  /// against the same old height.
  double? viewport;
}

/// Keeps the text just above the question box where it is when the room
/// under the list changes: the keyboard coming up or going down (the view
/// gets shorter or taller) and the question box growing or shrinking
/// ([_Shift], one frame after the box). Done in the list's own layout, so
/// the text moves with the keyboard frame by frame; it used to stay put and
/// then spring back when out of range. An answer that grows does not move
/// the list (R17d), and the position is only ever clamped, never sprung.
class _BottomAnchoredPhysics extends ScrollPhysics {
  const _BottomAnchoredPhysics(this.shift, {super.parent});

  final _Shift shift;

  @override
  _BottomAnchoredPhysics applyTo(ScrollPhysics? ancestor) =>
      _BottomAnchoredPhysics(shift, parent: buildParent(ancestor));

  @override
  double adjustPositionForNewDimensions({
    required ScrollMetrics oldPosition,
    required ScrollMetrics newPosition,
    required bool isScrolling,
    required double velocity,
  }) {
    final pixels = super.adjustPositionForNewDimensions(
      oldPosition: oldPosition,
      newPosition: newPosition,
      isScrolling: isScrolling,
      velocity: velocity,
    );
    var by = shift.value;
    shift.value = 0;
    final viewport =
        newPosition.hasViewportDimension ? newPosition.viewportDimension : null;
    final last = shift.viewport ??
        (oldPosition.hasViewportDimension
            ? oldPosition.viewportDimension
            : null);
    shift.viewport = viewport;
    if (isScrolling || !newPosition.hasContentDimensions) return pixels;
    if (last != null && viewport != null) by += last - viewport;
    // Moved from where it was, not from where the parent already clamped
    // it to (the view growing shortens the list's range first).
    return (by == 0 ? pixels : newPosition.pixels + by)
        .clamp(newPosition.minScrollExtent, newPosition.maxScrollExtent);
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
