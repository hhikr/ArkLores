import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/agent/agent_provider.dart';
import '../../../core/agent/turn_stats.dart';
import '../../../shared/l10n/l10n.dart';
import '../../../shared/providers/settings_provider.dart';
import '../../../shared/providers/theme_provider.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../shared/widgets/ef_widgets.dart';

/// Watches only the latest context value, leaving streamed text in its row.
class AskContextMeter extends ConsumerStatefulWidget {
  const AskContextMeter({super.key});

  @override
  ConsumerState<AskContextMeter> createState() => _AskContextMeterState();
}

class _AskContextMeterState extends ConsumerState<AskContextMeter> {
  bool _dialogScheduled = false;

  void _maybeWarn(String key) {
    final chat = ref.read(askChatProvider(key).notifier);
    if (!chat.contextWarningPending ||
        _dialogScheduled ||
        !TickerMode.valuesOf(context).enabled) {
      return;
    }
    _dialogScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _dialogScheduled = false;
      if (!mounted ||
          ref.read(shownAskProvider) != key ||
          !TickerMode.valuesOf(context).enabled ||
          !chat.contextWarningPending) {
        return;
      }
      final stats = chat.latestContext;
      if (stats == null) return;
      chat.acknowledgeContextWarning();
      final n =
          '${stats.contextEstimated ? '≈' : ''}${formatTokenCount(stats.contextTokens)}';
      final limit = formatTokenCount(ref.read(contextWarnTokensProvider));
      await showAppDialog<void>(
        context,
        (dialogContext) => Consumer(
          builder: (context, ref, _) {
            final sending = ref.watch(
              askChatProvider(key).select(
                (messages) => messages.any((m) => m.isStreaming),
              ),
            );
            return AppDialog(
              title: context.t.aiContextWarningTitle,
              message: context.t.aiContextWarningBody(n, limit),
              actions: [
                if (sending)
                  AppButton(
                    context.t.aiContextStop,
                    onPressed: () {
                      chat.cancel();
                      Navigator.pop(dialogContext);
                    },
                  ),
                AppButton(
                  context.t.aiContextNewChat,
                  onPressed: () {
                    Navigator.pop(dialogContext);
                    ref.read(askSessionsProvider.notifier).startNew();
                  },
                ),
                AppButton(
                  context.t.aiContextDismiss,
                  kind: ButtonKind.go,
                  onPressed: () => Navigator.pop(dialogContext),
                ),
              ],
            );
          },
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final key = ref.watch(shownAskProvider);
    final value = ref.watch(
      askChatProvider(key).select((messages) {
        final stats = latestContextStats(messages);
        return (stats?.contextTokens ?? 0, stats?.contextEstimated ?? false);
      }),
    );
    final threshold = ref.watch(contextWarnTokensProvider);
    _maybeWarn(key);
    if (value.$1 <= 0) return const SizedBox.shrink();
    final theme = ref.watch(themeProvider);
    final over = value.$1 >= threshold;
    final n = '${value.$2 ? '≈' : ''}${formatTokenCount(value.$1)}';
    final limit = formatTokenCount(threshold);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (over)
            NoticeBox(
              context.t.aiContextNotice(n, limit),
              action: AppButton(
                context.t.aiContextNewChat,
                onPressed: () =>
                    ref.read(askSessionsProvider.notifier).startNew(),
              ),
            ),
          Align(
            alignment: Alignment.centerRight,
            child: Container(
              key: const ValueKey('ask-context-meter'),
              // On the page's ground: the answer scrolls under it.
              color: over ? theme.accentPrimary : theme.bgPrimary,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (over) ...[
                    SizedBox(
                        width: 10,
                        height: 10,
                        child: ColoredBox(color: theme.onAccent),),
                    const SizedBox(width: 4),
                  ],
                  Text(
                    context.t.aiContextMeter(n, limit),
                    style: theme.field(
                        size: 12,
                        color: over ? theme.onAccent : theme.textSecondary,),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
