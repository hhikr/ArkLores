import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/agent/agent_logger.dart';
import 'core/agent/answer_options.dart';
import 'core/llm/embedding_client.dart';
import 'core/llm/llm_client.dart';
import 'features/ai/phone_bridge.dart';
import 'features/settings/api_settings_page.dart';
import 'features/settings/knowledge_base_page.dart';
import 'features/settings/onboarding_page.dart';
import 'features/settings/settings_service.dart';
import 'shared/frame_log.dart';
import 'shared/l10n/generated/app_localizations.dart';
import 'shared/l10n/locale_provider.dart';
import 'shared/providers/settings_provider.dart';
import 'shared/providers/theme_provider.dart';
import 'shared/theme/app_theme.dart';
import 'shared/theme/cut_border.dart';
import 'shared/theme/system_night_mode.dart';
import 'shared/widgets/industrial_ui.dart';
import 'shared/widgets/launch_curtain.dart';
import 'shared/widgets/smooth_page_route.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  startFrameLog();

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
    (
      nickname,
      answerOptions,
      profileSectionsOpen,
      readingFont,
      contextWarnTokens,
      compactPercent,
    ),
  ) = await (
    load('onboarding status', settingsService.isOnboardingDone, false),
    load('API config', settingsService.loadApiConfig, const LLMConfig()),
    load('embedding config', settingsService.loadEmbeddingConfig,
        defaultEmbeddingConfig,),
    load('main tab index', settingsService.loadMainTabIndex, 0),
    load('theme', settingsService.loadTheme, AppTheme.system),
    load('locale', settingsService.loadLocale, SupportedLocale.zh),
    load('session log toggle', settingsService.loadSessionLogsEnabled, false),
    // A record's .wait takes at most nine futures.
    (
      load('nickname', settingsService.loadNickname, ''),
      load('answer options', settingsService.loadAnswerOptions,
          const AnswerOptions(),),
      load('profile fold setting', settingsService.loadProfileSectionsOpen,
          true,),
      load('reading font', settingsService.loadReadingFont, ReadingFont.sans),
      load('context warning', settingsService.loadContextWarnTokens, defaultContextWarnTokens),
      load('compaction point', settingsService.loadCompactPercent,
          defaultCompactPercent,),
    ).wait,
  ).wait;
  // Apply the user's per-session AI log toggle before any agent runs.
  AgentLogger.setEnabled(sessionLogsEnabled);
  // The system starts the app in its own light or dark from now on (a
  // theme chosen before this was told to the system).
  unawaited(syncSystemNightMode(appTheme));

  runApp(
    ProviderScope(
      overrides: [
        launchCurtainProvider.overrideWithValue(true),
        onboardingDoneProvider.overrideWithValue(onboardingDone),
        initialApiConfigProvider.overrideWithValue(apiConfig),
        initialEmbeddingConfigProvider.overrideWithValue(embeddingConfig),
        initialMainTabIndexProvider.overrideWithValue(mainTabIndex),
        initialThemeProvider.overrideWithValue(appTheme),
        initialReadingFontProvider.overrideWithValue(readingFont),
        initialContextWarnTokensProvider.overrideWithValue(contextWarnTokens),
        initialCompactPercentProvider.overrideWithValue(compactPercent),
        initialLocaleProvider.overrideWithValue(appLocale),
        initialSessionLogsEnabledProvider.overrideWithValue(sessionLogsEnabled),
        initialNicknameProvider.overrideWithValue(nickname),
        initialAnswerOptionsProvider.overrideWithValue(answerOptions),
        initialProfileSectionsOpenProvider
            .overrideWithValue(profileSectionsOpen),
      ],
      // Only in local test builds (`install_local.ps1 -Bridge`).
      child: phoneBridgeEnabled
          ? const PhoneBridgeHost(child: ArkLoresApp())
          : const ArkLoresApp(),
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
      // Theme changes switch at once: the app's tokens change in one frame,
      // so Material's 200 ms colour fade would only lag behind them.
      themeAnimationDuration: Duration.zero,
      darkTheme: appTheme,
      theme: appTheme,
      locale: locale.flutterLocale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      builder: (context, child) => LaunchCurtain(
        child: IndustrialBackdrop(
          theme: theme,
          child: child ?? const SizedBox.shrink(),
        ),
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
  // Primary is ink (dark: the accent blue), not the yellow: stock Material
  // parts draw lines and text in primary (cursors, focus lines, progress,
  // checkboxes), and yellow lines vanish on the light paper. The accent as
  // a fill is applied by hand.
  final scheme = ColorScheme(
    brightness: tokens.isDark ? Brightness.dark : Brightness.light,
    primary: tokens.trace,
    onPrimary: tokens.isDark ? tokens.onAccent : tokens.bgPrimary,
    secondary: tokens.accentPrimary,
    onSecondary: tokens.onAccent,
    tertiary: tokens.accentPrimary,
    onTertiary: tokens.onAccent,
    error: tokens.danger,
    onError: tokens.cardSurface,
    surface: tokens.cardSurface,
    onSurface: tokens.textPrimary,
    onSurfaceVariant: tokens.textSecondary,
    surfaceContainerHighest: tokens.surfaceElevated,
    surfaceContainerHigh: tokens.surfaceElevated,
    surfaceContainer: tokens.cardSurface,
    surfaceContainerLow: tokens.cardSurface,
    surfaceContainerLowest: tokens.cardSurface,
    outline: tokens.cardBorder,
    outlineVariant: tokens.divider,
    surfaceTint: Colors.transparent,
  );
  // Square everywhere; a cut corner only on what can be pressed.
  final outline = RoundedRectangleBorder(
    side: BorderSide(color: tokens.cardBorder),
  );
  const square = RoundedRectangleBorder();
  const cut = CutBorder.br(8);
  final buttonText = sairaStyle(size: 15, weight: 700);

  return ThemeData(
    useMaterial3: true,
    brightness: tokens.isDark ? Brightness.dark : Brightness.light,
    colorScheme: scheme,
    scaffoldBackgroundColor: Colors.transparent,
    canvasColor: tokens.cardSurface,
    dividerColor: tokens.divider,
    dividerTheme: DividerThemeData(color: tokens.divider, thickness: 1, space: 1),
    // No ink ripples: pressing answers with a short, hard tint (and in the
    // app's own parts with a wipe of the accent).
    splashFactory: NoSplash.splashFactory,
    splashColor: Colors.transparent,
    highlightColor: tokens.textPrimary.withValues(alpha: 0.08),
    hoverColor: tokens.textPrimary.withValues(alpha: 0.04),
    focusColor: tokens.accentPrimary.withValues(alpha: 0.35),
    materialTapTargetSize: MaterialTapTargetSize.padded,
    visualDensity: VisualDensity.standard,
    iconTheme: IconThemeData(color: tokens.textPrimary, size: 22),
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
      cursorColor: tokens.trace,
      selectionColor: tokens.accentPrimary.withValues(alpha: tokens.isDark ? 0.35 : 0.55),
      selectionHandleColor: tokens.trace,
    ),
    // Inputs: a panel with a frame, the label above in the interface face,
    // help below; focused, the bottom edge becomes a 2px trace line.
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: tokens.cardSurface,
      floatingLabelBehavior: FloatingLabelBehavior.always,
      labelStyle: sairaStyle(size: 14, weight: 600, color: tokens.textSecondary),
      floatingLabelStyle:
          sairaStyle(size: 14, weight: 600, color: tokens.textPrimary),
      hintStyle: tokens.bodyFont.copyWith(color: tokens.textMuted),
      helperStyle: tokens.bodyFont.copyWith(color: tokens.textSecondary, fontSize: 12.5),
      helperMaxLines: 3,
      errorStyle: tokens.bodyFont.copyWith(color: tokens.textPrimary, fontSize: 12.5),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: BorderSide(color: tokens.cardBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: BorderSide(color: tokens.cardBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: BorderSide(color: tokens.trace, width: 2),
      ),
      // An error is not red (red is for deleting): a thick accent frame and
      // the message in ink below.
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: BorderSide(color: tokens.accentPrimary, width: 2),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: BorderSide(color: tokens.trace, width: 2),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: BorderSide(color: tokens.divider),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: tokens.accentPrimary,
        foregroundColor: tokens.onAccent,
        disabledBackgroundColor: tokens.surfaceElevated,
        disabledForegroundColor: tokens.textMuted,
        minimumSize: const Size(64, 48),
        padding: const EdgeInsets.fromLTRB(18, 0, 22, 0),
        shape: cut,
        textStyle: buttonText,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        shape: square,
        minimumSize: const Size(48, 48),
        foregroundColor: tokens.textPrimary,
        disabledForegroundColor: tokens.textMuted,
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      shape: cut,
      elevation: 0,
      focusElevation: 0,
      hoverElevation: 0,
      highlightElevation: 0,
      backgroundColor: tokens.accentPrimary,
      foregroundColor: tokens.onAccent,
    ),
    chipTheme: ChipThemeData(
      shape: const CutBorder.br(7),
      side: BorderSide.none,
      backgroundColor: tokens.surfaceElevated,
      selectedColor: tokens.accentPrimary,
      checkmarkColor: tokens.onAccent,
      labelStyle: sairaStyle(size: 14, weight: 500, color: tokens.textPrimary),
      secondaryLabelStyle:
          sairaStyle(size: 14, weight: 700, color: tokens.onAccent),
      padding: const EdgeInsets.fromLTRB(6, 6, 10, 6),
    ),
    cardTheme: const CardThemeData(shape: square, elevation: 0),
    dialogTheme: DialogThemeData(
      shape: CutBorder(bottomRight: 20, side: BorderSide(color: tokens.divider)),
      backgroundColor: tokens.cardSurface,
      elevation: 0,
      titleTextStyle: sairaStyle(size: 19, weight: 700, color: tokens.textPrimary),
      contentTextStyle: tokens.bodyFont.copyWith(
        fontSize: 15,
        color: tokens.textSecondary,
        height: 1.6,
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      shape: const CutBorder(topLeft: 24),
      backgroundColor: tokens.cardSurface,
      modalBackgroundColor: tokens.cardSurface,
      elevation: 0,
      modalElevation: 0,
      showDragHandle: false,
    ),
    popupMenuTheme: PopupMenuThemeData(
      shape: outline.copyWith(side: BorderSide(color: tokens.divider)),
      color: tokens.cardSurface,
      elevation: 0,
      textStyle: sairaStyle(size: 15, weight: 500, color: tokens.textPrimary),
    ),
    menuTheme: MenuThemeData(
      style: MenuStyle(
        shape: WidgetStatePropertyAll(
          outline.copyWith(side: BorderSide(color: tokens.divider)),
        ),
        elevation: const WidgetStatePropertyAll(0),
        backgroundColor: WidgetStatePropertyAll(tokens.cardSurface),
      ),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: const BoxDecoration(color: Color(0xFF161616)),
      textStyle: sairaStyle(size: 13, weight: 600, color: const Color(0xFFEDEDED)),
      waitDuration: const Duration(milliseconds: 400),
    ),
    listTileTheme: ListTileThemeData(
      shape: square,
      minVerticalPadding: 10,
      iconColor: tokens.textSecondary,
      textColor: tokens.textPrimary,
      titleTextStyle: sairaStyle(size: 16, weight: 600, color: tokens.textPrimary),
      subtitleTextStyle: tokens.bodyFont.copyWith(
        fontSize: 13,
        color: tokens.textSecondary,
      ),
    ),
    expansionTileTheme: ExpansionTileThemeData(
      shape: const Border(),
      collapsedShape: const Border(),
      iconColor: tokens.textPrimary,
      collapsedIconColor: tokens.textSecondary,
      textColor: tokens.textPrimary,
      collapsedTextColor: tokens.textPrimary,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        elevation: 0,
        backgroundColor: tokens.accentPrimary,
        foregroundColor: tokens.onAccent,
        disabledBackgroundColor: tokens.surfaceElevated,
        disabledForegroundColor: tokens.textMuted,
        minimumSize: const Size(64, 48),
        padding: const EdgeInsets.fromLTRB(18, 0, 22, 0),
        shape: cut,
        textStyle: buttonText,
      ),
    ),
    // Text buttons: ink text (the yellow is unreadable as text), at least
    // 48 high to the finger.
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: tokens.textPrimary,
        disabledForegroundColor: tokens.textMuted,
        minimumSize: const Size(48, 48),
        shape: cut,
        textStyle: sairaStyle(size: 15, weight: 700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: tokens.textPrimary,
        backgroundColor: tokens.surfaceElevated,
        disabledForegroundColor: tokens.textMuted,
        minimumSize: const Size(64, 48),
        padding: const EdgeInsets.fromLTRB(18, 0, 22, 0),
        shape: cut,
        side: BorderSide.none,
        textStyle: buttonText,
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? tokens.bgPrimary
              : tokens.textPrimary,
        ),
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? tokens.textPrimary
              : Colors.transparent,
        ),
        side: WidgetStatePropertyAll(BorderSide(color: tokens.textPrimary)),
        shape: const WidgetStatePropertyAll(square),
        minimumSize: const WidgetStatePropertyAll(Size(48, 44)),
        textStyle: WidgetStatePropertyAll(sairaStyle(size: 14, weight: 600)),
      ),
    ),
    tabBarTheme: TabBarThemeData(
      dividerColor: tokens.divider,
      indicatorColor: tokens.trace,
      labelColor: tokens.textPrimary,
      unselectedLabelColor: tokens.textSecondary,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected)
            ? tokens.onAccent
            : tokens.cardSurface,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected)
            ? tokens.accentPrimary
            : tokens.surfaceElevated,
      ),
      trackOutlineColor: WidgetStatePropertyAll(tokens.cardBorder),
    ),
    checkboxTheme: CheckboxThemeData(
      shape: square,
      fillColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected)
            ? tokens.accentPrimary
            : Colors.transparent,
      ),
      checkColor: WidgetStatePropertyAll(tokens.onAccent),
      side: BorderSide(color: tokens.cardBorder, width: 1.5),
    ),
    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected)
            ? tokens.textPrimary
            : tokens.cardBorder,
      ),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: tokens.trace,
      linearTrackColor: tokens.surfaceElevated,
      linearMinHeight: 4,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: const Color(0xFF161616),
      contentTextStyle:
          sairaStyle(size: 14, weight: 600, color: const Color(0xFFEDEDED)),
      actionTextColor: tokens.accentPrimary,
      behavior: SnackBarBehavior.floating,
      elevation: 0,
      shape: const RoundedRectangleBorder(),
    ),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStatePropertyAll(
        tokens.textPrimary.withValues(alpha: 0.35),
      ),
      radius: Radius.zero,
      thickness: const WidgetStatePropertyAll(4),
    ),
  );
}
