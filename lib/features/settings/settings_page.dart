import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/llm/llm_client.dart';
import '../../shared/providers/settings_provider.dart';
import '../../shared/providers/theme_provider.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/theme_aware_card.dart';

/// Settings tab — hosts API Key configuration, theme switcher, and
/// knowledge base management.
class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  late TextEditingController _baseUrlController;
  late TextEditingController _apiKeyController;
  late TextEditingController _chatModelController;
  late TextEditingController _embeddingModelController;
  bool _obscureApiKey = true;
  bool _saved = false;
  @override
  void initState() {
    super.initState();
    _baseUrlController = TextEditingController();
    _apiKeyController = TextEditingController();
    _chatModelController = TextEditingController();
    _embeddingModelController = TextEditingController();
    // Schedule a post-frame callback to sync controllers after the
    // first build, by which time apiConfigProvider may have loaded.
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncControllers());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Sync again when apiConfigProvider state changes (e.g. async load completes).
    _syncControllers();
  }

  void _syncControllers() {
    final config = ref.read(apiConfigProvider);
    if (config.apiKey.isNotEmpty && _apiKeyController.text.isEmpty) {
      _baseUrlController.text = config.baseUrl;
      _apiKeyController.text = config.apiKey;
      _chatModelController.text = config.chatModel;
      _embeddingModelController.text = config.embeddingModel;
    }
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    _apiKeyController.dispose();
    _chatModelController.dispose();
    _embeddingModelController.dispose();
    super.dispose();
  }

  Future<void> _saveConfig() async {
    final config = LLMConfig(
      baseUrl: _baseUrlController.text.trim(),
      apiKey: _apiKeyController.text.trim(),
      chatModel: _chatModelController.text.trim(),
      embeddingModel: _embeddingModelController.text.trim(),
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
    final notifier = ref.read(themeProvider.notifier);
    // Watch config so the UI re-renders when async load completes.
    ref.watch(apiConfigProvider);

    return Scaffold(
      backgroundColor: theme.bgPrimary,
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        children: [
          // ── Header ───────────────────────────────────────────
          const SizedBox(height: 32),
          Center(
            child: Icon(
              Icons.settings_rounded,
              size: 64,
              color: theme.accentPrimary.withValues(alpha: 0.4),
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: Text(
              'Settings',
              style: theme.titleFont.copyWith(fontSize: 24),
            ),
          ),
          const SizedBox(height: 32),

          // ── Theme Switcher ────────────────────────────────────
          ThemeAwareCard(
            child: Row(
              children: [
                Icon(Icons.palette_rounded, color: theme.accentPrimary),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Theme',
                        style: theme.titleFont.copyWith(fontSize: 16),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        notifier.currentTheme == AppTheme.ark
                            ? 'Tactical Archive'
                            : 'Holographic Projection',
                        style: theme.bodyFont.copyWith(
                          color: theme.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: notifier.currentTheme == AppTheme.ark,
                  onChanged: (_) => notifier.toggle(),
                  activeColor: theme.accentPrimary,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── API Configuration ──────────────────────────────────
          Text(
            'API Configuration',
            style: theme.titleFont.copyWith(fontSize: 18),
          ),
          const SizedBox(height: 12),
          ThemeAwareCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildInputLabel('Base URL', theme),
                _buildInputField(
                  controller: _baseUrlController,
                  hintText: 'https://api.deepseek.com/v1',
                  theme: theme,
                ),
                const SizedBox(height: 16),
                _buildInputLabel('API Key', theme),
                _buildInputField(
                  controller: _apiKeyController,
                  hintText: 'sk-...',
                  theme: theme,
                  obscureText: _obscureApiKey,
                  suffixIcon: IconButton(
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
                const SizedBox(height: 16),
                _buildInputLabel('Chat Model', theme),
                _buildInputField(
                  controller: _chatModelController,
                  hintText: 'deepseek-v4-flash',
                  theme: theme,
                ),
                const SizedBox(height: 16),
                _buildInputLabel('Embedding Model', theme),
                _buildInputField(
                  controller: _embeddingModelController,
                  hintText: 'deepseek-embed',
                  theme: theme,
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: theme.warning.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: theme.warning.withValues(alpha: 0.3),
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
                          'If your provider does not support embedding (e.g. DeepSeek), '
                          'you can use a different provider for embeddings by changing '
                          'the Base URL to a compatible one like '
                          'https://api.openai.com/v1.',
                          style: theme.bodyFont.copyWith(
                            color: theme.textSecondary,
                            fontSize: 11,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _saveConfig,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.accentPrimary,
                      foregroundColor: theme.bgPrimary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: theme.cardRadius,
                      ),
                    ),
                    child: Text(
                      _saved ? '✓ Saved' : 'Save Configuration',
                      style: theme.titleFont.copyWith(fontSize: 15),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // ── Knowledge Base ──────────────────────────────────
          Text(
            'Knowledge Base',
            style: theme.titleFont.copyWith(fontSize: 18),
          ),
          const SizedBox(height: 12),
          ThemeAwareCard(
            onTap: () {
              Navigator.pushNamed(context, '/knowledge-base');
            },
            child: Row(
              children: [
                Icon(Icons.storage_rounded, color: theme.accentPrimary),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Knowledge Base Management',
                        style: theme.titleFont.copyWith(fontSize: 16),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Manage Wiki index, view stats, update knowledge base',
                        style: theme.bodyFont.copyWith(
                          color: theme.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: theme.textSecondary,
                ),
              ],
            ),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildInputLabel(String label, AppThemeTokens theme) {
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

  Widget _buildInputField({
    required TextEditingController controller,
    required String hintText,
    required AppThemeTokens theme,
    bool obscureText = false,
    Widget? suffixIcon,
  }) {
    return Container(
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
          hintText: hintText,
          hintStyle: TextStyle(color: theme.textSecondary.withValues(alpha: 0.5)),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          suffixIcon: suffixIcon,
        ),
      ),
    );
  }
}
