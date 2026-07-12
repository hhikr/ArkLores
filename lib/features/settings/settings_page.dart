import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/providers/theme_provider.dart';
import '../../shared/widgets/theme_aware_card.dart';

/// Settings tab — hosts API Key configuration, theme switcher, and
/// knowledge base management (fully functional in v0.3+).
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    final notifier = ref.read(themeProvider.notifier);

    return Scaffold(
      backgroundColor: theme.bgPrimary,
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        children: [
          // ── Header ───────────────────────────────────────────
          const SizedBox(height: 32),
          Center(
            child: Icon(
              Icons.settings_rounded,
              size: 64,
              color: theme.accentPrimary.withValues(alpha: 0.4),
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: Text(
              'Settings',
              style: theme.titleFont.copyWith(fontSize: 24),
            ),
          ),
          const SizedBox(height: 32),

          // ── Theme Switcher ────────────────────────────────────
          ThemeAwareCard(
            child: Row(
              children: [
                Icon(
                  Icons.palette_rounded,
                  color: theme.accentPrimary,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Theme',
                        style: theme.titleFont.copyWith(fontSize: 16),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        theme.themeName == 'ArkTheme'
                            ? 'Tactical Archive'
                            : 'Holographic Projection',
                        style: theme.bodyFont.copyWith(
                          color: theme.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: notifier.currentTheme == AppTheme.ark,
                  onChanged: (_) => notifier.toggle(),
                  activeColor: theme.accentPrimary,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
