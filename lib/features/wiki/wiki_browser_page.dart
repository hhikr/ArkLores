import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/providers/theme_provider.dart';

/// Placeholder page for the Wiki Browser tab.
///
/// Will host a WebView (PRTS Wiki + Endfield Wiki) in v0.2.
class WikiBrowserPage extends ConsumerWidget {
  const WikiBrowserPage({super.key});

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
              Icons.language_rounded,
              size: 64,
              color: theme.accentPrimary.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 16),
            Text(
              'Wiki Browser',
              style: theme.titleFont.copyWith(fontSize: 24),
            ),
            const SizedBox(height: 8),
            Text(
              'Browse PRTS & Endfield Wikis',
              style: theme.bodyFont.copyWith(color: theme.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
