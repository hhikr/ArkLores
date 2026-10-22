import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/l10n/l10n.dart';
import '../../shared/providers/settings_provider.dart';
import '../../shared/providers/theme_provider.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/ef_widgets.dart';
import '../../shared/widgets/page_frame.dart';

/// Profile settings: one entry for now, how the stories address the reader.
/// Saved as it is typed.
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
    return PageScaffold(
      title: context.t.settingsProfile,
      scrollUnder: true,
      body: ListView(
        padding: pagePadding(context, const EdgeInsets.fromLTRB(16, 4, 16, 32)),
        children: [
          SectionTitle(title: context.t.profileNicknameLabel, code: 'name'),
          TextField(
            key: const ValueKey('profile-nickname'),
            controller: _nickname,
            onChanged: _save,
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
      ),
    );
  }
}
