import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/agent/agent_provider.dart';
import '../../core/agent/chat_session_models.dart';
import '../../core/agent/chat_session_store.dart';
import '../../shared/l10n/l10n.dart';
import '../../shared/providers/theme_provider.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/floating_bar.dart';
import '../../shared/widgets/press_feedback.dart';
import '../../shared/widgets/smooth_page_route.dart';
import 'widgets/chat_bubble.dart';

/// Chat History: lists persisted AI conversations (restored from the
/// `chat_sessions/` JSON files) with view / continue / delete actions.
class ChatHistoryPage extends ConsumerStatefulWidget {
  const ChatHistoryPage({super.key});

  @override
  ConsumerState<ChatHistoryPage> createState() => _ChatHistoryPageState();
}

class _ChatHistoryPageState extends ConsumerState<ChatHistoryPage> {
  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider);
    final summaries = ref.watch(chatHistoryListProvider);

    return FloatingScaffold(
      title: context.t.aiHistoryTitle,
      scrollUnder: true,
      body: summaries.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => Center(
          child: Text(
            '${context.t.aiHistoryTitle}: ${context.t.aiSettingsRequired}',
            style: theme.bodyFont.copyWith(color: theme.textSecondary),
          ),
        ),
        data: (sessions) {
          if (sessions.isEmpty) {
            return Center(
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
                      style: theme.bodyFont
                          .copyWith(color: theme.textSecondary),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(chatHistoryListProvider),
            // Under the floating docks: the refresh spinner starts below them.
            edgeOffset: floatingPadding(context, EdgeInsets.zero).top,
            child: ListView.separated(
              padding: floatingPadding(
                context,
                const EdgeInsets.symmetric(vertical: 8),
              ),
              itemCount: sessions.length,
              separatorBuilder: (_, __) => Divider(
                height: 1,
                indent: 16,
                endIndent: 16,
                color: theme.divider,
              ),
              itemBuilder: (context, index) =>
                  _buildSessionTile(theme, sessions[index]),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSessionTile(AppThemeTokens theme, ChatSessionSummary summary) {
    final t = context.t;
    return PressFeedback(
      enabled: !summary.corrupt,
      pressedScale: 0.985,
      child: ListTile(
      leading: Icon(
        summary.corrupt ? Icons.error_outline_sharp : Icons.chat_bubble_outline,
        color: summary.corrupt ? theme.danger : theme.accentPrimary,
      ),
      title: Text(
        summary.corrupt ? t.aiHistoryCorrupt : summary.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.titleFont.copyWith(fontSize: 15),
      ),
      subtitle: Text(
        summary.corrupt
            ? _formatTime(summary.updatedAt)
            : '${_formatTime(summary.updatedAt)} · '
                '${t.aiHistoryTurns(summary.turnCount)}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.bodyFont.copyWith(
          fontSize: 12,
          color: theme.textSecondary,
        ),
      ),
      onTap: summary.corrupt
          ? null
          : withHaptic(() => _openDetail(context, summary.sessionId)),
      trailing: PopupMenuButton<String>(
        icon: Icon(Icons.more_vert_sharp, color: theme.textSecondary),
        onSelected: (action) {
          switch (action) {
            case 'continue':
              unawaited(_continueSession(context, summary.sessionId));
            case 'view':
              _openDetail(context, summary.sessionId);
            case 'delete':
              unawaited(_confirmDelete(context, summary.sessionId));
          }
        },
        itemBuilder: (_) => [
          if (!summary.corrupt)
            PopupMenuItem(
              value: 'continue',
              child: Text(t.aiHistoryContinue),
            ),
          if (!summary.corrupt)
            PopupMenuItem(value: 'view', child: Text(t.aiHistoryView)),
          PopupMenuItem(value: 'delete', child: Text(t.aiHistoryDelete)),
        ],
      ),
      ),
    );
  }

  Future<void> _continueSession(BuildContext context, String sessionId) async {
    final store = ref.read(chatSessionStoreProvider);
    final session = await store.load(sessionId);
    if (!context.mounted) return;
    if (session == null) {
      _showLoadFailed();
      return;
    }
    ref.read(askChatProvider.notifier).loadSession(session);
    if (context.mounted) {
      Navigator.of(context).pop();
    }
  }

  void _openDetail(BuildContext context, String sessionId) {
    Navigator.of(context).push(
      smoothPageRoute<void>(
        builder: (_) => ChatSessionDetailPage(sessionId: sessionId),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, String sessionId) async {
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
    await ref.read(chatSessionStoreProvider).delete(sessionId);
    ref.invalidate(chatHistoryListProvider);
  }

  void _showLoadFailed() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.t.aiHistoryCorrupt)),
    );
  }

  String _formatTime(DateTime time) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${time.year}-${two(time.month)}-${two(time.day)} '
        '${two(time.hour)}:${two(time.minute)}';
  }
}

/// Read-only renderer of one persisted conversation, reusing [ChatBubble]
/// on the messages rebuilt from the session file.
class ChatSessionDetailPage extends ConsumerStatefulWidget {
  const ChatSessionDetailPage({super.key, required this.sessionId});
  final String sessionId;

  @override
  ConsumerState<ChatSessionDetailPage> createState() =>
      _ChatSessionDetailPageState();
}

class _ChatSessionDetailPageState extends ConsumerState<ChatSessionDetailPage> {
  late Future<ChatSessionFile?> _future;

  @override
  void initState() {
    super.initState();
    _future = ref.read(chatSessionStoreProvider).load(widget.sessionId);
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider);
    return FloatingScaffold(
      title: context.t.aiHistoryView,
      scrollUnder: true,
      body: FutureBuilder<ChatSessionFile?>(
        future: _future,
        builder: (context, snapshot) {
          final session = snapshot.data;
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (session == null) {
            return Center(
              child: Text(
                context.t.aiHistoryCorrupt,
                style: theme.bodyFont.copyWith(color: theme.textSecondary),
              ),
            );
          }
          final messages = chatSessionToMessages(session);
          if (messages.isEmpty) {
            return Center(
              child: Text(
                context.t.aiHistoryEmpty,
                style: theme.bodyFont.copyWith(color: theme.textSecondary),
              ),
            );
          }
          return ListView.builder(
            padding: floatingPadding(
              context,
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
            itemCount: messages.length,
            itemBuilder: (context, index) => ChatBubble(message: messages[index]),
          );
        },
      ),
    );
  }
}
