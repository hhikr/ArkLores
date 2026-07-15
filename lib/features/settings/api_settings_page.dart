import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/llm/llm_client.dart';
import '../../shared/l10n/l10n.dart';
import '../../shared/providers/settings_provider.dart';
import '../../shared/providers/theme_provider.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/theme_aware_card.dart';

/// Dedicated sub-page for configuring the Chat API provider.
class ApiSettingsPage extends ConsumerStatefulWidget {
  const ApiSettingsPage({super.key});

  @override
  ConsumerState<ApiSettingsPage> createState() => _ApiSettingsPageState();
}

class _ApiSettingsPageState extends ConsumerState<ApiSettingsPage> {
  late TextEditingController _chatBaseUrlCtrl;
  late TextEditingController _chatApiKeyCtrl;
  late TextEditingController _chatModelCtrl;

  bool _obscureChatKey = true;
  bool _saved = false;
  bool _synced = false;

  @override
  void initState() {
    super.initState();
    _chatBaseUrlCtrl = TextEditingController();
    _chatApiKeyCtrl = TextEditingController();
    _chatModelCtrl = TextEditingController();
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
    _synced = true;
  }

  @override
  void dispose() {
    _chatBaseUrlCtrl.dispose();
    _chatApiKeyCtrl.dispose();
    _chatModelCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveConfig() async {
    final chatApiKey = _chatApiKeyCtrl.text.trim();
    final chatKeyError =
        LLMConfig.apiKeyFormatError(chatApiKey, label: 'Chat API Key');
    if (chatKeyError != null) {
      _showConfigError(chatKeyError);
      return;
    }

    final config = LLMConfig(
      chatBaseUrl: _chatBaseUrlCtrl.text.trim(),
      chatApiKey: chatApiKey,
      chatModel: _chatModelCtrl.text.trim(),
    );

    await ref.read(apiConfigProvider.notifier).save(config);

    setState(() => _saved = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _saved = false);
    });
  }

  void _showConfigError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider);
    ref.watch(apiConfigProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: theme.bgSecondary,
        title: Text(
          context.t.apiSettingsTitle,
          style: theme.titleFont.copyWith(fontSize: 18),
        ),
        iconTheme: IconThemeData(color: theme.textPrimary),
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: Icon(
              Icons.api_rounded,
              size: 48,
              color: theme.accentPrimary.withValues(alpha: 0.4),
            ),
          ),
          const SizedBox(height: 24),
          _sectionHeader(
            theme,
            Icons.chat_rounded,
            context.t.apiSettingsChatSection,
          ),
          const SizedBox(height: 4),
          Text(
            context.t.apiSettingsChatDesc,
            style: theme.bodyFont.copyWith(
              color: theme.textSecondary,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 12),
          ThemeAwareCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _inputLabel(theme, context.t.apiSettingsLabelBaseUrl),
                _inputField(
                  theme: theme,
                  controller: _chatBaseUrlCtrl,
                  hint: 'https://api.deepseek.com/v1',
                ),
                const SizedBox(height: 14),
                _inputLabel(theme, context.t.apiSettingsLabelApiKey),
                _inputField(
                  theme: theme,
                  controller: _chatApiKeyCtrl,
                  hint: 'sk-...',
                  obscure: _obscureChatKey,
                  suffix: IconButton(
                    icon: Icon(
                      _obscureChatKey
                          ? Icons.visibility_off_rounded
                          : Icons.visibility_rounded,
                      color: theme.textSecondary,
                      size: 20,
                    ),
                    onPressed: () =>
                        setState(() => _obscureChatKey = !_obscureChatKey),
                  ),
                ),
                const SizedBox(height: 14),
                _inputLabel(theme, context.t.apiSettingsLabelModel),
                _inputField(
                  theme: theme,
                  controller: _chatModelCtrl,
                  hint: 'deepseek-v4-flash',
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _saveConfig,
              icon: Icon(
                _saved ? Icons.check_rounded : Icons.save_rounded,
                size: 20,
              ),
              label: Text(
                _saved ? context.t.apiSettingsSaved : context.t.apiSettingsSave,
                style: theme.titleFont.copyWith(fontSize: 15),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.accentPrimary,
                foregroundColor: theme.bgPrimary,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _sectionHeader(AppThemeTokens theme, IconData icon, String title) {
    return Row(
      children: [
        Icon(icon, color: theme.accentPrimary, size: 22),
        const SizedBox(width: 8),
        Text(title, style: theme.titleFont.copyWith(fontSize: 18)),
      ],
    );
  }

  Widget _inputLabel(AppThemeTokens theme, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        label,
        style: theme.bodyFont.copyWith(
          color: theme.textSecondary,
          fontSize: 13,
        ),
      ),
    );
  }

  Widget _inputField({
    required AppThemeTokens theme,
    required TextEditingController controller,
    required String hint,
    bool obscure = false,
    Widget? suffix,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: theme.bgSecondary,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.divider, width: 1),
      ),
      child: TextField(
        controller: controller,
        obscureText: obscure,
        style: theme.bodyFont.copyWith(
          color: theme.textPrimary,
          fontSize: 14,
        ),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle:
              TextStyle(color: theme.textSecondary.withValues(alpha: 0.5)),
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          suffixIcon: suffix,
        ),
      ),
    );
  }
}
