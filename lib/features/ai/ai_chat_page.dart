import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/l10n/l10n.dart';
import '../../shared/providers/theme_provider.dart';
import '../../shared/widgets/theme_aware_card.dart';

/// Placeholder page for the AI Chat tab.
///
/// Will host three AI modes (FactCheck / Summary / Roleplay) in v0.4-v0.6.
class AiChatPage extends ConsumerWidget {
  const AiChatPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);

    return Scaffold(
      backgroundColor: theme.bgPrimary,
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.psychology_rounded,
              size: 64,
              color: theme.accentPrimary.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 16),
            Text(
              context.t.aiChatTitle,
              style: theme.titleFont.copyWith(fontSize: 24),
            ),
            const SizedBox(height: 8),
            Text(
              context.t.aiChatSubtitle,
              style: theme.bodyFont.copyWith(color: theme.textSecondary),
            ),
            const SizedBox(height: 32),
            ThemeAwareCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    context.t.aiChatComingSoon,
                    style: theme.titleFont.copyWith(fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    context.t.aiChatComingSoonDesc,
                    style: theme.bodyFont.copyWith(color: theme.textSecondary),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
