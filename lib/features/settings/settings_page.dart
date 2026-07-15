import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/l10n/l10n.dart';
import '../../shared/providers/theme_provider.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/industrial_ui.dart';
import '../../shared/widgets/theme_aware_card.dart';
import 'onboarding_page.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    final currentTheme = ref.read(themeProvider.notifier).currentTheme;
    final currentLocale = ref.watch(localeProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                MediaQuery.sizeOf(context).width >= 400 ? 28 : 20,
                12,
                MediaQuery.sizeOf(context).width >= 400 ? 28 : 20,
                40,
              ),
              sliver: SliverToBoxAdapter(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 620),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        IndustrialPageHeader(
                          theme: theme,
                          title: context.t.settingsTitle,
                          code: context.t.settingsSystemCode,
                          icon: Icons.tune_rounded,
                        ),
                        _CompactSettingWidth(
                          child: ThemeAwareCard(
                            padding: EdgeInsets.zero,
                            child: Column(
                              children: [
                                _PreferenceRow(
                                  theme: theme,
                                  icon: Icons.layers_outlined,
                                  title: context.t.settingsTheme,
                                  subtitle: currentTheme == AppTheme.ark
                                      ? context.t.settingsThemeArk
                                      : context.t.settingsThemeEndfield,
                                  control: SegmentedButton<AppTheme>(
                                    showSelectedIcon: false,
                                    segments: [
                                      ButtonSegment(
                                        value: AppTheme.ark,
                                        label: Text(
                                            context.t.settingsThemeArkShort),
                                      ),
                                      ButtonSegment(
                                        value: AppTheme.endfield,
                                        label: Text(
                                          context.t.settingsThemeEndfieldShort,
                                        ),
                                      ),
                                    ],
                                    selected: {currentTheme},
                                    onSelectionChanged: (selection) {
                                      ref
                                          .read(themeProvider.notifier)
                                          .switchTo(selection.first);
                                    },
                                  ),
                                ),
                                Divider(height: 1, color: theme.divider),
                                _PreferenceRow(
                                  theme: theme,
                                  icon: Icons.language_rounded,
                                  title: context.t.settingsLanguage,
                                  subtitle: currentLocale.displayName,
                                  control: SegmentedButton<SupportedLocale>(
                                    showSelectedIcon: false,
                                    segments: [
                                      ButtonSegment(
                                        value: SupportedLocale.en,
                                        label:
                                            Text(context.t.localeEnglishShort),
                                      ),
                                      ButtonSegment(
                                        value: SupportedLocale.zh,
                                        label:
                                            Text(context.t.localeChineseShort),
                                      ),
                                    ],
                                    selected: {currentLocale},
                                    onSelectionChanged: (selection) {
                                      ref
                                          .read(localeProvider.notifier)
                                          .switchTo(selection.first);
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 22),
                        IndustrialSectionHeader(
                          theme: theme,
                          title: context.t.settingsAiServices,
                          code: context.t.settingsAiSectionCode,
                        ),
                        _CompactSettingWidth(
                          child: _SettingsActionTile(
                            theme: theme,
                            icon: Icons.api_rounded,
                            title: context.t.settingsApiSettings,
                            subtitle: context.t.settingsApiSettingsDesc,
                            onTap: () => Navigator.pushNamed(
                              context,
                              '/api-settings',
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        IndustrialSectionHeader(
                          theme: theme,
                          title: context.t.settingsKnowledgeBase,
                          code: context.t.settingsKnowledgeSectionCode,
                        ),
                        _CompactSettingWidth(
                          child: _SettingsActionTile(
                            theme: theme,
                            icon: Icons.dns_outlined,
                            title: context.t.settingsKnowledgeBase,
                            subtitle: context.t.settingsKnowledgeBaseDesc,
                            onTap: () => Navigator.pushNamed(
                              context,
                              '/knowledge-base',
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        IndustrialSectionHeader(
                          theme: theme,
                          title: context.t.settingsHelpGuide,
                          code: context.t.settingsHelpSectionCode,
                        ),
                        _CompactSettingWidth(
                          child: _SettingsActionTile(
                            theme: theme,
                            icon: Icons.menu_book_outlined,
                            title: context.t.settingsShowOnboarding,
                            subtitle: context.t.settingsShowOnboardingDesc,
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (context) => OnboardingPage(
                                  onComplete: () => Navigator.of(context).pop(),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 28),
                        _SystemFooter(
                          theme: theme,
                          label: context.t.settingsVersionLabel,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PreferenceRow extends StatelessWidget {
  const _PreferenceRow({
    required this.theme,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.control,
  });

  final AppThemeTokens theme;
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget control;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final stack = constraints.maxWidth < 285 ||
            MediaQuery.textScalerOf(context).scale(14) > 20;
        final label = Row(
          children: [
            SizedBox(
              width: 44,
              height: 44,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: theme.surfaceElevated,
                  border: Border.all(color: theme.divider),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Icon(
                      icon,
                      color: theme.isEndfield
                          ? theme.textPrimary
                          : theme.accentPrimary,
                      size: 24,
                    ),
                    if (theme.isEndfield)
                      Positioned(
                        left: 0,
                        top: 0,
                        bottom: 0,
                        child: Container(
                          width: 3,
                          color: theme.accentPrimary,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.titleFont.copyWith(fontSize: 16),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.bodyFont.copyWith(
                      color: theme.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );

        return Padding(
          padding: const EdgeInsets.all(14),
          child: stack
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    label,
                    const SizedBox(height: 14),
                    Align(alignment: Alignment.centerRight, child: control),
                  ],
                )
              : Row(
                  children: [
                    Expanded(child: label),
                    const SizedBox(width: 16),
                    control,
                  ],
                ),
        );
      },
    );
  }
}

class _CompactSettingWidth extends StatelessWidget {
  const _CompactSettingWidth({
    required this.child,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      widthFactor: 0.94,
      alignment: Alignment.center,
      child: child,
    );
  }
}

class _SettingsActionTile extends StatelessWidget {
  const _SettingsActionTile({
    required this.theme,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final AppThemeTokens theme;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ThemeAwareCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Row(
        children: [
          SizedBox(
            width: 48,
            height: 48,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: theme.surfaceElevated,
                border: Border.all(color: theme.divider),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Icon(
                    icon,
                    color: theme.isEndfield
                        ? theme.textPrimary
                        : theme.accentSecondary,
                    size: 26,
                  ),
                  if (theme.isEndfield)
                    Positioned(
                      left: 0,
                      top: 0,
                      bottom: 0,
                      child: Container(width: 3, color: theme.accentPrimary),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.titleFont.copyWith(fontSize: 17),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: theme.bodyFont.copyWith(
                    color: theme.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Icon(Icons.chevron_right_rounded, color: theme.textSecondary),
        ],
      ),
    );
  }
}

class _SystemFooter extends StatelessWidget {
  const _SystemFooter({required this.theme, required this.label});

  final AppThemeTokens theme;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(width: 36, height: 2, color: theme.accentPrimary),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.bodyFont.copyWith(
              color: theme.textMuted,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}
