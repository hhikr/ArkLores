import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/providers/theme_provider.dart';

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
      body: Center(
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
              'AI Chat',
              style: theme.titleFont.copyWith(fontSize: 24),
            ),
            const SizedBox(height: 8),
            Text(
              'Fact Check · Summary · Roleplay',
              style: theme.bodyFont.copyWith(color: theme.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
