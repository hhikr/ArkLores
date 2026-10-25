import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/background/background_work.dart';
import '../../core/gamedata/game.dart';
import '../../core/llm/embedding_client.dart';
import '../../core/llm/llm_client.dart';
import '../../shared/l10n/l10n.dart';
import '../../shared/providers/settings_provider.dart';
import '../../shared/providers/theme_provider.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/theme/motion.dart';
import '../../shared/widgets/ef_widgets.dart';
import '../library/reading_text.dart' show readingFontSample;
import 'background_access.dart';
import 'game_asset_card.dart';
import 'wiki_sources_settings_page.dart';

/// The steps of the onboarding, in order. [background] only where the
/// system has something to ask (Android).
enum OnboardingStep {
  welcome,
  appearance,
  profile,
  chat,
  embedding,
  knowledgeBase,
  wiki,
  background,
  done,
}

/// Onboarding, shown on first launch and from Settings: one step per part of
/// the app's setup — what the app is, appearance, how the stories address
/// the reader, the chat and vector services, the knowledge bases, the Wiki
/// sites, running in the background, ready.
///
/// Every field starts with what is saved on the device (a service filled in
/// before, a knowledge base already downloaded shows so); a step whose
/// fields are unchanged just goes on. A numbered step bar on top says where
/// the reader is; the step's main button is at the bottom, within reach of
/// the thumb; Back (the system's or the step's) returns to the step before.
class OnboardingPage extends ConsumerStatefulWidget {
  const OnboardingPage({super.key, required this.onComplete});
  final VoidCallback onComplete;

