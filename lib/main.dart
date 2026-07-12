import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'features/settings/knowledge_base_page.dart';
import 'features/settings/onboarding_page.dart';
import 'features/settings/settings_service.dart';
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
///
/// Checks onboarding status on startup and shows the onboarding
/// flow if the user hasn't completed it yet.
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
    final service = SettingsService();
    final done = await service.isOnboardingDone();
    if (mounted) {
      setState(() {
        _checkingOnboarding = false;
        _onboardingDone = done;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider);

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
      home: _buildHome(),
      onGenerateRoute: (settings) {
        switch (settings.name) {
          case '/knowledge-base':
            return MaterialPageRoute(
              builder: (_) => const KnowledgeBasePage(),
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
