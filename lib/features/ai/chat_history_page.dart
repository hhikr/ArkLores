import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/agent/agent_provider.dart';
import '../../core/agent/chat_session_store.dart';
import '../../shared/l10n/l10n.dart';
import '../../shared/providers/theme_provider.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/ef_widgets.dart';
import '../../shared/widgets/page_bar.dart';
import '../../shared/widgets/page_frame.dart';
import '../library/library_widgets.dart';

/// The saved conversations (the `chat_sessions/` JSON files), last written
/// first, a page at a time. It works as a chat app's list of conversations:
/// tapping one makes it the current conversation (the one before it stays in
/// its own file), the current one is marked, and each row can be deleted
/// (after a question).
class ChatHistoryPage extends ConsumerStatefulWidget {
  const ChatHistoryPage({super.key});

  @override
  ConsumerState<ChatHistoryPage> createState() => _ChatHistoryPageState();
}

class _ChatHistoryPageState extends ConsumerState<ChatHistoryPage> {
  /// 0-based page of the list; only the page shown is read from the files.
  int _page = 0;

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider);
    final count = ref.watch(chatHistoryCountProvider);
    final total = count.valueOrNull ?? 0;
    final pages = pageCountOf(total, ChatSessionStore.pageSize);
    final page = _page.clamp(0, pages - 1);
    final current = ref.read(askChatProvider.notifier).currentSessionId;

    return PageScaffold(
      title: context.t.aiHistoryTitle,
      scrollUnder: true,
      body: count.when(
        loading: () => const LoadingView(),
        error: (_, __) => _empty(theme),
        data: (_) {
          if (total == 0) return _empty(theme);
          final sessions = ref.watch(chatHistoryPageProvider(page));
          return sessions.when(
            loading: () => const LoadingView(),
            error: (_, __) => _empty(theme),
            data: (shown) {
              final divider = rowDivider(theme);
              final pager = pages > 1
                  ? PageBar(
                      theme: theme,
                      keyPrefix: 'chat-history',
                      page: page,
                      pages: pages,
                      onPage: _goTo,
                    )
                  : null;
              return ListView(
                key: ValueKey('chat-history-page-$page'),
                padding: pagePadding(
                  context,
                  const EdgeInsets.fromLTRB(16, 8, 16, 24),
                ),
                children: [
                  if (pager != null)
                    KeyedSubtree(
                      key: const ValueKey('chat-history-pager-top'),
                      child: pager,
                    ),
                  SectionTitle(
                    title: context.t.aiHistoryTitle,
                    code: 'conversations',
                    trailing: Text('$total', style: theme.field()),
                  ),
                  for (final s in shown) ...[
                    divider,
                    _tile(theme, s, isCurrent: s.sessionId == current),
                  ],
                  divider,
                  if (pager != null)
                    KeyedSubtree(
                      key: const ValueKey('chat-history-pager-bottom'),
                      child: pager,
                    ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  void _goTo(int page) {
    if (mounted) setState(() => _page = page);
  }

  Widget _empty(AppThemeTokens theme) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: EmptyState(text: context.t.aiHistoryEmpty),
        ),
      );

  /// One conversation. The current one is marked with an accent block at
  /// its left edge and says so in its second line.
  Widget _tile(
    AppThemeTokens theme,
    ChatSessionSummary summary, {
    required bool isCurrent,
  }) {
    final t = context.t;
    final row = LibraryRow(
      key: ValueKey('chat-history-tile-${summary.sessionId}'),
      title: summary.corrupt ? t.aiHistoryCorrupt : summary.title,
      subtitle: [
        if (isCurrent) t.aiHistoryCurrent,
        _formatTime(summary.updatedAt),
        if (!summary.corrupt) t.aiHistoryTurns(summary.turnCount),
      ].join(' / '),
      subtitleLines: 1,
      trailing: SquareIconButton(
        key: ValueKey('chat-history-delete-${summary.sessionId}'),
        tooltip: t.aiHistoryDelete,
        onPressed: () => _confirmDelete(summary.sessionId),
        icon: Icons.delete_outline_sharp,
        color: theme.danger,
      ),
      onTap: summary.corrupt ? null : () => _open(summary.sessionId),
    );
    if (!isCurrent) return row;
    return Semantics(
      selected: true,
      child: DecoratedBox(
        key: const ValueKey('chat-history-current'),
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(color: theme.accentPrimary, width: 6),
          ),
        ),
        child: row,
      ),
    );
  }

  /// Makes the conversation the current one and goes back to it.
  Future<void> _open(String sessionId) async {
    final notifier = ref.read(askChatProvider.notifier);
    if (sessionId == notifier.currentSessionId) {
      Navigator.of(context).pop();
      return;
    }
    final session = await ref.read(chatSessionStoreProvider).load(sessionId);
    if (!mounted) return;
    if (session == null) {
      showToast(context, context.t.aiHistoryCorrupt);
      return;
    }
    notifier.loadSession(session);
    Navigator.of(context).pop();
  }

  Future<void> _confirmDelete(String sessionId) async {
    final confirmed = await confirmAction(
      context,
      title: context.t.aiHistoryDeleteConfirm,
      confirm: context.t.aiHistoryDelete,
      cancel: context.t.aiCancel,
      danger: true,
      confirmKey: const ValueKey('chat-history-delete-confirm'),
    );
    if (!confirmed || !mounted) return;
    // The conversation on screen goes with its file.
    final notifier = ref.read(askChatProvider.notifier);
    if (sessionId == notifier.currentSessionId) notifier.newSession();
    await ref.read(chatSessionStoreProvider).delete(sessionId);
    ref
      ..invalidate(chatHistoryCountProvider)
      ..invalidate(chatHistoryPageProvider);
  }

  String _formatTime(DateTime time) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${time.year}.${two(time.month)}.${two(time.day)} '
        '${two(time.hour)}:${two(time.minute)}';
  }
}
