import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/background/background_work.dart';
import '../../shared/l10n/l10n.dart';
import '../../shared/providers/settings_provider.dart';
import '../../shared/providers/theme_provider.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/ef_widgets.dart';

/// Set once nothing is left to explain in this run of the app: later calls
/// (every question) return at once.
bool _explained = false;

/// Forgets [_explained] (tests).
@visibleForTesting
void resetBackgroundExplained() => _explained = false;

/// Before the first answer (or on Ask, for a reader who has asked before):
/// once, says why the app asks to be exempt from battery optimisation, and
/// asks the system on "Allow". Nothing where there is nothing to ask or the
/// app is exempt already.
Future<void> explainBackgroundOnce(BuildContext context, WidgetRef ref) async {
  if (_explained) return;
  final work = ref.read(backgroundWorkProvider);
  final settings = ref.read(settingsServiceProvider);
  final access = await work.access();
  if (access == null || access.batteryExempt) {
    _explained = true;
    return;
  }
  if (await settings.isBackgroundExplained()) {
    _explained = true;
    return;
  }
  if (!context.mounted || _explained) return;
  // Before the dialog: a second call while it is up does not show another.
  _explained = true;
  await settings.markBackgroundExplained();
  if (!context.mounted) return;
  final allow = await showAppDialog<bool>(
    context,
    (context) => AppDialog(
      key: const ValueKey('background-access-dialog'),
      title: context.t.backgroundAccessTitle,
      code: 'background',
      message: context.t.backgroundAccessBody,
      actions: [
        AppButton(
          context.t.onboardingNotNow,
          small: true,
          kind: ButtonKind.quiet,
          onPressed: () => Navigator.of(context).pop(false),
        ),
        AppButton(
          context.t.backgroundAccessAllow,
          key: const ValueKey('background-access-allow'),
          small: true,
          kind: ButtonKind.go,
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    ),
  );
  if (allow ?? false) await work.requestBatteryExempt();
}

/// The two things the system decides about background work, each with its
/// state ("Allowed") or a button that asks. Read again when the app comes
/// back from the system's dialog or settings. Nothing where there is
/// nothing to ask (not Android).
class BackgroundAccessRows extends ConsumerStatefulWidget {
  const BackgroundAccessRows({super.key});

  @override
  ConsumerState<BackgroundAccessRows> createState() =>
      _BackgroundAccessRowsState();
}

class _BackgroundAccessRowsState extends ConsumerState<BackgroundAccessRows>
    with WidgetsBindingObserver {
  BackgroundAccess? _access;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _read();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _read();
  }

  Future<void> _read() async {
    final access = await ref.read(backgroundWorkProvider).access();
    if (mounted) setState(() => _access = access);
  }

  @override
  Widget build(BuildContext context) {
    final access = _access;
    if (access == null) return const SizedBox.shrink();
    final work = ref.read(backgroundWorkProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _row(
          key: 'notifications',
          icon: Icons.notifications_none_sharp,
          label: context.t.backgroundAccessNotifications,
          description: context.t.backgroundAccessNotificationsDesc,
          granted: access.notifications,
          onGrant: work.requestNotifications,
        ),
        _row(
          key: 'battery',
          icon: Icons.battery_saver_sharp,
          label: context.t.backgroundAccessBattery,
          description: context.t.backgroundAccessBatteryDesc,
          granted: access.batteryExempt,
          onGrant: () {
            // Asked here, so Ask need not explain it again.
            ref.read(settingsServiceProvider).markBackgroundExplained();
            return work.requestBatteryExempt();
          },
        ),
      ],
    );
  }

  Widget _row({
    required String key,
    required IconData icon,
    required String label,
    required String description,
    required bool granted,
    required Future<void> Function() onGrant,
  }) {
    final theme = ref.watch(themeProvider);
    return ActionRow(
      key: ValueKey('background-access-$key'),
      icon: icon,
      label: label,
      description: description,
      showChevron: false,
      onTap: granted ? null : onGrant,
      trailing: granted
          ? Text(
              context.t.backgroundAccessGranted,
              style: theme.field(color: theme.textPrimary, weight: 600),
            )
          : AppButton(
              context.t.backgroundAccessGrant,
              key: ValueKey('background-access-$key-grant'),
              small: true,
              kind: ButtonKind.go,
              onPressed: onGrant,
            ),
    );
  }
}
