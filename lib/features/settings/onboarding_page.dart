import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/llm/llm_client.dart';
import '../../shared/l10n/l10n.dart';
import '../../shared/providers/settings_provider.dart';
import '../../shared/providers/theme_provider.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/theme/motion.dart';
import '../../shared/widgets/ef_widgets.dart';

/// Onboarding page shown on first launch, in three steps:
/// 1. what the app is,
/// 2. the chat service (can be left for later),
/// 3. ready.
///
/// A numbered step bar on top says where the reader is; the step's main
/// button is at the bottom, within reach of the thumb; Back (the system's or
/// the step's) returns to the step before.
class OnboardingPage extends ConsumerStatefulWidget {
  const OnboardingPage({super.key, required this.onComplete});
  final VoidCallback onComplete;

  @override
  ConsumerState<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends ConsumerState<OnboardingPage> {
  final PageController _pageController = PageController();
  int _currentStep = 0;
  String? _keyError;
  bool _keyShown = false;

  // Chat API config form controllers.
  late TextEditingController _baseUrlController;
  late TextEditingController _apiKeyController;
  late TextEditingController _chatModelController;

  @override
  void initState() {
    super.initState();
    _baseUrlController = TextEditingController(
      text: 'https://api.z.ai/api/paas/v4',
    );
    _apiKeyController = TextEditingController();
    _chatModelController = TextEditingController(
      text: 'glm-5.3-flash',
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

  Future<void> _go(int step) => _pageController.animateToPage(
        step,
        duration: Motion.of(context, Motion.shutter),
        curve: Motion.mech,
      );

  Future<void> _saveAndContinue() async {
    final chatApiKey = _apiKeyController.text.trim();
    final keyError =
        LLMConfig.apiKeyFormatError(chatApiKey, label: 'Chat API Key');
    setState(() => _keyError = keyError);
    if (keyError != null) return;

    final config = LLMConfig(
      chatBaseUrl: _baseUrlController.text.trim(),
      chatApiKey: chatApiKey,
      chatModel: _chatModelController.text.trim(),
    );

    if (config.isValid) {
      await ref.read(apiConfigProvider.notifier).save(config);
    }
    await _go(2);
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider);
    final currentLocale = ref.watch(localeProvider);

    return PopScope(
      // Back steps back through the steps before it leaves.
      canPop: _currentStep == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _currentStep > 0) _go(_currentStep - 1);
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Column(
            children: [
              const TriStrip(),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 8, 0),
                child: Row(
                  children: [
                    Text(
                      '${(_currentStep + 1).toString().padLeft(2, '0')} / 03',
                      style: theme.field(color: theme.textPrimary, size: 14),
                    ),
                    const SizedBox(width: 8),
                    // On a narrow screen the two wrap rather than overflow.
                    Expanded(
                      child: Wrap(
                        alignment: WrapAlignment.end,
                        children: [
                          AppButton(
                            currentLocale == SupportedLocale.en
                                ? SupportedLocale.zh.displayName
                                : SupportedLocale.en.displayName,
                            small: true,
                            kind: ButtonKind.quiet,
                            icon: Icons.translate_sharp,
                            onPressed: () {
                              final next = currentLocale == SupportedLocale.en
                                  ? SupportedLocale.zh
                                  : SupportedLocale.en;
                              ref.read(localeProvider.notifier).switchTo(next);
                              ref.read(settingsServiceProvider).saveLocale(next);
                            },
                          ),
                          // "Not now" only on the service step: the last
                          // step's main button already finishes onboarding.
                          if (_currentStep == 1)
                            ExcludeFocus(
                              child: AppButton(
                                context.t.onboardingNotNow,
                                small: true,
                                kind: ButtonKind.quiet,
                                onPressed: _skip,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: _StepBar(current: _currentStep),
              ),
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
            ],
          ),
        ),
      ),
    );
  }

  /// A step: its content scrolls in the middle, its buttons stay at the
  /// bottom.
  Widget _step({
    required List<Widget> children,
    required List<Widget> buttons,
  }) {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 32, 24, 16),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: children,
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: buttons,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildWelcomeStep(AppThemeTokens theme) {
    return _step(
      children: [
        Text(
          'ARKLORES',
          style: sairaStyle(
            size: 48,
            weight: 800,
            width: 125,
            color: theme.textPrimary,
            height: 1,
          ),
        ),
        const SizedBox(height: 16),
        Text(context.t.onboardingWelcomeTitle, style: theme.heading(26)),
        const SizedBox(height: 14),
        Text(
          context.t.onboardingWelcomeDesc,
          style: theme.text(16, color: theme.textSecondary, height: 1.7),
        ),
      ],
      buttons: [
        AppButton(
          context.t.onboardingGetStarted,
          kind: ButtonKind.go,
          expand: true,
          onPressed: () => _go(1),
        ),
      ],
    );
  }

  Widget _buildApiConfigStep(AppThemeTokens theme) {
    return _step(
      children: [
        Text(context.t.onboardingApiTitle, style: theme.heading(24)),
        const SizedBox(height: 8),
        Text(
          context.t.onboardingApiDesc,
          style: theme.text(15, color: theme.textSecondary, height: 1.6),
        ),
        const SizedBox(height: 24),
        TextField(
          controller: _baseUrlController,
          keyboardType: TextInputType.url,
          autocorrect: false,
          style: theme.field(color: theme.textPrimary, size: 15),
          decoration: InputDecoration(
            labelText: context.t.apiSettingsLabelBaseUrl,
            hintText: 'https://api.z.ai/api/paas/v4',
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _apiKeyController,
          obscureText: !_keyShown,
          // The keyboard must not learn, suggest or autocorrect a key.
          keyboardType: TextInputType.visiblePassword,
          autocorrect: false,
          enableSuggestions: false,
          onChanged: (_) {
            if (_keyError != null) setState(() => _keyError = null);
          },
          style: theme.field(color: theme.textPrimary, size: 15),
          decoration: InputDecoration(
            labelText: context.t.apiSettingsLabelApiKey,
            hintText: 'sk-...',
            errorText: _keyError,
            errorMaxLines: 3,
            suffixIcon: IconButton(
              tooltip: _keyShown
                  ? context.t.apiSettingsHideKey
                  : context.t.apiSettingsShowKey,
              icon: Icon(
                _keyShown ? Icons.visibility_off_sharp : Icons.visibility_sharp,
                size: 20,
              ),
              onPressed: () => setState(() => _keyShown = !_keyShown),
            ),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _chatModelController,
          autocorrect: false,
          style: theme.field(color: theme.textPrimary, size: 15),
          decoration: InputDecoration(
            labelText: context.t.apiSettingsLabelModel,
            hintText: 'glm-5.3-flash',
          ),
        ),
      ],
      buttons: [
        AppButton(
          context.t.onboardingSaveContinue,
          kind: ButtonKind.go,
          expand: true,
          onPressed: _saveAndContinue,
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            AppButton(
              MaterialLocalizations.of(context).backButtonTooltip,
              kind: ButtonKind.quiet,
              icon: Icons.arrow_back_sharp,
              small: true,
              onPressed: () => _go(0),
            ),
            const Spacer(),
            AppButton(
              context.t.onboardingConfigureLater,
              kind: ButtonKind.quiet,
              small: true,
              onPressed: _skip,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDoneStep(AppThemeTokens theme) {
    return _step(
      children: [
        Text(context.t.onboardingDoneTitle, style: theme.heading(28)),
        const SizedBox(height: 14),
        Text(
          context.t.onboardingDoneDesc,
          style: theme.text(16, color: theme.textSecondary, height: 1.7),
        ),
      ],
      buttons: [
        AppButton(
          context.t.onboardingStartExploring,
          kind: ButtonKind.go,
          expand: true,
          onPressed: _complete,
        ),
      ],
    );
  }
}

/// The steps as numbered cells: the current one in the accent and bold,
/// the done ones in ink, the ones to come in chip grey; a hairline under
/// them.
class _StepBar extends ConsumerWidget {
  const _StepBar({required this.current});

  final int current;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    return Semantics(
      label: '${current + 1} / 3',
      child: Row(
        children: [
          for (var i = 0; i < 3; i++) ...[
            if (i > 0) const SizedBox(width: 4),
            Expanded(
              child: AnimatedContainer(
                duration: Motion.of(context, Motion.wipe),
                curve: Motion.mech,
                height: 28,
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                color: i == current
                    ? theme.accentPrimary
                    : i < current
                        ? theme.textPrimary
                        : theme.surfaceElevated,
                child: Text(
                  (i + 1).toString().padLeft(2, '0'),
                  style: theme.field(
                    size: 13,
                    weight: i == current ? 700 : 500,
                    color: i == current
                        ? theme.onAccent
                        : i < current
                            ? theme.bgPrimary
                            : theme.textSecondary,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
