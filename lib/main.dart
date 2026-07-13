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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final settingsService = SettingsService();

  // Load onboarding status
  bool onboardingDone = false;
  try {
    onboardingDone = await settingsService.isOnboardingDone();
  } catch (e) {
    print('[Startup] Error reading onboarding status: $e');
  }

  // Load API config
  LLMConfig apiConfig = const LLMConfig();
  try {
    apiConfig = await settingsService.loadApiConfig();
  } catch (e) {
    print('[Startup] Error loading API config: $e');
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

    return MaterialApp(
      title: 'ArkLores',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData.dark(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: theme.bgPrimary,
      ),
      theme: ThemeData.light(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: theme.bgPrimary,
      ),
      locale: locale.flutterLocale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
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
