import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/app_version.dart';
import '../../shared/l10n/l10n.dart';
import '../../shared/providers/theme_provider.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/ef_widgets.dart';
import '../../shared/widgets/page_frame.dart';
import '../../shared/widgets/smooth_page_route.dart';
import 'profile_settings_page.dart';
import 'settings_sections.dart';

/// The settings tab: the categories, one numbered row each (the decorative
/// label over the name in bold); each opens its page (settings_sections.dart)
/// with the settings themselves.
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);

    void push(Widget page) => Navigator.of(context)
        .push(smoothPageRoute<void>(builder: (_) => page));

    final categories = <_Category>[
      (
        key: 'appearance',
        code: 'appearance',
        title: context.t.settingsAppearance,
        open: () => push(const AppearanceSettingsPage()),
      ),
      (
        key: 'profile',
        code: context.t.settingsProfileSectionCode,
        title: context.t.settingsProfile,
        open: () => push(const ProfileSettingsPage()),
      ),
      (
        key: 'ai',
        code: context.t.settingsAiSectionCode,
        title: context.t.settingsAiServices,
        open: () => push(const AiSettingsPage()),
      ),
      (
        key: 'knowledge',
        code: context.t.settingsKnowledgeSectionCode,
        title: context.t.settingsKnowledgeCategory,
        open: () => push(const KnowledgeSettingsPage()),
      ),
      (
        key: 'help',
        code: context.t.settingsHelpSectionCode,
        title: context.t.settingsHelpGuide,
        open: () => push(const HelpSettingsPage()),
      ),
    ];

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          ListView(
            key: const ValueKey('settings-list'),
            padding: pagePadding(
              context,
              const EdgeInsets.fromLTRB(16, 12, 16, 40),
            ),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final (i, c) in categories.indexed)
                        _CategoryRow(index: i + 1, category: c),
                      Divider(height: 1, color: theme.divider),
                      const SizedBox(height: 24),
                      Text(
                        context.t.settingsVersionLabel(appVersion),
                        style: theme.field(),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          MainTopBar(
            leading: TopBarTitle(
              title: context.t.settingsTitle,
              code: 'settings',
            ),
          ),
        ],
      ),
    );
  }
}

typedef _Category = ({
  String key,
  String code,
  String title,
  VoidCallback open,
});

/// A category of settings: its number, the decorative label over its name in
/// bold, `›`. Opens its page.
class _CategoryRow extends ConsumerWidget {
  const _CategoryRow({required this.index, required this.category});

  final int index;
  final _Category category;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    return Semantics(
      button: true,
      label: category.title,
      excludeSemantics: true,
      child: PressRow(
        key: ValueKey('settings-category-${category.key}'),
        onTap: category.open,
        child: Container(
          constraints: const BoxConstraints(minHeight: 64),
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: theme.divider)),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 36,
                child: Text(
                  index.toString().padLeft(2, '0'),
                  style: theme.field(size: 14, color: theme.textMuted),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Eyebrow(category.code, color: theme.textMuted),
                    const SizedBox(height: 2),
                    Text(category.title, style: theme.heading(17)),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_sharp,
                color: theme.textSecondary,
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
