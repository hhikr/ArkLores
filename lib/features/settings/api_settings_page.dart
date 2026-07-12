import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/llm/llm_client.dart';
import '../../shared/providers/settings_provider.dart';
import '../../shared/providers/theme_provider.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/theme_aware_card.dart';

/// Dedicated sub-page for configuring Chat and Embedding API providers.
///
/// Chat and Embedding can use different providers (e.g. DeepSeek for
/// chat, OpenAI for embeddings). When Embedding fields are left empty,
/// the app falls back to the Chat config at runtime.
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

  bool _obscureChatKey = true;
  bool _obscureEmbedKey = true;
  bool _useChatForEmbed = false;
  bool _saved = false;

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
    final config = ref.read(apiConfigProvider);
    if (config.chatApiKey.isNotEmpty && _chatApiKeyCtrl.text.isEmpty) {
      _chatBaseUrlCtrl.text = config.chatBaseUrl;
      _chatApiKeyCtrl.text = config.chatApiKey;
      _chatModelCtrl.text = config.chatModel;
      _embedBaseUrlCtrl.text = config.embedBaseUrl;
      _embedApiKeyCtrl.text = config.embedApiKey;
      _embedModelCtrl.text = config.embedModel;
    }
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
    final config = LLMConfig(
      chatBaseUrl: _chatBaseUrlCtrl.text.trim(),
      chatApiKey: _chatApiKeyCtrl.text.trim(),
      chatModel: _chatModelCtrl.text.trim(),
      embedBaseUrl: _useChatForEmbed
          ? _chatBaseUrlCtrl.text.trim()
          : _embedBaseUrlCtrl.text.trim(),
      embedApiKey: _useChatForEmbed
          ? _chatApiKeyCtrl.text.trim()
          : _embedApiKeyCtrl.text.trim(),
      embedModel: _useChatForEmbed
          ? _chatModelCtrl.text.trim()
          : _embedModelCtrl.text.trim(),
    );

    await ref.read(apiConfigProvider.notifier).save(config);

    setState(() => _saved = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _saved = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider);
    ref.watch(apiConfigProvider);

    return Scaffold(
      backgroundColor: theme.bgPrimary,
      appBar: AppBar(
        backgroundColor: theme.bgSecondary,
        title: Text(
          'API Settings',
          style: theme.titleFont.copyWith(fontSize: 18),
        ),
        iconTheme: IconThemeData(color: theme.textPrimary),
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Header ────────────────────────────────────
          Center(
            child: Icon(
              Icons.api_rounded,
              size: 48,
              color: theme.accentPrimary.withValues(alpha: 0.4),
            ),
          ),
          const SizedBox(height: 24),

          // ── Chat API Section ──────────────────────────
          _buildSectionHeader(theme, Icons.chat_rounded, 'Chat API'),
          const SizedBox(height: 4),
          Text(
            'Used for AI conversations (Fact Check, Summary, Roleplay).',
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
                _inputLabel(theme, 'Base URL'),
                _inputField(
                  theme: theme,
                  controller: _chatBaseUrlCtrl,
                  hint: 'https://api.deepseek.com/v1',
                ),
                const SizedBox(height: 14),
                _inputLabel(theme, 'API Key'),
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
                _inputLabel(theme, 'Model'),
                _inputField(
                  theme: theme,
                  controller: _chatModelCtrl,
                  hint: 'deepseek-v4-flash',
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),

          // ── Embedding API Section ─────────────────────
          _buildSectionHeader(theme, Icons.auto_awesome_rounded, 'Embedding API'),
          const SizedBox(height: 4),
          Text(
            'Used for knowledge base indexing (Wiki, books). '
            'Can use a different provider from Chat.',
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
                // ── Use Chat config toggle ──────────────
                Row(
                  children: [
                    SizedBox(
                      height: 24,
                      width: 24,
                      child: Checkbox(
                        value: _useChatForEmbed,
                        onChanged: (v) =>
                            setState(() => _useChatForEmbed = v ?? false),
                        activeColor: theme.accentPrimary,
                        checkColor: theme.bgPrimary,
                        side: BorderSide(color: theme.divider),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Use same provider as Chat',
                        style: theme.bodyFont.copyWith(
                          color: theme.textPrimary,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                if (!_useChatForEmbed) ...[
                  _inputLabel(theme, 'Base URL'),
                  _inputField(
                    theme: theme,
                    controller: _embedBaseUrlCtrl,
                    hint: 'https://api.openai.com/v1',
                  ),
                  const SizedBox(height: 14),
                  _inputLabel(theme, 'API Key'),
                  _inputField(
                    theme: theme,
                    controller: _embedApiKeyCtrl,
                    hint: 'sk-...',
                    obscure: _obscureEmbedKey,
                    suffix: IconButton(
                      icon: Icon(
                        _obscureEmbedKey
                            ? Icons.visibility_off_rounded
                            : Icons.visibility_rounded,
                        color: theme.textSecondary,
                        size: 20,
                      ),
                      onPressed: () =>
                          setState(() => _obscureEmbedKey = !_obscureEmbedKey),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _inputLabel(theme, 'Model'),
                  _inputField(
                    theme: theme,
                    controller: _embedModelCtrl,
                    hint: 'text-embedding-3-small',
                  ),
                ] else ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.warning.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: theme.warning.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline,
                            color: theme.warning, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Embedding will use the Chat API config above. '
                            'Note: DeepSeek does not support embeddings — '
                            'if you use DeepSeek for chat, uncheck this '
                            'to configure a separate embedding provider.',
                            style: theme.bodyFont.copyWith(
                              color: theme.textSecondary,
                              fontSize: 12,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 28),

          // ── Save Button ───────────────────────────────
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _saveConfig,
              icon: Icon(
                _saved ? Icons.check_rounded : Icons.save_rounded,
                size: 20,
              ),
              label: Text(
                _saved ? '✓ Saved' : 'Save Configuration',
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

  Widget _buildSectionHeader(
      AppThemeTokens theme, IconData icon, String title) {
    return Row(
      children: [
        Icon(icon, color: theme.accentPrimary, size: 22),
        const SizedBox(width: 8),
        Text(
          title,
          style: theme.titleFont.copyWith(fontSize: 18),
        ),
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
