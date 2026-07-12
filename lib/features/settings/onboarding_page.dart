import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/llm/llm_client.dart';
import '../../shared/providers/settings_provider.dart';
import '../../shared/providers/theme_provider.dart';
import '../../shared/theme/app_theme.dart';

/// Onboarding page shown on first launch.
///
/// Guides users through:
/// 1. App introduction
/// 2. Chat API Key configuration (embedding can be set later in Settings)
/// 3. Ready to explore
class OnboardingPage extends ConsumerStatefulWidget {
  final VoidCallback onComplete;

  const OnboardingPage({super.key, required this.onComplete});

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
  bool _obscureApiKey = true;

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
    final config = LLMConfig(
      chatBaseUrl: _baseUrlController.text.trim(),
      chatApiKey: _apiKeyController.text.trim(),
      chatModel: _chatModelController.text.trim(),
    );

    if (config.isValid) {
      await ref.read(apiConfigProvider.notifier).save(config);
    }

    _pageController.nextPage(
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider);

    return Scaffold(
      backgroundColor: theme.bgPrimary,
      body: SafeArea(
        child: Column(
          children: [
            // ── Skip button (top right) ─────────────────────
            Align(
              alignment: Alignment.topRight,
              child: TextButton(
                onPressed: _skip,
                child: Text(
                  'Skip',
                  style: theme.bodyFont.copyWith(
                    color: theme.textSecondary,
                    fontSize: 14,
                  ),
                ),
              ),
            ),

            // ── PageView ────────────────────────────────────
            Expanded(
              child: PageView(
                controller: _pageController,
                onPageChanged: (i) => setState(() => _currentStep = i),
                physics: _currentStep == 1
                    ? const NeverScrollableScrollPhysics()
                    : null,
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
            'Welcome to ArkLores',
            style: theme.titleFont.copyWith(fontSize: 28),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Text(
            'Your AI-enhanced companion for exploring\n'
            'Arknights and Endfield lore.\n\n'
            '• Browse PRTS & Endfield Wikis\n'
            '• AI-powered fact checking & summaries\n'
            '• Import your lore books\n'
            '• Immersive character roleplay',
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
              'Get Started',
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
            'Configure Chat API',
            style: theme.titleFont.copyWith(fontSize: 22),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'ArkLores uses your own AI API key.\n'
            'Configure at least a Chat provider now;\n'
            'Embedding can be set up later in Settings.',
            style: theme.bodyFont.copyWith(
              color: theme.textSecondary,
              fontSize: 14,
              height: 1.4,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 28),
          _buildInputField(
            label: 'Base URL',
            controller: _baseUrlController,
            hint: 'https://api.deepseek.com/v1',
            theme: theme,
          ),
          const SizedBox(height: 14),
          _buildInputField(
            label: 'API Key',
            controller: _apiKeyController,
            hint: 'sk-...',
            theme: theme,
            obscureText: _obscureApiKey,
            suffix: IconButton(
              icon: Icon(
                _obscureApiKey
                    ? Icons.visibility_off_rounded
                    : Icons.visibility_rounded,
                color: theme.textSecondary,
                size: 20,
              ),
              onPressed: () =>
                  setState(() => _obscureApiKey = !_obscureApiKey),
            ),
          ),
          const SizedBox(height: 14),
          _buildInputField(
            label: 'Model',
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
              'Save & Continue',
              style: theme.titleFont.copyWith(fontSize: 16),
            ),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: _skip,
            child: Text(
              'Configure later',
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
            'All Set!',
            style: theme.titleFont.copyWith(fontSize: 28),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Text(
            'You\'re ready to explore the world of\n'
            'Arknights and Endfield.\n\n'
            'Visit Settings > API Settings to configure\n'
            'a separate Embedding provider if needed,\n'
            'or start browsing the Wiki!',
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
              'Start Exploring',
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
    bool obscureText = false,
    Widget? suffix,
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
            obscureText: obscureText,
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
              suffixIcon: suffix,
            ),
          ),
        ),
      ],
    );
  }
}
