import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/llm/embedding_profile.dart';
import '../../core/llm/llm_client.dart';
import '../../core/rag/local_embedding/builtin_embedding_model.dart';
import '../../core/rag/vector_store_provider.dart';
import '../../shared/l10n/l10n.dart';
import '../../shared/providers/settings_provider.dart';
import '../../shared/providers/theme_provider.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/theme_aware_card.dart';

/// Dedicated sub-page for configuring Chat and Embedding API providers.
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
  EmbeddingBackend _embeddingBackend = EmbeddingBackend.api;
  bool _saved = false;
  bool _synced = false;

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
    // Sync again when the provider state changes (e.g. load completes
    // after the first didChangeDependencies call).
    _syncControllers();
  }

  void _syncControllers() {
    if (_synced) return;
    final config = ref.read(apiConfigProvider);
    final activeProfile = ref.read(embeddingSettingsProvider).activeProfile;
    _chatBaseUrlCtrl.text = config.chatBaseUrl;
    _chatApiKeyCtrl.text = config.chatApiKey;
    _chatModelCtrl.text = config.chatModel;
    if (activeProfile != null) {
      _applyProfileToControllers(activeProfile);
    } else {
      _embedBaseUrlCtrl.text = config.embedBaseUrl;
      _embedApiKeyCtrl.text = config.embedApiKey;
      _embedModelCtrl.text = config.embedModel;
    }
    _synced = true;
  }

  void _applyProfileToControllers(EmbeddingProfile profile) {
    _embeddingBackend = profile.backend;
    if (profile.isApi) {
      _embedBaseUrlCtrl.text = profile.baseUrl;
      _embedApiKeyCtrl.text = profile.apiKey;
      _embedModelCtrl.text = profile.model;
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
    final embedBaseUrl = _useChatForEmbed
        ? _chatBaseUrlCtrl.text.trim()
        : _embedBaseUrlCtrl.text.trim();
    final embedApiKey = _useChatForEmbed
        ? _chatApiKeyCtrl.text.trim()
        : _embedApiKeyCtrl.text.trim();
    final embedModel = _useChatForEmbed
        ? _chatModelCtrl.text.trim()
        : _embedModelCtrl.text.trim();

    final config = LLMConfig(
      chatBaseUrl: _chatBaseUrlCtrl.text.trim(),
      chatApiKey: _chatApiKeyCtrl.text.trim(),
      chatModel: _chatModelCtrl.text.trim(),
      embedBaseUrl: embedBaseUrl,
      embedApiKey: embedApiKey,
      embedModel: embedModel,
    );

    await ref.read(apiConfigProvider.notifier).save(config);

    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final profile = _embeddingBackend == EmbeddingBackend.builtin
        ? EmbeddingProfile.builtin(
            model: BuiltinEmbeddingModel.id,
            dimension: BuiltinEmbeddingModel.expectedDimension,
            now: now,
          )
        : EmbeddingProfile.api(
            baseUrl: embedBaseUrl,
            apiKey: embedApiKey,
            model: embedModel,
            dimension: 0,
            now: now,
          );
    await ref.read(embeddingSettingsProvider.notifier).upsertProfile(profile);

    setState(() => _saved = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _saved = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider);
    final embeddingSettings = ref.watch(embeddingSettingsProvider);
    ref.watch(apiConfigProvider);

    return Scaffold(
      backgroundColor: theme.bgPrimary,
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

          // ── Chat API Section ──────────────────────────
          _sectionHeader(
              theme, Icons.chat_rounded, context.t.apiSettingsChatSection),
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

          // ── Embedding API Section ─────────────────────
          _sectionHeader(theme, Icons.auto_awesome_rounded,
              context.t.apiSettingsEmbedSection),
          const SizedBox(height: 4),
          Text(
            context.t.apiSettingsEmbedDesc,
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
                SegmentedButton<EmbeddingBackend>(
                  segments: const [
                    ButtonSegment(
                      value: EmbeddingBackend.api,
                      icon: Icon(Icons.cloud_queue_rounded, size: 18),
                      label: Text('API'),
                    ),
                    ButtonSegment(
                      value: EmbeddingBackend.builtin,
                      icon: Icon(Icons.memory_rounded, size: 18),
                      label: Text('Built-in'),
                    ),
                  ],
                  selected: {_embeddingBackend},
                  onSelectionChanged: (selected) {
                    setState(() => _embeddingBackend = selected.first);
                  },
                ),
                const SizedBox(height: 14),
                if (_embeddingBackend == EmbeddingBackend.builtin) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.accentPrimary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: theme.accentPrimary.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.memory_rounded,
                            color: theme.accentPrimary, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${BuiltinEmbeddingModel.displayName} · ${BuiltinEmbeddingModel.expectedDimension}d\n'
                            '使用内置固定模型生成 embedding。切换后需要为当前 profile 重建知识库；旧 profile 会保留，可随时切回。',
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
                ] else ...[
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
                          context.t.apiSettingsUseSameProvider,
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
                    _inputLabel(theme, context.t.apiSettingsLabelBaseUrl),
                    _inputField(
                      theme: theme,
                      controller: _embedBaseUrlCtrl,
                      hint: 'https://api.openai.com/v1',
                    ),
                    const SizedBox(height: 14),
                    _inputLabel(theme, context.t.apiSettingsLabelApiKey),
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
                        onPressed: () => setState(
                            () => _obscureEmbedKey = !_obscureEmbedKey),
                      ),
                    ),
                    const SizedBox(height: 14),
                    _inputLabel(theme, context.t.apiSettingsLabelModel),
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
                              context.t.apiSettingsEmbedFallbackNote,
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
              ],
            ),
          ),
          const SizedBox(height: 28),

          _buildProfileList(theme, embeddingSettings),
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

  Widget _buildProfileList(
    AppThemeTokens theme,
    EmbeddingSettingsState settings,
  ) {
    if (settings.profiles.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(theme, Icons.hub_rounded, 'Embedding Profiles'),
        const SizedBox(height: 12),
        ...settings.profiles.map((profile) {
          final active = profile.id == settings.activeProfileId;
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: ThemeAwareCard(
              child: Row(
                children: [
                  Icon(
                    profile.isBuiltin
                        ? Icons.memory_rounded
                        : Icons.cloud_queue_rounded,
                    color: active ? theme.accentPrimary : theme.textSecondary,
                    size: 22,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          profile.displayName,
                          style: theme.titleFont.copyWith(fontSize: 14),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          active
                              ? 'Active · ${profile.dimension > 0 ? '${profile.dimension}d' : 'dimension pending'}'
                              : '${profile.backend.name} · ${profile.dimension > 0 ? '${profile.dimension}d' : 'dimension pending'}',
                          style: theme.bodyFont.copyWith(
                            color: theme.textSecondary,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!active)
                    TextButton(
                      onPressed: () async {
                        await ref
                            .read(embeddingSettingsProvider.notifier)
                            .activateProfile(profile.id);
                        ref.invalidate(vectorStoreStatsProvider);
                        setState(() => _applyProfileToControllers(profile));
                      },
                      child: Text(
                        'Activate',
                        style: theme.bodyFont.copyWith(
                          color: theme.accentPrimary,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  IconButton(
                    tooltip: 'Delete',
                    icon: Icon(Icons.delete_outline_rounded,
                        color: settings.profiles.length == 1
                            ? theme.textSecondary.withValues(alpha: 0.35)
                            : theme.danger),
                    onPressed: settings.profiles.length == 1
                        ? null
                        : () => _deleteProfile(profile),
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  Future<void> _deleteProfile(EmbeddingProfile profile) async {
    final theme = ref.read(themeProvider);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: theme.bgSecondary,
        title: Text(
          'Delete profile?',
          style: theme.titleFont.copyWith(color: theme.textPrimary),
        ),
        content: Text(
          'This will delete the profile and all chunks/books indexed with it. This cannot be undone.',
          style: theme.bodyFont.copyWith(color: theme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text('Cancel',
                style: theme.bodyFont.copyWith(color: theme.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text('Delete',
                style: theme.bodyFont.copyWith(color: theme.danger)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await ref.read(vectorStoreProvider).deleteProfileData(profile.id);
    await ref
        .read(embeddingSettingsProvider.notifier)
        .deleteProfile(profile.id);
    ref.invalidate(vectorStoreStatsProvider);
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
