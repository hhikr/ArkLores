import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/agent/agent_provider.dart';
import '../../../core/agent/roleplay_agent.dart';
import '../../../shared/l10n/l10n.dart';
import '../../../shared/providers/theme_provider.dart';
import '../../../shared/theme/app_theme.dart';
import 'chat_bubble.dart';

class RoleplayTab extends ConsumerStatefulWidget {
  const RoleplayTab({super.key});

  @override
  ConsumerState<RoleplayTab> createState() => _RoleplayTabState();
}

class _RoleplayTabState extends ConsumerState<RoleplayTab> {
  final _characterController = TextEditingController();
  final _sceneController = TextEditingController();
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _characterController.dispose();
    _sceneController.dispose();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider);
    final state = ref.watch(roleplayProvider);
    ref.listen(roleplayProvider, (previous, next) {
      if (previous?.messages.length != next.messages.length) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController.animateTo(
              _scrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut,
            );
          }
        });
      }
    });
    return state.character == null
        ? _buildSetup(theme, state)
        : _buildConversation(theme, state);
  }

  Widget _buildSetup(AppThemeTokens theme, RoleplayState state) {
    final notifier = ref.read(roleplayProvider.notifier);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (state.hasSavedSession) ...[
          OutlinedButton.icon(
            onPressed: notifier.continueSavedSession,
            icon: const Icon(Icons.history_rounded),
            label: Text(context.t.aiRoleplayContinue),
          ),
          const SizedBox(height: 12),
        ],
        Text(context.t.aiRoleplayChoose,
            style: theme.titleFont
                .copyWith(fontSize: 18, color: theme.textPrimary)),
        const SizedBox(height: 6),
        Text(context.t.aiRoleplayChooseDesc,
            style: theme.bodyFont.copyWith(color: theme.textSecondary)),
        const SizedBox(height: 16),
        TextField(
          controller: _characterController,
          enabled: !state.isResolving,
          decoration: InputDecoration(
            labelText: context.t.aiRoleplayCharacter,
            prefixIcon: const Icon(Icons.person_search_rounded),
          ),
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _sceneController,
          enabled: !state.isResolving,
          minLines: 2,
          maxLines: 4,
          decoration: InputDecoration(
            labelText: context.t.aiRoleplayScene,
            helperText: context.t.aiRoleplaySceneContext,
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: state.isResolving
              ? null
              : () => notifier.resolveCharacter(
                    _characterController.text,
                    scene: _sceneController.text,
                  ),
          icon: state.isResolving
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.check_rounded),
          label: Text(state.isResolving
              ? context.t.aiRoleplayResolving
              : context.t.aiRoleplayStart),
        ),
        if (state.resolutionStatus == CharacterResolutionStatus.unavailable)
          _status(theme, context.t.aiRoleplayNoDatabase),
        if (state.resolutionStatus == CharacterResolutionStatus.notFound)
          _status(theme, context.t.aiRoleplayNotFound),
        if (state.candidates.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text(context.t.aiRoleplayDisambiguate,
              style: theme.titleFont.copyWith(color: theme.textPrimary)),
          const SizedBox(height: 8),
          for (final candidate in state.candidates)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.badge_outlined),
              title: Text(candidate.name),
              subtitle: Text('${candidate.entityType} · ${candidate.entityId}'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => notifier.selectCandidate(candidate,
                  scene: _sceneController.text),
            ),
        ],
      ],
    );
  }

  Widget _status(AppThemeTokens theme, String text) => Padding(
        padding: const EdgeInsets.only(top: 16),
        child: Text(text,
            style: theme.bodyFont.copyWith(color: theme.danger),
            textAlign: TextAlign.center),
      );

  Widget _buildConversation(AppThemeTokens theme, RoleplayState state) {
    final notifier = ref.read(roleplayProvider.notifier);
    final character = state.character!;
    return Column(
      children: [
        Container(
          width: double.infinity,
          color: theme.bgSecondary,
          padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
          child: Row(
            children: [
              Icon(Icons.verified_user_outlined,
                  size: 20, color: theme.accentPrimary),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(character.name,
                        style: theme.titleFont
                            .copyWith(color: theme.textPrimary, fontSize: 15)),
                    Text('${character.entityId} · GameData',
                        overflow: TextOverflow.ellipsis,
                        style: theme.bodyFont.copyWith(
                            color: theme.textSecondary, fontSize: 11)),
                  ],
                ),
              ),
              IconButton(
                onPressed: state.isSending ? null : notifier.restart,
                tooltip: context.t.aiRoleplayRestart,
                icon: const Icon(Icons.restart_alt_rounded),
              ),
            ],
          ),
        ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
          color: theme.accentPrimary.withValues(alpha: 0.08),
          child: Text(context.t.aiRoleplayGeneratedNotice,
              style: theme.bodyFont
                  .copyWith(color: theme.textSecondary, fontSize: 11)),
        ),
        Expanded(
          child: state.messages.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(context.t.aiRoleplayEmpty,
                        textAlign: TextAlign.center,
                        style: theme.bodyFont
                            .copyWith(color: theme.textSecondary)),
                  ),
                )
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(16),
                  itemCount: state.messages.length,
                  itemBuilder: (_, index) =>
                      ChatBubble(message: state.messages[index]),
                ),
        ),
        if (state.messages.lastOrNull?.isError == true && !state.isSending)
          TextButton.icon(
            onPressed: notifier.retryLast,
            icon: const Icon(Icons.refresh_rounded),
            label: Text(context.t.aiRetry),
          ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    enabled: !state.isSending,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(notifier),
                    decoration: InputDecoration(
                        hintText: context.t.aiRoleplayInputPlaceholder),
                  ),
                ),
                IconButton(
                  onPressed:
                      state.isSending ? notifier.cancel : () => _send(notifier),
                  tooltip:
                      state.isSending ? context.t.aiCancel : context.t.aiSend,
                  icon: Icon(state.isSending
                      ? Icons.stop_rounded
                      : Icons.send_rounded),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _send(RoleplayNotifier notifier) {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;
    _messageController.clear();
    notifier.sendMessage(text);
  }
}
