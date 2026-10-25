import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/agent/agent_provider.dart';
import '../../../shared/l10n/l10n.dart';
import '../../../shared/providers/theme_provider.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../shared/theme/motion.dart';
import '../../../shared/widgets/ef_widgets.dart';
import '../../../shared/widgets/smooth_page_route.dart';
import '../chat_history_page.dart';

/// How many conversations the panel lists under "recent" before "all".
const conversationsPanelRecent = 8;

/// The top bar's button for the conversations panel; while conversations
/// other than the one shown are answering, their count on an accent block
/// at its corner.
class ConversationsButton extends ConsumerWidget {
  const ConversationsButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    final sessions = ref.watch(askSessionsProvider);
    var elsewhere = 0;
    for (final key in sessions.open) {
      if (key == sessions.shown) continue;
      if (ref.watch(askChatProvider(key).select(_answering))) elsewhere++;
    }
    final label = elsewhere == 0
        ? context.t.aiConversations
        : '${context.t.aiConversations}，'
            '${context.t.aiConversationsAnsweringCount(elsewhere)}';
    return Stack(
      clipBehavior: Clip.none,
      children: [
        SquareIconButton(
          key: const ValueKey('ask-chat-history'),
          icon: Icons.menu_sharp,
          tooltip: label,
          onPressed: () => showConversationsPanel(context),
        ),
        if (elsewhere > 0)
          Positioned(
            right: 4,
            top: 6,
            child: IgnorePointer(
              child: Container(
                key: const ValueKey('ask-answering-elsewhere'),
                constraints: const BoxConstraints(minWidth: 16),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                color: theme.accentPrimary,
                child: Text(
                  '$elsewhere',
                  textAlign: TextAlign.center,
                  style: theme.field(
                    size: 12,
                    weight: 700,
                    color: theme.onAccent,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

bool _answering(List<ChatMessage> messages) =>
    messages.any((m) => m.isStreaming);

/// Opens the conversations panel from the left edge: a new conversation,
/// those answering now, the recent ones, and the way to all of them.
Future<void> showConversationsPanel(BuildContext context) {
  final still = Motion.reduced(context);
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    transitionDuration: still ? Duration.zero : Motion.sheetIn,
    pageBuilder: (context, _, __) => const Align(
      alignment: Alignment.centerLeft,
      child: _ConversationsPanel(),
    ),
    transitionBuilder: (context, animation, _, child) => SlideTransition(
      position: Tween(begin: const Offset(-1, 0), end: Offset.zero).animate(
        CurvedAnimation(
          parent: animation,
          curve: Motion.snap,
          reverseCurve: Motion.mech.flipped,
        ),
      ),
      child: child,
    ),
  );
}

class _ConversationsPanel extends ConsumerStatefulWidget {
  const _ConversationsPanel();

  @override
  ConsumerState<_ConversationsPanel> createState() =>
      _ConversationsPanelState();
}

class _ConversationsPanelState extends ConsumerState<_ConversationsPanel> {
  @override
  void initState() {
    super.initState();
    // What was saved since the list was last read (a conversation answered
    // in the background).
    Future.microtask(() {
      if (!mounted) return;
      ref
        ..invalidate(chatHistoryCountProvider)
        ..invalidate(chatHistoryPageProvider);
    });
  }

  void _close() => Navigator.of(context).pop();

  /// Shows the saved conversation [sessionId] (opened from its file).
  Future<void> _openSaved(String sessionId) async {
    final ok =
        await ref.read(askSessionsProvider.notifier).openSaved(sessionId);
    if (!mounted) return;
    if (!ok) showToast(context, context.t.aiHistoryCorrupt);
    _close();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider);
    final sessions = ref.watch(askSessionsProvider);
    final control = ref.read(askSessionsProvider.notifier);
    final width = MediaQuery.sizeOf(context).width;

    // The open conversations: answering, or idle with something in them.
    final answering = <String>[];
    final idle = <String>[];
    for (final key in sessions.open) {
      final messages = ref.watch(askChatProvider(key));
      if (messages.isEmpty) continue;
      (_answering(messages) ? answering : idle).add(key);
    }
    final openIds = {
      for (final key in sessions.open)
        if (control.chat(key).currentSessionId case final id?) id,
    };
    final saved = ref.watch(chatHistoryPageProvider(0)).valueOrNull ?? const [];
    final total = ref.watch(chatHistoryCountProvider).valueOrNull ?? 0;
    final recent = <Widget>[
      for (final key in idle)
        _row(
          theme,
          key: ValueKey('ask-conversation-$key'),
          title: control.chat(key).title ?? context.t.aiNewConversation,
          note: key == sessions.shown ? context.t.aiHistoryCurrent : null,
          current: key == sessions.shown,
          onTap: () {
            control.show(key);
            _close();
          },
        ),
      for (final s in saved)
        if (!openIds.contains(s.sessionId) && !s.corrupt)
          _row(
            theme,
            key: ValueKey('ask-conversation-saved-${s.sessionId}'),
            title: s.title,
            note: _time(s.updatedAt),
            onTap: () => _openSaved(s.sessionId),
          ),
    ].take(conversationsPanelRecent).toList();

    return Material(
      key: const ValueKey('ask-conversations-panel'),
      color: theme.bgPrimary,
      child: SizedBox(
        width: width < 400 ? width * 0.86 : 340,
        height: double.infinity,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(right: BorderSide(color: theme.divider)),
          ),
          child: SafeArea(
            right: false,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                const Eyebrow('conversations'),
                const SizedBox(height: 4),
                Text(context.t.aiConversations, style: theme.heading(24)),
                const SizedBox(height: 16),
                AppButton(
                  context.t.aiNewConversation,
                  key: const ValueKey('ask-conversations-new'),
                  kind: ButtonKind.go,
                  icon: Icons.add_comment_outlined,
                  onPressed: () {
                    control.startNew();
                    _close();
                  },
                ),
                if (answering.isNotEmpty) ...[
                  SectionTitle(
                    title: context.t.aiConversationsAnswering,
                    code: 'answering',
                    size: 17,
                    trailing:
                        Text('${answering.length}', style: theme.field()),
                  ),
                  for (final key in answering)
                    _AnsweringRow(
                      conversation: key,
                      current: key == sessions.shown,
                      onTap: () {
                        control.show(key);
                        _close();
                      },
                    ),
                  Divider(height: 1, color: theme.divider),
                ],
                SectionTitle(
                  title: context.t.aiConversationsRecent,
                  code: 'recent',
                  size: 17,
                ),
                if (recent.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      context.t.aiConversationsNone,
                      style: theme.text(14, color: theme.textSecondary),
                    ),
                  )
                else ...[
                  ...recent,
                  Divider(height: 1, color: theme.divider),
                ],
                if (total > 0)
                  _row(
                    theme,
                    key: const ValueKey('ask-conversations-all'),
                    title: context.t.aiConversationsAll,
                    note: '$total',
                    muted: true,
                    onTap: () {
                      final navigator = Navigator.of(context);
                      _close();
                      navigator.push(
                        smoothPageRoute<void>(
                          builder: (_) => const ChatHistoryPage(),
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// One conversation: its name and a note (current, when it was saved);
  /// the one shown has the trace line at its left.
  Widget _row(
    AppThemeTokens theme, {
    required Key key,
    required String title,
    String? note,
    bool current = false,
    bool muted = false,
    required VoidCallback onTap,
  }) =>
      Semantics(
        button: true,
        selected: current,
        child: PressRow(
          key: key,
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 52),
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: theme.divider),
                left: BorderSide(
                  color: current ? theme.trace : Colors.transparent,
                  width: 4,
                ),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: muted
                        ? theme.text(15, color: theme.textSecondary)
                        : theme.text(15, weight: FontWeight.w500),
                  ),
                ),
                if (note != null) ...[
                  const SizedBox(width: 8),
                  Text(note, style: theme.field(size: 12)),
                ],
              ],
            ),
          ),
        ),
      );

  static String _time(DateTime time) {
    final now = DateTime.now();
    String two(int value) => value.toString().padLeft(2, '0');
    if (time.year == now.year && time.month == now.month && time.day == now.day) {
      return '${two(time.hour)}:${two(time.minute)}';
    }
    return '${two(time.month)}.${two(time.day)}';
  }
}

/// A conversation answering now: an accent block at its left, its name, and
/// the step it is on, live.
class _AnsweringRow extends ConsumerWidget {
  const _AnsweringRow({
    required this.conversation,
    required this.current,
    required this.onTap,
  });

  final String conversation;
  final bool current;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    final status = ref.watch(
      askChatProvider(conversation).select(
        (m) => m.lastWhere((x) => x.isStreaming, orElse: () => m.last).liveStatus,
      ),
    );
    final title =
        ref.read(askSessionsProvider.notifier).chat(conversation).title ?? '';
    return Semantics(
      button: true,
      selected: current,
      label: '$title，${context.t.aiConversationsAnswering}',
      excludeSemantics: true,
      child: PressRow(
        key: ValueKey('ask-conversation-answering-$conversation'),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 60),
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          decoration: BoxDecoration(
            color: theme.cardSurface,
            border: Border(
              top: BorderSide(color: theme.divider),
              left: BorderSide(color: theme.accentPrimary, width: 6),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.text(15, weight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    color: theme.accentPrimary,
                    child: Text(
                      current
                          ? context.t.aiHistoryCurrent
                          : context.t.aiConversationsAnswering,
                      style: theme.ui(12, weight: 700, color: theme.onAccent),
                    ),
                  ),
                ],
              ),
              if (status.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  status,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.text(13, color: theme.textSecondary),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