  @override
  ConsumerState<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends ConsumerState<OnboardingPage> {
  final PageController _pageController = PageController();
  int _currentStep = 0;

  /// Whether the system has background access to ask for (Android).
  bool _hasBackgroundStep = false;

  late final TextEditingController _nickname;

  // The chat service, as saved.
  late final TextEditingController _chatUrl;
  late final TextEditingController _chatKey;
  late final TextEditingController _chatModel;
  String? _chatKeyError;

  // The vector service, as saved.
  late final TextEditingController _embedUrl;
  late final TextEditingController _embedKey;
  late final TextEditingController _embedModel;
  String? _embedKeyError;

  bool _saving = false;

  List<OnboardingStep> get _steps => [
        for (final step in OnboardingStep.values)
          if (step != OnboardingStep.background || _hasBackgroundStep) step,
      ];

  @override
  void initState() {
    super.initState();
    _nickname = TextEditingController(text: ref.read(nicknameProvider));
    final chat = ref.read(apiConfigProvider);
    _chatUrl = TextEditingController(text: chat.chatBaseUrl);
    _chatKey = TextEditingController(text: chat.chatApiKey);
    _chatModel = TextEditingController(text: chat.chatModel);
    final embedding = ref.read(embeddingConfigProvider);
    _embedUrl = TextEditingController(text: embedding.baseUrl);
    _embedKey = TextEditingController(text: embedding.apiKey);
    _embedModel = TextEditingController(text: embedding.model);
    for (final c in [_chatUrl, _chatKey, _chatModel, _embedUrl, _embedKey, _embedModel]) {
      // The main button says whether there is something to save.
      c.addListener(_refresh);
    }
    ref.read(backgroundWorkProvider).access().then((access) {
      if (access != null && mounted) {
        setState(() => _hasBackgroundStep = true);
      }
    });
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _pageController.dispose();
    for (final c in [
      _nickname,
      _chatUrl,
      _chatKey,
      _chatModel,
      _embedUrl,
      _embedKey,
      _embedModel,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _finish() async {
    await ref.read(settingsServiceProvider).markOnboardingDone();
    widget.onComplete();
  }

  Future<void> _go(int step) => _pageController.animateToPage(
        step,
        duration: Motion.of(context, Motion.shutter),
        curve: Motion.mech,
      );

  Future<void> _next() => _go(_currentStep + 1);

  LLMConfig get _chatConfig => LLMConfig(
        chatBaseUrl: _chatUrl.text.trim(),
        chatApiKey: _chatKey.text.trim(),
        chatModel: _chatModel.text.trim(),
      );

  bool get _chatChanged {
    final saved = ref.read(apiConfigProvider);
    final now = _chatConfig;
    return now.chatBaseUrl != saved.chatBaseUrl ||
        now.chatApiKey != saved.chatApiKey ||
        now.chatModel != saved.chatModel;
  }

  EmbeddingConfig get _embedConfig => ref.read(embeddingConfigProvider).copyWith(
        baseUrl: _embedUrl.text.trim(),
        apiKey: _embedKey.text.trim(),
        model: _embedModel.text.trim(),
      );

  bool get _embedChanged {
    final saved = ref.read(embeddingConfigProvider);
    final now = _embedConfig;
    return now.baseUrl != saved.baseUrl ||
        now.apiKey != saved.apiKey ||
        now.model != saved.model;
  }

  Future<void> _saveChat() async {
    final error = LLMConfig.apiKeyFormatError(_chatKey.text, label: 'Chat API Key');
    setState(() => _chatKeyError = error);
    if (error != null) return;
    if (_chatChanged) {
      setState(() => _saving = true);
      await ref.read(apiConfigProvider.notifier).save(_chatConfig);
      if (!mounted) return;
      setState(() => _saving = false);
    }
    await _next();
  }

  Future<void> _saveEmbedding() async {
    final error =
        LLMConfig.apiKeyFormatError(_embedKey.text, label: 'Embedding API Key');
    setState(() => _embedKeyError = error);
    if (error != null) return;
    if (_embedChanged) {
      setState(() => _saving = true);
      await ref.read(embeddingConfigProvider.notifier).save(_embedConfig);
      if (!mounted) return;
      setState(() => _saving = false);
    }
    await _next();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider);
    final currentLocale = ref.watch(localeProvider);
    final steps = _steps;
    final last = _currentStep == steps.length - 1;

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
                      '${(_currentStep + 1).toString().padLeft(2, '0')} / '
                      '${steps.length.toString().padLeft(2, '0')}',
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
                          // The last step's main button finishes already.
                          if (!last)
                            ExcludeFocus(
                              child: AppButton(
                                context.t.onboardingSkipGuide,
                                key: const ValueKey('onboarding-skip'),
                                small: true,
                                kind: ButtonKind.quiet,
                                onPressed: _finish,
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
                child: _StepBar(current: _currentStep, count: steps.length),
              ),
              Expanded(
                child: PageView(
                  controller: _pageController,
                  onPageChanged: (i) {
                    FocusScope.of(context).unfocus();
                    setState(() => _currentStep = i);
                  },
                  // Steps advance only through their buttons, never by swiping.
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    for (final step in steps)
                      KeyedSubtree(
                        key: ValueKey('onboarding-${step.name}'),
                        child: _buildStep(step, theme),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStep(OnboardingStep step, AppThemeTokens theme) =>
      switch (step) {
        OnboardingStep.welcome => _welcome(theme),
        OnboardingStep.appearance => _appearance(theme),
        OnboardingStep.profile => _profile(theme),
        OnboardingStep.chat => _chat(theme),
        OnboardingStep.embedding => _embedding(theme),
        OnboardingStep.knowledgeBase => _knowledgeBase(theme),
        OnboardingStep.wiki => _wiki(theme),
        OnboardingStep.background => _background(theme),
        OnboardingStep.done => _done(theme),
      };

  /// A step: its content scrolls in the middle, its buttons stay at the
  /// bottom: the main one, and under it Back and an optional "later".
  Widget _step({
    required String title,
    required String code,
    String? description,
    required List<Widget> children,
    required Widget main,
    Widget? later,
  }) {
    final theme = ref.watch(themeProvider);
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SectionTitle(
                      title: title,
                      code: code,
                      size: 24,
                      padding: const EdgeInsets.only(bottom: 8),
                    ),
                    if (description != null) ...[
                      Text(
                        description,
                        style: theme.text(15, color: theme.textSecondary, height: 1.6),
                      ),
                      const SizedBox(height: 20),
                    ],
                    ...children,
                  ],
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
              children: [
                main,
                if (_currentStep > 0 || later != null) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (_currentStep > 0)
                        AppButton(
                          MaterialLocalizations.of(context).backButtonTooltip,
                          kind: ButtonKind.quiet,
                          icon: Icons.arrow_back_sharp,
                          small: true,
                          onPressed: () => _go(_currentStep - 1),
                        ),
                      const Spacer(),
                      if (later != null) later,
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _nextButton({String? label, VoidCallback? onPressed}) => AppButton(
        label ?? context.t.onboardingNext,
        key: const ValueKey('onboarding-next'),
        kind: ButtonKind.go,
        expand: true,
        busy: _saving,
        onPressed: onPressed ?? _next,
      );

  /// "Configure later": on to the next step without saving.
  Widget _laterButton() => AppButton(
        context.t.onboardingConfigureLater,
        key: const ValueKey('onboarding-later'),
        kind: ButtonKind.quiet,
        small: true,
        onPressed: _next,
      );

  Widget _welcome(AppThemeTokens theme) {
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
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: _nextButton(label: context.t.onboardingGetStarted),
          ),
        ),
      ],
    );
  }

  Widget _appearance(AppThemeTokens theme) {
    final themes = ref.read(themeProvider.notifier);
    final service = ref.read(settingsServiceProvider);
    Widget label(String text) => Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 8),
          child: Text(text, style: theme.heading(16)),
        );
    return _step(
      title: context.t.onboardingAppearanceTitle,
      code: 'appearance',
      description: context.t.onboardingAppearanceDesc,
      children: [
        label(context.t.settingsTheme),
        SegmentedChoice<AppTheme>(
          key: const ValueKey('onboarding-theme'),
          value: themes.currentTheme,
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
        const SizedBox(height: 16),
        label(context.t.settingsReadingFont),
        SegmentedChoice<ReadingFont>(
          key: const ValueKey('onboarding-reading-font'),
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
      ],
      main: _nextButton(),
    );
  }

  Widget _profile(AppThemeTokens theme) {
    return _step(
      title: context.t.settingsProfile,
      code: 'name',
      description: context.t.onboardingProfileDesc,
      children: [
        TextField(
          key: const ValueKey('onboarding-nickname'),
          controller: _nickname,
          // Saved as it is typed, as on the profile page.
          onChanged: (value) {
            ref.read(nicknameProvider.notifier).state = value.trim();
            ref.read(settingsServiceProvider).saveNickname(value);
          },
          textInputAction: TextInputAction.done,
          style: theme.text(16),
          decoration: InputDecoration(
            labelText: context.t.profileNicknameLabel,
            hintText: context.t.profileNicknameDefault,
            helperText: context.t.profileNicknameHelp,
            helperMaxLines: 4,
          ),
        ),
      ],
      main: _nextButton(),
    );
  }

  Widget _chat(AppThemeTokens theme) {
    return _step(
      title: context.t.onboardingApiTitle,
      code: 'chat',
      description: context.t.onboardingApiDesc,
      children: [
        _field(_chatUrl, context.t.apiSettingsLabelBaseUrl, url: true),
        _SecretField(
          key: const ValueKey('onboarding-chat-key'),
          controller: _chatKey,
          label: context.t.apiSettingsLabelApiKey,
          error: _chatKeyError,
          onChanged: () {
            if (_chatKeyError != null) setState(() => _chatKeyError = null);
          },
        ),
        _field(_chatModel, context.t.apiSettingsLabelModel),
      ],
      main: _nextButton(
        label: _chatChanged ? context.t.onboardingSaveContinue : null,
        onPressed: _saveChat,
      ),
      later: _chatChanged || !_chatConfig.isValid ? _laterButton() : null,
    );
  }

  Widget _embedding(AppThemeTokens theme) {
    return _step(
      title: context.t.apiSettingsEmbeddingSection,
      code: 'embedding',
      description: context.t.onboardingEmbeddingDesc,
      children: [
        _field(_embedUrl, context.t.apiSettingsLabelBaseUrl,
            hint: defaultEmbeddingConfig.baseUrl, url: true,),
        _SecretField(
          key: const ValueKey('onboarding-embedding-key'),
          controller: _embedKey,
          label: context.t.apiSettingsLabelApiKey,
          error: _embedKeyError,
          onChanged: () {
            if (_embedKeyError != null) setState(() => _embedKeyError = null);
          },
        ),
        _field(_embedModel, context.t.apiSettingsLabelModel,
            hint: defaultEmbeddingConfig.model,),
      ],
      main: _nextButton(
        label: _embedChanged ? context.t.onboardingSaveContinue : null,
        onPressed: _saveEmbedding,
      ),
      later: _embedChanged || !_embedConfig.isValid ? _laterButton() : null,
    );
  }

  Widget _knowledgeBase(AppThemeTokens theme) {
    return _step(
      title: context.t.onboardingKbTitle,
      code: 'knowledge',
      description: context.t.onboardingKbDesc,
      children: [
        for (final (i, game) in Game.values.indexed) ...[
          if (i > 0) const SizedBox(height: 16),
          GameAssetCard(
            game: game,
            title: game == Game.endfield
                ? context.t.kbEndfieldTitle
                : context.t.kbArknightsTitle,
          ),
        ],
      ],
      main: _nextButton(),
    );
  }

  Widget _wiki(AppThemeTokens theme) {
    return _step(
      title: context.t.onboardingWikiTitle,
      code: 'wiki',
      description: context.t.onboardingWikiDesc,
      children: const [WikiSourcesList()],
      main: _nextButton(),
    );
  }

  Widget _background(AppThemeTokens theme) {
    return _step(
      title: context.t.onboardingBackgroundTitle,
      code: 'background',
      description: context.t.backgroundAccessBody,
      children: const [BackgroundAccessRows()],
      main: _nextButton(),
    );
  }

  Widget _done(AppThemeTokens theme) {
    return _step(
      title: context.t.onboardingDoneTitle,
      code: 'ready',
      description: context.t.onboardingDoneDesc,
      children: const [],
      main: _nextButton(
        label: context.t.onboardingStartExploring,
        onPressed: _finish,
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    String? hint,
    bool url = false,
  }) {
    final theme = ref.read(themeProvider);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextField(
        controller: controller,
        keyboardType: url ? TextInputType.url : TextInputType.text,
        autocorrect: false,
        style: theme.field(color: theme.textPrimary, size: 15),
        decoration: InputDecoration(labelText: label, hintText: hint),
      ),
    );
  }
}

/// A key field: hidden by default, an eye to show it; its format error is
/// said right under it.
class _SecretField extends ConsumerStatefulWidget {
  const _SecretField({
    super.key,
    required this.controller,
    required this.label,
    required this.onChanged,
    this.error,
  });

  final TextEditingController controller;
  final String label;
  final String? error;
  final VoidCallback onChanged;

  @override
  ConsumerState<_SecretField> createState() => _SecretFieldState();
}

class _SecretFieldState extends ConsumerState<_SecretField> {
  bool _shown = false;

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextField(
        controller: widget.controller,
        obscureText: !_shown,
        // The keyboard must not learn, suggest or autocorrect a key.
        keyboardType: TextInputType.visiblePassword,
        autocorrect: false,
        enableSuggestions: false,
        onChanged: (_) => widget.onChanged(),
        style: theme.field(color: theme.textPrimary, size: 15),
        decoration: InputDecoration(
          labelText: widget.label,
          hintText: 'sk-...',
          errorText: widget.error,
          errorMaxLines: 3,
          suffixIcon: IconButton(
            tooltip: _shown
                ? context.t.apiSettingsHideKey
                : context.t.apiSettingsShowKey,
            icon: Icon(
              _shown ? Icons.visibility_off_sharp : Icons.visibility_sharp,
              size: 20,
            ),
            onPressed: () => setState(() => _shown = !_shown),
          ),
        ),
      ),
    );
  }
}

/// The steps as numbered cells: the current one in the accent and bold,
/// the done ones in ink, the ones to come in chip grey.
class _StepBar extends ConsumerWidget {
  const _StepBar({required this.current, required this.count});

  final int current;
  final int count;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    return Semantics(
      label: '${current + 1} / $count',
      child: Row(
        children: [
          for (var i = 0; i < count; i++) ...[
            if (i > 0) const SizedBox(width: 3),
            Expanded(
              child: AnimatedContainer(
                duration: Motion.of(context, Motion.wipe),
                curve: Motion.mech,
                height: 28,
                alignment: Alignment.center,
                color: i == current
                    ? theme.accentPrimary
                    : i < current
                        ? theme.textPrimary
                        : theme.surfaceElevated,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    (i + 1).toString().padLeft(2, '0'),
                    style: theme.field(
                      size: 12,
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
            ),
          ],
        ],
      ),
    );
  }
}
