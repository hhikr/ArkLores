import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/agent/agent_provider.dart';
import '../../core/agent/chat_session_store.dart';
import '../../shared/l10n/l10n.dart';
import '../../shared/providers/theme_provider.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/floating_bar.dart';
import '../../shared/widgets/page_bar.dart';
import '../library/library_widgets.dart';

/// The saved conversations (the `chat_sessions/` JSON files), last written
/// first, a page at a time. It works as a chat app's list of conversations:
/// tapping one makes it the current conversation (the one before it stays in
/// its own file), the current one is marked, and each row can be deleted.
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

    return FloatingScaffold(
      title: context.t.aiHistoryTitle,
      scrollUnder: true,
      body: count.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => _empty(theme),
        data: (_) {
          if (total == 0) return _empty(theme);
          final sessions = ref.watch(chatHistoryPageProvider(page));
          return sessions.when(
            loading: () => const Center(child: CircularProgressIndicator()),
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
                padding: floatingPadding(
                  context,
                  const EdgeInsets.symmetric(vertical: 8),
                ),
                children: [
                  if (pager != null) ...[
                    KeyedSubtree(
                      key: const ValueKey('chat-history-pager-top'),
                      child: pager,
                    ),
                    divider,
                  ],
                  for (final s in shown) ...[
                    _tile(theme, s, isCurrent: s.sessionId == current),
                    divider,
                  ],
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
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.history_sharp,
                size: 56,
                color: theme.textSecondary.withValues(alpha: 0.4),
              ),
              const SizedBox(height: 16),
              Text(
                context.t.aiHistoryEmpty,
                style: theme.bodyFont.copyWith(color: theme.textSecondary),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );

  /// One conversation. The current one has the accent bar at its left edge
  /// and says so in its second line.
  Widget _tile(
    AppThemeTokens theme,
    ChatSessionSummary summary, {
    required bool isCurrent,
  }) {
    final t = context.t;
    final row = LibraryRow(
      key: ValueKey('chat-history-tile-${summary.sessionId}'),
      leading: Icon(
        summary.corrupt
            ? Icons.error_outline_sharp
            : Icons.chat_bubble_outline_sharp,
        color: summary.corrupt ? theme.danger : theme.accentText,
      ),
      title: summary.corrupt ? t.aiHistoryCorrupt : summary.title,
      subtitle: [
        if (isCurrent) t.aiHistoryCurrent,
        _formatTime(summary.updatedAt),
        if (!summary.corrupt) t.aiHistoryTurns(summary.turnCount),
      ].join(' · '),
      subtitleLines: 1,
      trailing: IconButton(
        key: ValueKey('chat-history-delete-${summary.sessionId}'),
        visualDensity: VisualDensity.compact,
        tooltip: t.aiHistoryDelete,
        onPressed: () => _confirmDelete(summary.sessionId),
        icon: Icon(
          Icons.delete_outline_sharp,
          size: 20,
          color: theme.textSecondary,
        ),
      ),
      onTap: summary.corrupt ? null : () => _open(summary.sessionId),
    );
    if (!isCurrent) return row;
    return DecoratedBox(
      key: const ValueKey('chat-history-current'),
      decoration: BoxDecoration(
        color: theme.accentPrimary.withValues(alpha: 0.10),
        border: Border(
          left: BorderSide(color: theme.accentPrimary, width: 4),
        ),
      ),
      child: row,
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.t.aiHistoryCorrupt)),
      );
      return;
    }
    notifier.loadSession(session);
    Navigator.of(context).pop();
  }

  Future<void> _confirmDelete(String sessionId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.t.aiHistoryDelete),
        content: Text(context.t.aiHistoryDeleteConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(context.t.aiCancel),
          ),
          TextButton(
            key: const ValueKey('chat-history-delete-confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(
              context.t.aiHistoryDelete,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
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
    return '${time.year}-${two(time.month)}-${two(time.day)} '
        '${two(time.hour)}:${two(time.minute)}';
  }
}
