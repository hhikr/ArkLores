import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/llm/llm_client.dart';
import 'features/settings/api_settings_page.dart';
import 'features/settings/knowledge_base_page.dart';
import 'features/settings/onboarding_page.dart';
import 'features/settings/settings_service.dart';
import 'shared/l10n/generated/app_localizations.dart';
import 'shared/l10n/locale_provider.dart';
import 'shared/providers/settings_provider.dart';
import 'shared/providers/theme_provider.dart';
import 'shared/theme/app_theme.dart';
import 'shared/widgets/industrial_ui.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final settingsService = SettingsService();

  // Load onboarding status
  bool onboardingDone = false;
  try {
    onboardingDone = await settingsService.isOnboardingDone();
  } catch (e) {
    debugPrint('[Startup] Error reading onboarding status: $e');
  }

  // Load API config
  LLMConfig apiConfig = const LLMConfig();
  try {
    apiConfig = await settingsService.loadApiConfig();
  } catch (e) {
    debugPrint('[Startup] Error loading API config: $e');
  }

  runApp(
    ProviderScope(
      overrides: [
        onboardingDoneProvider.overrideWithValue(onboardingDone),
        initialApiConfigProvider.overrideWithValue(apiConfig),
      ],
      child: const ArkLoresApp(),
    ),
  );
}

/// Root application widget.
class ArkLoresApp extends ConsumerWidget {
  const ArkLoresApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    final locale = ref.watch(localeProvider);
    final onboardingDone = ref.watch(onboardingStatusProvider);

    final appTheme = buildAppTheme(theme);

    return MaterialApp(
      title: 'ArkLores',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: appTheme,
      theme: appTheme,
      locale: locale.flutterLocale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      builder: (context, child) => IndustrialBackdrop(
        theme: theme,
        child: child ?? const SizedBox.shrink(),
      ),
      home: onboardingDone
          ? const MainShell()
          : OnboardingPage(
              onComplete: () {
                ref.read(onboardingStatusProvider.notifier).state = true;
              },
            ),
      onGenerateRoute: (settings) {
        switch (settings.name) {
          case '/knowledge-base':
            return MaterialPageRoute(
              builder: (_) => const KnowledgeBasePage(),
              settings: settings,
            );
          case '/api-settings':
            return MaterialPageRoute(
              builder: (_) => const ApiSettingsPage(),
              settings: settings,
            );
          default:
            return null;
        }
      },
    );
  }
}

ThemeData buildAppTheme(AppThemeTokens tokens) {
  final scheme = ColorScheme.fromSeed(
    brightness: tokens.isDark ? Brightness.dark : Brightness.light,
    seedColor: tokens.accentPrimary,
    primary: tokens.accentPrimary,
    secondary: tokens.accentSecondary,
    surface: tokens.cardSurface,
    error: tokens.danger,
    onPrimary: tokens.isDark ? tokens.bgPrimary : tokens.textPrimary,
    onSurface: tokens.textPrimary,
  );
  final outline = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(2),
    side: BorderSide(color: tokens.cardBorder),
  );

  return ThemeData(
    useMaterial3: true,
    brightness: tokens.isDark ? Brightness.dark : Brightness.light,
    colorScheme: scheme,
    scaffoldBackgroundColor: Colors.transparent,
    canvasColor: tokens.bgSecondary,
    dividerColor: tokens.divider,
    splashColor: tokens.accentPrimary.withValues(alpha: 0.08),
    highlightColor: tokens.accentPrimary.withValues(alpha: 0.05),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: tokens.accentPrimary,
      selectionColor: tokens.accentPrimary.withValues(alpha: 0.24),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: tokens.bgSecondary,
      foregroundColor: tokens.textPrimary,
      elevation: 0,
      centerTitle: false,
      shape: Border(bottom: BorderSide(color: tokens.divider)),
      titleTextStyle: tokens.titleFont.copyWith(fontSize: 18),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: tokens.surfaceElevated,
      labelStyle: tokens.bodyFont.copyWith(color: tokens.textSecondary),
      hintStyle: tokens.bodyFont.copyWith(color: tokens.textMuted),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(2),
        borderSide: BorderSide(color: tokens.cardBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(2),
        borderSide: BorderSide(color: tokens.accentPrimary, width: 1.5),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        elevation: 0,
        backgroundColor: tokens.accentPrimary,
        foregroundColor: tokens.isDark ? tokens.bgPrimary : tokens.textPrimary,
        shape: outline.copyWith(side: BorderSide.none),
        textStyle: tokens.titleFont.copyWith(fontSize: 14),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: tokens.textPrimary,
        shape: outline,
        side: BorderSide(color: tokens.cardBorder),
        textStyle: tokens.titleFont.copyWith(fontSize: 14),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? tokens.bgPrimary
              : tokens.textSecondary,
        ),
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? tokens.accentPrimary
              : tokens.surfaceElevated,
        ),
        side: WidgetStatePropertyAll(BorderSide(color: tokens.cardBorder)),
        shape: WidgetStatePropertyAll(outline),
      ),
    ),
    tabBarTheme: TabBarThemeData(
      dividerColor: tokens.divider,
      indicatorColor: tokens.accentPrimary,
      labelColor: tokens.accentPrimary,
      unselectedLabelColor: tokens.textSecondary,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: tokens.accentPrimary,
      linearTrackColor: tokens.divider,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: tokens.surfaceElevated,
      contentTextStyle: tokens.bodyFont,
      shape: Border(top: BorderSide(color: tokens.accentPrimary)),
    ),
  );
}
