import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/agent/agent_logger.dart';
import 'core/agent/answer_options.dart';
import 'core/llm/embedding_client.dart';
import 'core/llm/llm_client.dart';
import 'features/settings/api_settings_page.dart';
import 'features/settings/app_icon_service.dart';
import 'features/settings/knowledge_base_page.dart';
import 'features/settings/onboarding_page.dart';
import 'features/settings/settings_service.dart';
import 'shared/l10n/generated/app_localizations.dart';
import 'shared/l10n/locale_provider.dart';
import 'shared/providers/settings_provider.dart';
import 'shared/providers/theme_provider.dart';
import 'shared/theme/app_theme.dart';
import 'shared/widgets/industrial_ui.dart';
import 'shared/widgets/smooth_page_route.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final settingsService = SettingsService();

  /// One saved setting, or [fallback] when it cannot be read.
  Future<T> load<T>(String what, Future<T> Function() read, T fallback) =>
      read().catchError((Object e) {
        debugPrint('[Startup] Error loading $what: $e');
        return fallback;
      });

  // The reads go to secure storage (a platform call each), so they run
  // together instead of one after another before the first frame.
  final (
    onboardingDone,
    apiConfig,
    embeddingConfig,
    mainTabIndex,
    appTheme,
    appLocale,
    sessionLogsEnabled,
    (nickname, answerOptions),
    _,
  ) = await (
    load('onboarding status', settingsService.isOnboardingDone, false),
    load('API config', settingsService.loadApiConfig, const LLMConfig()),
    load('embedding config', settingsService.loadEmbeddingConfig,
        defaultEmbeddingConfig,),
    load('main tab index', settingsService.loadMainTabIndex, 0),
    load('theme', settingsService.loadTheme, AppTheme.ark),
    load('locale', settingsService.loadLocale, SupportedLocale.zh),
    load('session log toggle', settingsService.loadSessionLogsEnabled, false),
    // A record's .wait takes at most nine futures.
    (
      load('nickname', settingsService.loadNickname, ''),
      load('answer options', settingsService.loadAnswerOptions,
          const AnswerOptions(),),
    ).wait,
    load(
      'launcher icon',
      () async =>
          AppIconService.setIcon(await settingsService.loadAppLauncherIcon()),
      null,
    ),
  ).wait;
  // Apply the user's per-session AI log toggle before any agent runs.
  AgentLogger.setEnabled(sessionLogsEnabled);

  runApp(
    ProviderScope(
      overrides: [
        onboardingDoneProvider.overrideWithValue(onboardingDone),
        initialApiConfigProvider.overrideWithValue(apiConfig),
        initialEmbeddingConfigProvider.overrideWithValue(embeddingConfig),
        initialMainTabIndexProvider.overrideWithValue(mainTabIndex),
        initialThemeProvider.overrideWithValue(appTheme),
        initialLocaleProvider.overrideWithValue(appLocale),
        initialSessionLogsEnabledProvider.overrideWithValue(sessionLogsEnabled),
        initialNicknameProvider.overrideWithValue(nickname),
        initialAnswerOptionsProvider.overrideWithValue(answerOptions),
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
      themeMode: theme.isDark ? ThemeMode.dark : ThemeMode.light,
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
            return smoothPageRoute(
              settings: settings,
              builder: (_) => const KnowledgeBasePage(),
            );
          case '/api-settings':
            return smoothPageRoute(
              settings: settings,
              builder: (_) => const ApiSettingsPage(),
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
    // Touch feedback that can be seen: the signal yellow at 5–8 % vanished
    // on the light grounds. A neutral wash of the text colour reads on both
    // themes; the press scale and haptics come from `PressFeedback`.
    splashColor: tokens.textPrimary.withValues(alpha: 0.12),
    highlightColor: tokens.textPrimary.withValues(alpha: 0.07),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: SmoothPageTransitionsBuilder(),
        TargetPlatform.iOS: SmoothPageTransitionsBuilder(),
        TargetPlatform.windows: SmoothPageTransitionsBuilder(),
        TargetPlatform.linux: SmoothPageTransitionsBuilder(),
        TargetPlatform.macOS: SmoothPageTransitionsBuilder(),
      },
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: tokens.accentPrimary,
      selectionColor: tokens.accentPrimary.withValues(alpha: 0.24),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: tokens.bgSecondary,
      foregroundColor: tokens.textPrimary,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      // Slim: 48 high, a hairline below, a title the size of a heading
      // rather than a banner.
      toolbarHeight: 48,
      titleSpacing: 4,
      shape: Border(bottom: BorderSide(color: tokens.divider, width: 0.5)),
      iconTheme: IconThemeData(color: tokens.textPrimary, size: 22),
      actionsIconTheme: IconThemeData(color: tokens.textSecondary, size: 22),
      titleTextStyle: tokens.titleFont.copyWith(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: tokens.textPrimary,
      ),
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
    // Text buttons would take the primary colour (the signal yellow), which
    // is too faint as text; text uses accentText.
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: tokens.accentText),
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
