import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/l10n/l10n.dart';
import '../../shared/providers/theme_provider.dart';
import '../../shared/widgets/theme_aware_card.dart';

/// Settings tab — hosts theme switcher, API settings, and
/// knowledge base management.
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
              context.t.settingsTitle,
              style: theme.titleFont.copyWith(fontSize: 24),
            ),
          ),
          const SizedBox(height: 32),

          // ── Theme Switcher ────────────────────────────────────
          ThemeAwareCard(
            child: Row(
              children: [
                Icon(Icons.palette_rounded, color: theme.accentPrimary),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.t.settingsTheme,
                        style: theme.titleFont.copyWith(fontSize: 16),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        notifier.currentTheme == AppTheme.ark
                            ? context.t.settingsThemeArk
                            : context.t.settingsThemeEndfield,
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
          const SizedBox(height: 16),

          // ── API Settings ─────────────────────────────────────
          Text(
            context.t.settingsAiServices,
            style: theme.titleFont.copyWith(fontSize: 18),
          ),
          const SizedBox(height: 12),
          ThemeAwareCard(
            onTap: () {
              Navigator.pushNamed(context, '/api-settings');
            },
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: theme.accentPrimary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.api_rounded,
                    color: theme.accentPrimary,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.t.settingsApiSettings,
                        style: theme.titleFont.copyWith(fontSize: 16),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        context.t.settingsApiSettingsDesc,
                        style: theme.bodyFont.copyWith(
                          color: theme.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: theme.textSecondary,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // ── Knowledge Base ──────────────────────────────────
          Text(
            context.t.settingsKnowledgeBase,
            style: theme.titleFont.copyWith(fontSize: 18),
          ),
          const SizedBox(height: 12),
          ThemeAwareCard(
            onTap: () {
              Navigator.pushNamed(context, '/knowledge-base');
            },
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: theme.accentPrimary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.storage_rounded,
                    color: theme.accentPrimary,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.t.settingsKnowledgeBase,
                        style: theme.titleFont.copyWith(fontSize: 16),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        context.t.settingsKnowledgeBaseDesc,
                        style: theme.bodyFont.copyWith(
                          color: theme.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: theme.textSecondary,
                ),
              ],
            ),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}
