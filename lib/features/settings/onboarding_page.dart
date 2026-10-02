import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/llm/llm_client.dart';
import '../../shared/l10n/l10n.dart';
import '../../shared/providers/settings_provider.dart';
import '../../shared/providers/theme_provider.dart';
import '../../shared/theme/app_theme.dart';

/// Onboarding page shown on first launch.
///
/// Guides users through:
/// 1. App introduction
/// 2. Chat API Key configuration
/// 3. Ready to explore
class OnboardingPage extends ConsumerStatefulWidget {

  const OnboardingPage({super.key, required this.onComplete});
  final VoidCallback onComplete;

  @override
  ConsumerState<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends ConsumerState<OnboardingPage> {
  final PageController _pageController = PageController();
  int _currentStep = 0;

  // Chat API config form controllers.
  late TextEditingController _baseUrlController;
  late TextEditingController _apiKeyController;
  late TextEditingController _chatModelController;

  @override
  void initState() {
    super.initState();
    _baseUrlController = TextEditingController(
      text: 'https://api.deepseek.com/v1',
    );
    _apiKeyController = TextEditingController();
    _chatModelController = TextEditingController(
      text: 'deepseek-v4-flash',
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    _baseUrlController.dispose();
    _apiKeyController.dispose();
    _chatModelController.dispose();
    super.dispose();
  }

  Future<void> _complete() async {
    final service = ref.read(settingsServiceProvider);
    await service.markOnboardingDone();
    widget.onComplete();
  }

  Future<void> _skip() async {
    final service = ref.read(settingsServiceProvider);
    await service.markOnboardingDone();
    widget.onComplete();
  }

  Future<void> _saveAndContinue() async {
    final chatApiKey = _apiKeyController.text.trim();
    final keyError =
        LLMConfig.apiKeyFormatError(chatApiKey, label: 'Chat API Key');
    if (keyError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(keyError)),
      );
      return;
    }

    final config = LLMConfig(
      chatBaseUrl: _baseUrlController.text.trim(),
      chatApiKey: chatApiKey,
      chatModel: _chatModelController.text.trim(),
    );

    if (config.isValid) {
      await ref.read(apiConfigProvider.notifier).save(config);
    }

    await _pageController.nextPage(
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider);
    final currentLocale = ref.watch(localeProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Column(
          children: [
            // ── Top Bar (Language Switcher & Skip Button) ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Language Toggle (top left)
                  TextButton.icon(
                    onPressed: () {
                      final next = currentLocale == SupportedLocale.en
                          ? SupportedLocale.zh
                          : SupportedLocale.en;
                      ref.read(localeProvider.notifier).switchTo(next);
                      ref.read(settingsServiceProvider).saveLocale(next);
                    },
                    icon: Icon(
                      Icons.translate_rounded,
                      color: theme.accentPrimary,
                      size: 18,
                    ),
                    label: Text(
                      currentLocale == SupportedLocale.en
                          ? SupportedLocale.zh.displayName
                          : SupportedLocale.en.displayName,
                      style: theme.titleFont.copyWith(
                        color: theme.textPrimary,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  // "Not now" (top right), only on the API step: the last
                  // step's main button already finishes onboarding.
                  if (_currentStep == 1)
                    ExcludeFocus(
                      child: TextButton(
                        onPressed: _skip,
                        child: Text(
                          context.t.onboardingNotNow,
                          style: theme.bodyFont.copyWith(
                            color: theme.textSecondary,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    )
                  else
                    const SizedBox(width: 48), // Spacer to balance layout
                ],
              ),
            ),

            // ── PageView ────────────────────────────────────
            Expanded(
              child: PageView(
                controller: _pageController,
                onPageChanged: (i) => setState(() => _currentStep = i),
                // Steps advance only through their buttons, never by swiping.
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _buildWelcomeStep(theme),
                  _buildApiConfigStep(theme),
                  _buildDoneStep(theme),
                ],
              ),
            ),

            // ── Step indicators ─────────────────────────────
            Padding(
              padding: const EdgeInsets.only(bottom: 32),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(3, (i) {
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: _currentStep == i ? 28 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: _currentStep == i
                          ? theme.accentPrimary
                          : theme.divider,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  );
                }),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWelcomeStep(AppThemeTokens theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.auto_stories_rounded,
            size: 80,
            color: theme.accentPrimary,
          ),
          const SizedBox(height: 24),
          Text(
            context.t.onboardingWelcomeTitle,
            style: theme.titleFont.copyWith(fontSize: 28),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Text(
            context.t.onboardingWelcomeDesc,
            style: theme.bodyFont.copyWith(
              color: theme.textSecondary,
              fontSize: 15,
              height: 1.6,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 40),
          ElevatedButton(
            onPressed: () {
              _pageController.nextPage(
                duration: const Duration(milliseconds: 400),
                curve: Curves.easeInOut,
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: theme.accentPrimary,
              foregroundColor: theme.bgPrimary,
              padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text(
              context.t.onboardingGetStarted,
              style: theme.titleFont.copyWith(fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildApiConfigStep(AppThemeTokens theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.key_rounded,
            size: 56,
            color: theme.accentPrimary,
          ),
          const SizedBox(height: 16),
          Text(
            context.t.onboardingApiTitle,
            style: theme.titleFont.copyWith(fontSize: 22),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            context.t.onboardingApiDesc,
            style: theme.bodyFont.copyWith(
              color: theme.textSecondary,
              fontSize: 14,
              height: 1.4,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 28),
          _buildInputField(
            label: context.t.apiSettingsLabelBaseUrl,
            controller: _baseUrlController,
            hint: 'https://api.deepseek.com/v1',
            theme: theme,
          ),
          const SizedBox(height: 14),
          _buildInputField(
            label: context.t.apiSettingsLabelApiKey,
            controller: _apiKeyController,
            hint: 'sk-...',
            theme: theme,
            secret: true,
          ),
          const SizedBox(height: 14),
          _buildInputField(
            label: context.t.apiSettingsLabelModel,
            controller: _chatModelController,
            hint: 'deepseek-v4-flash',
            theme: theme,
          ),
          const SizedBox(height: 28),
          ElevatedButton(
            onPressed: _saveAndContinue,
            style: ElevatedButton.styleFrom(
              backgroundColor: theme.accentPrimary,
              foregroundColor: theme.bgPrimary,
              padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text(
              context.t.onboardingSaveContinue,
              style: theme.titleFont.copyWith(fontSize: 16),
            ),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: _skip,
            child: Text(
              context.t.onboardingConfigureLater,
              style: theme.bodyFont.copyWith(
                color: theme.textSecondary,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDoneStep(AppThemeTokens theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.check_circle_rounded,
            size: 80,
            color: theme.accentPrimary,
          ),
          const SizedBox(height: 24),
          Text(
            context.t.onboardingDoneTitle,
            style: theme.titleFont.copyWith(fontSize: 28),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Text(
            context.t.onboardingDoneDesc,
            style: theme.bodyFont.copyWith(
              color: theme.textSecondary,
              fontSize: 15,
              height: 1.6,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 40),
          ElevatedButton(
            onPressed: _complete,
            style: ElevatedButton.styleFrom(
              backgroundColor: theme.accentPrimary,
              foregroundColor: theme.bgPrimary,
              padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text(
              context.t.onboardingStartExploring,
              style: theme.titleFont.copyWith(fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputField({
    required String label,
    required TextEditingController controller,
    required String hint,
    required AppThemeTokens theme,
    bool secret = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(
            label,
            style: theme.bodyFont.copyWith(
              color: theme.textSecondary,
              fontSize: 13,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: theme.bgSecondary,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: theme.divider, width: 1),
          ),
          child: TextField(
            controller: controller,
            // Keys stay visible, but the keyboard must not learn, suggest or
            // autocorrect them.
            keyboardType: secret ? TextInputType.visiblePassword : null,
            autocorrect: !secret,
            enableSuggestions: !secret,
            style: theme.bodyFont.copyWith(
              color: theme.textPrimary,
              fontSize: 14,
            ),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(
                color: theme.textSecondary.withValues(alpha: 0.5),
              ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
