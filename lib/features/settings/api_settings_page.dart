import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/llm/embedding_client.dart';
import '../../core/llm/llm_client.dart';
import '../../shared/l10n/l10n.dart';
import '../../shared/providers/settings_provider.dart';
import '../../shared/providers/theme_provider.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/ef_widgets.dart';
import '../../shared/widgets/page_frame.dart';

/// Dedicated sub-page for configuring the chat and embedding services: two
/// sections of labelled fields; a key's format error is said under that
/// key; one save button at the bottom.
class ApiSettingsPage extends ConsumerStatefulWidget {
  const ApiSettingsPage({super.key});

  @override
  ConsumerState<ApiSettingsPage> createState() => _ApiSettingsPageState();
}

class _ApiSettingsPageState extends ConsumerState<ApiSettingsPage> {
  late TextEditingController _chatBaseUrlCtrl;
  late TextEditingController _chatApiKeyCtrl;
  late TextEditingController _chatModelCtrl;
  late TextEditingController _embedBaseUrlCtrl;
  late TextEditingController _embedApiKeyCtrl;
  late TextEditingController _embedModelCtrl;

  bool _saving = false;
  bool _synced = false;
  String? _chatKeyError;
  String? _embedKeyError;

  @override
  void initState() {
    super.initState();
    _chatBaseUrlCtrl = TextEditingController();
    _chatApiKeyCtrl = TextEditingController();
    _chatModelCtrl = TextEditingController();
    _embedBaseUrlCtrl = TextEditingController();
    _embedApiKeyCtrl = TextEditingController();
    _embedModelCtrl = TextEditingController();
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncControllers());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncControllers();
  }

  void _syncControllers() {
    if (_synced) return;
    final config = ref.read(apiConfigProvider);
    _chatBaseUrlCtrl.text = config.chatBaseUrl;
    _chatApiKeyCtrl.text = config.chatApiKey;
    _chatModelCtrl.text = config.chatModel;
    final embedding = ref.read(embeddingConfigProvider);
    _embedBaseUrlCtrl.text = embedding.baseUrl;
    _embedApiKeyCtrl.text = embedding.apiKey;
    _embedModelCtrl.text = embedding.model;
    _synced = true;
  }

  @override
  void dispose() {
    _chatBaseUrlCtrl.dispose();
    _chatApiKeyCtrl.dispose();
    _chatModelCtrl.dispose();
    _embedBaseUrlCtrl.dispose();
    _embedApiKeyCtrl.dispose();
    _embedModelCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveConfig() async {
    final chatApiKey = _chatApiKeyCtrl.text.trim();
    final embedApiKey = _embedApiKeyCtrl.text.trim();
    final chatKeyError =
        LLMConfig.apiKeyFormatError(chatApiKey, label: 'Chat API Key');
    final embedKeyError =
        LLMConfig.apiKeyFormatError(embedApiKey, label: 'Embedding API Key');
    setState(() {
      _chatKeyError = chatKeyError;
      _embedKeyError = embedKeyError;
    });
    if (chatKeyError != null || embedKeyError != null) return;

    setState(() => _saving = true);
    final config = LLMConfig(
      chatBaseUrl: _chatBaseUrlCtrl.text.trim(),
      chatApiKey: chatApiKey,
      chatModel: _chatModelCtrl.text.trim(),
    );
    await ref.read(apiConfigProvider.notifier).save(config);
    await ref.read(embeddingConfigProvider.notifier).save(
          ref.read(embeddingConfigProvider).copyWith(
                baseUrl: _embedBaseUrlCtrl.text.trim(),
                apiKey: embedApiKey,
                model: _embedModelCtrl.text.trim(),
              ),
        );

    if (!mounted) return;
    setState(() => _saving = false);
    showToast(context, context.t.apiSettingsSaved);
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider);
    ref.watch(apiConfigProvider);

    return PageScaffold(
      title: context.t.apiSettingsTitle,
      scrollUnder: true,
      body: ListView(
        padding: pagePadding(context, const EdgeInsets.fromLTRB(16, 4, 16, 40)),
        children: [
          SectionTitle(title: context.t.apiSettingsChatSection, code: 'chat'),
          Text(
            context.t.apiSettingsChatDesc,
            style: theme.text(14, color: theme.textSecondary),
          ),
          const SizedBox(height: 16),
          _field(
            controller: _chatBaseUrlCtrl,
            label: context.t.apiSettingsLabelBaseUrl,
            hint: 'https://api.z.ai/api/paas/v4',
            url: true,
          ),
          _SecretField(
            controller: _chatApiKeyCtrl,
            label: context.t.apiSettingsLabelApiKey,
            error: _chatKeyError,
            onChanged: () {
              if (_chatKeyError != null) setState(() => _chatKeyError = null);
            },
          ),
          _field(
            controller: _chatModelCtrl,
            label: context.t.apiSettingsLabelModel,
            hint: 'glm-5.3-flash',
          ),
          const SizedBox(height: 8),
          Divider(height: 1, color: theme.divider),
          SectionTitle(
            title: context.t.apiSettingsEmbeddingSection,
            code: 'embedding',
          ),
          Text(
            context.t.apiSettingsEmbeddingDesc,
            style: theme.text(14, color: theme.textSecondary),
          ),
          const SizedBox(height: 16),
          _field(
            controller: _embedBaseUrlCtrl,
            label: context.t.apiSettingsLabelBaseUrl,
            hint: defaultEmbeddingConfig.baseUrl,
            url: true,
          ),
          _SecretField(
            controller: _embedApiKeyCtrl,
            label: context.t.apiSettingsLabelApiKey,
            error: _embedKeyError,
            onChanged: () {
              if (_embedKeyError != null) setState(() => _embedKeyError = null);
            },
          ),
          _field(
            controller: _embedModelCtrl,
            label: context.t.apiSettingsLabelModel,
            hint: defaultEmbeddingConfig.model,
          ),
          const SizedBox(height: 16),
          AppButton(
            context.t.apiSettingsSave,
            key: const ValueKey('api-settings-save'),
            kind: ButtonKind.go,
            icon: Icons.save_sharp,
            expand: true,
            busy: _saving,
            onPressed: _saveConfig,
          ),
        ],
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required String hint,
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
