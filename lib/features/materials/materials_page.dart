import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/providers/theme_provider.dart';

/// Placeholder page for the Materials tab.
///
/// Will host book import list and PDF/TXT file management in v0.3.
class MaterialsPage extends ConsumerWidget {
  const MaterialsPage({super.key});

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
              Icons.menu_book_rounded,
              size: 64,
              color: theme.accentPrimary.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 16),
            Text(
              'Materials',
              style: theme.titleFont.copyWith(fontSize: 24),
            ),
            const SizedBox(height: 8),
            Text(
              'Import & manage your lore books',
              style: theme.bodyFont.copyWith(color: theme.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
