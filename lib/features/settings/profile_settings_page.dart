import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/l10n/l10n.dart';
import '../../shared/providers/settings_provider.dart';
import '../../shared/providers/theme_provider.dart';
import '../../shared/widgets/floating_bar.dart';
import '../../shared/widgets/theme_aware_card.dart';

/// Profile settings: one entry for now, how the stories address the reader.
class ProfileSettingsPage extends ConsumerStatefulWidget {
  const ProfileSettingsPage({super.key});

  @override
  ConsumerState<ProfileSettingsPage> createState() =>
      _ProfileSettingsPageState();
}

class _ProfileSettingsPageState extends ConsumerState<ProfileSettingsPage> {
  late final TextEditingController _nickname =
      TextEditingController(text: ref.read(nicknameProvider));

  @override
  void dispose() {
    _nickname.dispose();
    super.dispose();
  }

  void _save(String value) {
    ref.read(nicknameProvider.notifier).state = value.trim();
    ref.read(settingsServiceProvider).saveNickname(value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider);
    return FloatingScaffold(
      title: context.t.settingsProfile,
      scrollUnder: true,
      body: ListView(
        padding: floatingPadding(context, const EdgeInsets.all(16)),
        children: [
          ThemeAwareCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  key: const ValueKey('profile-nickname'),
                  controller: _nickname,
                  onChanged: _save,
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    labelText: context.t.profileNicknameLabel,
                    hintText: context.t.profileNicknameDefault,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  context.t.profileNicknameHelp,
                  style: theme.bodyFont.copyWith(
                    color: theme.textSecondary,
                    fontSize: 12,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
