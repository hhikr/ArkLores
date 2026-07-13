import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'features/settings/api_settings_page.dart';
import 'features/settings/knowledge_base_page.dart';
import 'features/settings/onboarding_page.dart';
import 'shared/l10n/generated/app_localizations.dart';
import 'shared/l10n/locale_provider.dart';
import 'shared/providers/settings_provider.dart';
import 'shared/providers/theme_provider.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const ProviderScope(
      child: ArkLoresApp(),
    ),
  );
}

/// Root application widget.
class ArkLoresApp extends ConsumerStatefulWidget {
  const ArkLoresApp({super.key});

  @override
  ConsumerState<ArkLoresApp> createState() => _ArkLoresAppState();
}

class _ArkLoresAppState extends ConsumerState<ArkLoresApp> {
  bool _checkingOnboarding = true;
  bool _onboardingDone = false;

  @override
  void initState() {
    super.initState();
    _checkOnboarding();
  }

  Future<void> _checkOnboarding() async {
    int retryCount = 0;
    const maxRetries = 3;
    const retryDelay = Duration(milliseconds: 200);

    while (retryCount < maxRetries) {
      try {
        final service = ref.read(settingsServiceProvider);
        final done = await service.isOnboardingDone();

        await ref.read(apiConfigProvider.notifier).load();

        if (mounted) {
          setState(() {
            _checkingOnboarding = false;
            _onboardingDone = done;
          });
        }
        return;
      } catch (_) {
        retryCount++;
        if (retryCount >= maxRetries) {
          if (mounted) {
            setState(() {
              _checkingOnboarding = false;
              _onboardingDone = false;
            });
          }
        } else {
          await Future.delayed(retryDelay);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider);
    final locale = ref.watch(localeProvider);

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
      home: _buildHome(),
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

  Widget _buildHome() {
    if (_checkingOnboarding) {
      final theme = ref.watch(themeProvider);
      return Scaffold(
        backgroundColor: theme.bgPrimary,
        body: Center(
          child: CircularProgressIndicator(color: theme.accentPrimary),
        ),
      );
    }

    if (!_onboardingDone) {
      return OnboardingPage(
        onComplete: () {
          if (mounted) {
            setState(() => _onboardingDone = true);
          }
        },
      );
    }

    return const MainShell();
  }
}
