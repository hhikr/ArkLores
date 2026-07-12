import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/providers/theme_provider.dart';
import '../../shared/widgets/theme_aware_card.dart';

/// Placeholder page for the Settings tab.
///
/// Will host API Key configuration, theme switcher, and knowledge base
/// management in v0.3+.
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

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
              Icons.settings_rounded,
              size: 64,
              color: theme.accentPrimary.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 16),
            Text(
              'Settings',
              style: theme.titleFont.copyWith(fontSize: 24),
            ),
            const SizedBox(height: 8),
            Text(
              'API Key · Theme · Knowledge Base',
              style: theme.bodyFont.copyWith(color: theme.textSecondary),
            ),
            const SizedBox(height: 32),
            ThemeAwareCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Coming in v0.3',
                    style: theme.titleFont.copyWith(fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'API key configuration, theme switching, '
                    'and knowledge base management.',
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
