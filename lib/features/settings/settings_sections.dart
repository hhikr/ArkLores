/// The pages a settings category opens (SettingsPage lists the
/// categories): each the settings of one kind, in rows with a hairline
/// between them. A choice among a few is a segmented control under its name
/// (it gets the full width); a yes/no is a switch on the right; a row that
/// opens a page ends in `›`.
library;

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
import '../library/reading_text.dart' show readingFontSample;
import 'background_access.dart';
import 'onboarding_page.dart';
import 'wiki_sources_settings_page.dart';

/// One category's page: its title and code, the rows in a column at most
/// 640 wide, the last row closed by a hairline.
class _SectionPage extends ConsumerWidget {
  const _SectionPage({
    required this.title,
    required this.code,
    required this.children,
  });

  final String title;
  final String code;
  final List<Widget> children;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    return PageScaffold(
      title: title,
      code: code,
      scrollUnder: true,
      body: ListView(
        padding: pagePadding(context, const EdgeInsets.fromLTRB(16, 12, 16, 40)),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ...children,
                  Divider(height: 1, color: theme.divider),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Theme, reading font and language.
class AppearanceSettingsPage extends ConsumerWidget {
  const AppearanceSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(themeProvider);
    final themes = ref.read(themeProvider.notifier);
    final currentTheme = themes.currentTheme;
    final currentLocale = ref.watch(localeProvider);
    final service = ref.read(settingsServiceProvider);
    return _SectionPage(
      title: context.t.settingsAppearance,
      code: 'appearance',
      children: [
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
            service.saveTheme(next);
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
          labelStyle: readingFontSample,
          onChanged: (next) {
            themes.setReadingFont(next);
            service.saveReadingFont(next);
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
            service.saveLocale(next);
          },
        ),
      ],
    );
  }
}

/// The model services, the session logs and running in the background.
class AiSettingsPage extends ConsumerWidget {
  const AiSettingsPage({super.key});

  /// Per-session AI logs: persists the choice and applies it to
  /// [AgentLogger] at once (release builds included).
  static Future<void> _setLogs(WidgetRef ref, bool value) async {
    ref.read(sessionLogsEnabledProvider.notifier).state = value;
    AgentLogger.setEnabled(value);
    await ref.read(settingsServiceProvider).saveSessionLogsEnabled(value);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logs = ref.watch(sessionLogsEnabledProvider);
    return _SectionPage(
      title: context.t.settingsAiServices,
      code: context.t.settingsAiSectionCode,
      children: [
        ActionRow(
          icon: Icons.api_sharp,
          label: context.t.settingsApiSettings,
          description: context.t.settingsApiSettingsDesc,
          onTap: () => Navigator.pushNamed(context, '/api-settings'),
        ),
        ActionRow(
          key: const ValueKey('settings-session-logs'),
          icon: Icons.receipt_long_sharp,
          label: context.t.settingsSessionLogs,
          description: context.t.settingsSessionLogsDesc,
          onTap: () => _setLogs(ref, !logs),
          trailing: SquareSwitch(
            value: logs,
            semanticLabel: context.t.settingsSessionLogs,
            onChanged: (value) => _setLogs(ref, value),
          ),
        ),
        // Notifications and battery optimisation (Android).
        const BackgroundAccessRows(),
      ],
    );
  }
}

/// The knowledge bases, the wiki sites and how profiles open.
class KnowledgeSettingsPage extends ConsumerWidget {
  const KnowledgeSettingsPage({super.key});

  /// How the parts of an operator's file open: all unfolded (on) or folded.
  static Future<void> _setFoldOpen(WidgetRef ref, bool value) async {
    ref.read(profileSectionsOpenProvider.notifier).state = value;
    await ref.read(settingsServiceProvider).saveProfileSectionsOpen(value);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final foldOpen = ref.watch(profileSectionsOpenProvider);
    return _SectionPage(
      title: context.t.settingsKnowledgeCategory,
      code: context.t.settingsKnowledgeSectionCode,
      children: [
        ActionRow(
          icon: Icons.storage_sharp,
          label: context.t.settingsKnowledgeBase,
          description: context.t.settingsKnowledgeBaseDesc,
          onTap: () => Navigator.pushNamed(context, '/knowledge-base'),
        ),
        ActionRow(
          icon: Icons.dns_outlined,
          label: context.t.settingsWikiSources,
          description: context.t.settingsWikiSourcesDesc,
          onTap: () => Navigator.of(context).push(
            smoothPageRoute<void>(
              builder: (_) => const WikiSourcesSettingsPage(),
            ),
          ),
        ),
        ActionRow(
          key: const ValueKey('settings-profile-sections'),
          icon: Icons.unfold_more_sharp,
          label: context.t.settingsProfileSectionsOpen,
          description: context.t.settingsProfileSectionsOpenDesc,
          onTap: () => _setFoldOpen(ref, !foldOpen),
          trailing: SquareSwitch(
            value: foldOpen,
            semanticLabel: context.t.settingsProfileSectionsOpen,
            onChanged: (value) => _setFoldOpen(ref, value),
          ),
        ),
      ],
    );
  }
}

/// The onboarding again, and the version.
class HelpSettingsPage extends ConsumerWidget {
  const HelpSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _SectionPage(
      title: context.t.settingsHelpGuide,
      code: context.t.settingsHelpSectionCode,
      children: [
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
        ActionRow(
          icon: Icons.info_outline_sharp,
          label: context.t.settingsVersion,
          meta: context.t.settingsVersionLabel(appVersion),
          showChevron: false,
        ),
      ],
    );
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
    this.labelStyle,
  });

  final String title;
  final String description;
  final T value;
  final List<(T, String)> options;
  final ValueChanged<T> onChanged;
  final TextStyle Function(T value)? labelStyle;

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
          SegmentedChoice<T>(
            options: options,
            value: value,
            onChanged: onChanged,
            labelStyle: labelStyle,
          ),
        ],
      ),
    );
  }
}
