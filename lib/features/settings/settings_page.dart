import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/agent/agent_logger.dart';
import '../../shared/app_version.dart';
import '../../shared/l10n/l10n.dart';
import '../../shared/providers/settings_provider.dart';
import '../../shared/providers/theme_provider.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/ef_widgets.dart';
import '../../shared/widgets/page_frame.dart';
import '../../shared/widgets/smooth_page_route.dart';
import 'app_icon_service.dart';
import 'onboarding_page.dart';
import 'profile_settings_page.dart';
import 'settings_service.dart';
import 'wiki_sources_settings_page.dart';

/// The settings tab: one column of sections, each a heading and rows with a
/// hairline between them. A choice among a few is a segmented control under
/// its name (it gets the full width); a yes/no is a switch on the right; a
/// row that opens a page ends in `›`.
class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  AppLauncherIcon _launcherIcon = AppLauncherIcon.light;
  bool _loadingLocalSettings = true;

  @override
  void initState() {
    super.initState();
    _loadLocalSettings();
  }

  Future<void> _loadLocalSettings() async {
    final service = ref.read(settingsServiceProvider);
    final icon = await service.loadAppLauncherIcon();
    if (!mounted) return;
    setState(() {
      _launcherIcon = icon;
      _loadingLocalSettings = false;
    });
  }

  Future<void> _selectLauncherIcon(AppLauncherIcon icon) async {
    if (icon == _launcherIcon) return;
    final service = ref.read(settingsServiceProvider);
    await service.saveAppLauncherIcon(icon);
    final applied = await AppIconService.setIcon(icon);
    if (!mounted) return;
    setState(() => _launcherIcon = icon);
    if (!applied) showToast(context, context.t.settingsIconUnsupported);
  }

  void _push(Widget page) => Navigator.of(context)
      .push(smoothPageRoute<void>(builder: (_) => page));

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider);
    final themes = ref.read(themeProvider.notifier);
    final currentTheme = themes.currentTheme;
    final currentLocale = ref.watch(localeProvider);
    final logs = ref.watch(sessionLogsEnabledProvider);
    final foldOpen = ref.watch(profileSectionsOpenProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          ListView(
            key: const ValueKey('settings-list'),
            padding: pagePadding(
              context,
              const EdgeInsets.fromLTRB(16, 4, 16, 40),
            ),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SectionTitle(
                        title: context.t.settingsAppearance,
                        code: 'appearance',
                      ),
                      _ChoiceRow<AppTheme>(
                        key: const ValueKey('settings-theme'),
                        title: context.t.settingsTheme,
                        description: switch (currentTheme) {
                          AppTheme.system => context.t.settingsThemeSystem,
                          AppTheme.ark => context.t.settingsThemeArk,
                          AppTheme.endfield => context.t.settingsThemeEndfield,
                        },
                        value: currentTheme,
                        options: [
                          (AppTheme.system, context.t.settingsThemeSystemShort),
                          (AppTheme.endfield, context.t.settingsThemeEndfieldShort),
                          (AppTheme.ark, context.t.settingsThemeArkShort),
                        ],
                        onChanged: (next) {
                          themes.switchTo(next);
                          ref.read(settingsServiceProvider).saveTheme(next);
                        },
                      ),
                      _ChoiceRow<ReadingFont>(
                        key: const ValueKey('settings-reading-font'),
                        title: context.t.settingsReadingFont,
                        description: context.t.settingsReadingFontDesc,
                        value: themes.readingFont,
                        options: [
                          (ReadingFont.sans, context.t.settingsReadingFontSans),
                          (ReadingFont.kai, context.t.settingsReadingFontKai),
                        ],
                        onChanged: (next) {
                          themes.setReadingFont(next);
                          ref.read(settingsServiceProvider).saveReadingFont(next);
                        },
                      ),
                      _ChoiceRow<SupportedLocale>(
                        title: context.t.settingsLanguage,
                        description: currentLocale.displayName,
                        value: currentLocale,
                        options: [
                          (SupportedLocale.zh, context.t.localeChineseShort),
                          (SupportedLocale.en, context.t.localeEnglishShort),
                        ],
                        onChanged: (next) {
                          ref.read(localeProvider.notifier).switchTo(next);
                          ref.read(settingsServiceProvider).saveLocale(next);
                        },
                      ),
                      _ChoiceRow<AppLauncherIcon>(
                        title: context.t.settingsAppIcon,
                        description: _launcherIcon == AppLauncherIcon.light
                            ? context.t.settingsIconLightLabel
                            : context.t.settingsIconDarkLabel,
                        value: _launcherIcon,
                        enabled: !_loadingLocalSettings,
                        options: [
                          (AppLauncherIcon.light, context.t.settingsIconLightShort),
                          (AppLauncherIcon.dark, context.t.settingsIconDarkShort),
                        ],
                        onChanged: _selectLauncherIcon,
                      ),
                      Divider(height: 1, color: theme.divider),
                      SectionTitle(
                        title: context.t.settingsProfile,
                        code: context.t.settingsProfileSectionCode,
                      ),
                      ActionRow(
                        icon: Icons.person_outline_sharp,
                        label: context.t.settingsProfile,
                        description: context.t.settingsProfileDesc,
                        onTap: () => _push(const ProfileSettingsPage()),
                      ),
                      Divider(height: 1, color: theme.divider),
                      SectionTitle(
                        title: context.t.settingsAiServices,
                        code: context.t.settingsAiSectionCode,
                      ),
                      ActionRow(
                        icon: Icons.api_sharp,
                        label: context.t.settingsApiSettings,
                        description: context.t.settingsApiSettingsDesc,
                        onTap: () =>
                            Navigator.pushNamed(context, '/api-settings'),
                      ),
                      ActionRow(
                        key: const ValueKey('settings-session-logs'),
                        icon: Icons.receipt_long_sharp,
                        label: context.t.settingsSessionLogs,
                        description: context.t.settingsSessionLogsDesc,
                        onTap: () => _setLogs(!logs),
                        trailing: SquareSwitch(
                          value: logs,
                          semanticLabel: context.t.settingsSessionLogs,
                          onChanged: _setLogs,
                        ),
                      ),
                      Divider(height: 1, color: theme.divider),
                      SectionTitle(
                        title: context.t.settingsKnowledgeBase,
                        code: context.t.settingsKnowledgeSectionCode,
                      ),
                      ActionRow(
                        icon: Icons.storage_sharp,
                        label: context.t.settingsKnowledgeBase,
                        description: context.t.settingsKnowledgeBaseDesc,
                        onTap: () =>
                            Navigator.pushNamed(context, '/knowledge-base'),
                      ),
                      ActionRow(
                        icon: Icons.dns_outlined,
                        label: context.t.settingsWikiSources,
                        description: context.t.settingsWikiSourcesDesc,
                        onTap: () => _push(const WikiSourcesSettingsPage()),
                      ),
                      ActionRow(
                        key: const ValueKey('settings-profile-sections'),
                        icon: Icons.unfold_more_sharp,
                        label: context.t.settingsProfileSectionsOpen,
                        description: context.t.settingsProfileSectionsOpenDesc,
                        onTap: () => _setFoldOpen(!foldOpen),
                        trailing: SquareSwitch(
                          value: foldOpen,
                          semanticLabel: context.t.settingsProfileSectionsOpen,
                          onChanged: _setFoldOpen,
                        ),
                      ),
                      Divider(height: 1, color: theme.divider),
                      SectionTitle(
                        title: context.t.settingsHelpGuide,
                        code: context.t.settingsHelpSectionCode,
                      ),
                      ActionRow(
                        icon: Icons.menu_book_outlined,
                        label: context.t.settingsShowOnboarding,
                        description: context.t.settingsShowOnboardingDesc,
                        onTap: () => Navigator.of(context).push(
                          smoothPageRoute<void>(
                            builder: (context) => OnboardingPage(
                              onComplete: () => Navigator.of(context).pop(),
                            ),
                          ),
                        ),
                      ),
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

  /// Per-session AI logs: persists the choice and applies it to
  /// [AgentLogger] at once (release builds included).
  Future<void> _setLogs(bool value) async {
    ref.read(sessionLogsEnabledProvider.notifier).state = value;
    AgentLogger.setEnabled(value);
    await ref.read(settingsServiceProvider).saveSessionLogsEnabled(value);
  }

  /// How the parts of an operator's file open: all unfolded (on) or folded.
  Future<void> _setFoldOpen(bool value) async {
    ref.read(profileSectionsOpenProvider.notifier).state = value;
    await ref.read(settingsServiceProvider).saveProfileSectionsOpen(value);
  }
}

/// A setting chosen among a few values: its name and what the current value
/// means, the choices as a segmented control under them, full width.
class _ChoiceRow<T> extends ConsumerWidget {
  const _ChoiceRow({
    super.key,
    required this.title,
    required this.description,
    required this.value,
    required this.options,
    required this.onChanged,
    this.enabled = true,
  });

  final String title;
  final String description;
  final T value;
  final List<(T, String)> options;
  final ValueChanged<T> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: theme.divider)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: theme.ui(16, weight: 600)),
          const SizedBox(height: 2),
          Text(
            description,
            style: theme.text(13, color: theme.textSecondary, height: 1.45),
          ),
          const SizedBox(height: 10),
          IgnorePointer(
            ignoring: !enabled,
            child: Opacity(
              opacity: enabled ? 1 : 0.45,
              child: SegmentedChoice<T>(
                options: options,
                value: value,
                onChanged: onChanged,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
