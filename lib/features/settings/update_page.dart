import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/update/app_update.dart';
import '../../core/update/app_update_provider.dart';
import '../../shared/app_version.dart';
import '../../shared/l10n/l10n.dart';
import '../../shared/providers/settings_provider.dart';
import '../../shared/providers/theme_provider.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/ef_widgets.dart';

String _mb(int bytes) => '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';

/// The update rows of Settings → Help & Guide (on that page itself,
/// developer 2026-10-26): the version, the automatic check (off by default)
/// and checking, downloading and installing by hand. The work lives in
/// [appUpdateProvider], so a download goes on when the page is left; back
/// from the system's "install unknown apps" page it installs.
class UpdateRows extends ConsumerStatefulWidget {
  const UpdateRows({super.key});

  @override
  ConsumerState<UpdateRows> createState() => _UpdateRowsState();
}

class _UpdateRowsState extends ConsumerState<UpdateRows>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(ref.read(appUpdateProvider.notifier).onResumed());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(ref.read(appUpdateProvider.notifier).onResumed());
    }
  }

  Future<void> _setAuto(bool value) async {
    ref.read(autoUpdateCheckProvider.notifier).state = value;
    await ref.read(settingsServiceProvider).saveAutoUpdateCheck(value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider);
    final t = context.t;
    final auto = ref.watch(autoUpdateCheckProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ActionRow(
          key: const ValueKey('update-version'),
          icon: Icons.info_outline_sharp,
          label: t.settingsVersion,
          description: t.updateVersionBuild(appVersion, appBuild),
          showChevron: false,
        ),
        ActionRow(
          key: const ValueKey('settings-auto-update'),
          icon: Icons.update_sharp,
          label: t.updateAutoCheck,
          description: t.updateAutoCheckDesc,
          onTap: () => _setAuto(!auto),
          trailing: SquareSwitch(
            value: auto,
            semanticLabel: t.updateAutoCheck,
            onChanged: _setAuto,
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: theme.divider)),
          ),
          child: const _UpdateStatus(),
        ),
      ],
    );
  }
}

/// What the check found and the one thing to do next.
class _UpdateStatus extends ConsumerWidget {
  const _UpdateStatus();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    final t = context.t;
    final s = ref.watch(appUpdateProvider);
    final notifier = ref.read(appUpdateProvider.notifier);
    final supported = ref.watch(appInstallerProvider).supported;
    final release = s.release;

    void install() =>
        unawaited(notifier.downloadAndInstall(t.updateNotification));

    final checkButton = AppButton(
      t.updateCheck,
      key: const ValueKey('update-check'),
      small: true,
      busy: s.phase == AppUpdatePhase.checking,
      onPressed: s.busy ? null : () => unawaited(notifier.check()),
    );

    Widget note(String text, {Color? color}) => Text(
          text,
          style: theme.text(14, color: color ?? theme.textPrimary, height: 1.5),
        );

    // The step to take, with checking again beside it (not under it).
    Widget buttons(Widget main) => Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [main, checkButton],
        );

    final children = <Widget>[];
    void gap([double h = 10]) => children.add(SizedBox(height: h));

    if (release != null &&
        s.phase != AppUpdatePhase.upToDate &&
        s.phase != AppUpdatePhase.checking) {
      children.add(
        Text(
          t.updateAvailable(release.versionName),
          key: const ValueKey('update-available'),
          style: theme.heading(17),
        ),
      );
      gap(4);
      if (release.apkSize > 0) {
        children.add(
          note(
            t.updateAvailableSize(_mb(release.apkSize)),
            color: theme.textSecondary,
          ),
        );
      }
      final excerpt = release.notesExcerpt();
      if (excerpt.isNotEmpty) {
        gap(8);
        children.add(
          Text(
            excerpt,
            key: const ValueKey('update-notes'),
            style: theme.text(13, color: theme.textSecondary, height: 1.5),
          ),
        );
      }
      gap(12);
    }

    switch (s.phase) {
      case AppUpdatePhase.idle:
        children
            .add(Align(alignment: Alignment.centerLeft, child: checkButton));
      case AppUpdatePhase.checking:
        children
          ..add(BusyMark(width: 144, label: t.updateChecking))
          ..add(const SizedBox(height: 12))
          ..add(Align(alignment: Alignment.centerLeft, child: checkButton));
      case AppUpdatePhase.upToDate:
        children
          ..add(note(t.updateUpToDate))
          ..add(const SizedBox(height: 12))
          ..add(Align(alignment: Alignment.centerLeft, child: checkButton));
      case AppUpdatePhase.available:
        if (!supported) {
          children.add(note(t.updateUnsupported, color: theme.textSecondary));
        } else {
          children.add(
            buttons(
              AppButton(
                t.updateDownloadInstall,
                key: const ValueKey('update-download'),
                kind: ButtonKind.go,
                small: true,
                onPressed: install,
              ),
            ),
          );
        }
      case AppUpdatePhase.downloading:
        final total = s.total ?? 0;
        children
          ..add(
            SegmentProgress(
              key: const ValueKey('update-progress'),
              value: total > 0 ? (s.received / total).clamp(0.0, 1.0) : null,
              label: t.updateDownloading(
                _mb(s.received),
                total > 0 ? _mb(total) : '?',
              ),
            ),
          )
          ..add(const SizedBox(height: 12))
          ..add(
            Align(
              alignment: Alignment.centerLeft,
              child: AppButton(
                t.updateCancel,
                key: const ValueKey('update-cancel'),
                small: true,
                onPressed: notifier.cancel,
              ),
            ),
          );
      case AppUpdatePhase.verifying:
        children.add(BusyMark(width: 144, label: t.updateVerifying));
      case AppUpdatePhase.needsPermission:
        children.add(
          NoticeBox(
            t.updateNeedsPermission,
            key: const ValueKey('update-permission'),
            action: AppButton(
              t.updateAllow,
              key: const ValueKey('update-allow'),
              kind: ButtonKind.go,
              small: true,
              onPressed: () => unawaited(notifier.openInstallSettings()),
            ),
          ),
        );
      case AppUpdatePhase.ready:
        children
          ..add(note(t.updateReady))
          ..add(const SizedBox(height: 12))
          ..add(
            buttons(
              AppButton(
                t.updateInstall,
                key: const ValueKey('update-install'),
                kind: ButtonKind.go,
                small: true,
                onPressed: install,
              ),
            ),
          );
      case AppUpdatePhase.failed:
        children.add(
          NoticeBox(
            switch (s.failure) {
              AppUpdateFailure.download => t.updateErrorDownload,
              AppUpdateFailure.checksum => t.updateErrorChecksum,
              AppUpdateFailure.install => t.updateErrorInstall,
              AppUpdateFailure.check || null => t.updateErrorCheck,
            },
            key: const ValueKey('update-error'),
            action: AppButton(
              t.updateRetry,
              key: const ValueKey('update-retry'),
              small: true,
              onPressed: release != null && supported
                  ? install
                  : () => unawaited(notifier.check()),
            ),
          ),
        );
    }
    if ((s.phase == AppUpdatePhase.available && !supported) ||
        s.phase == AppUpdatePhase.needsPermission) {
      gap(12);
      children.add(Align(alignment: Alignment.centerLeft, child: checkButton));
    }
    return Semantics(
      liveRegion: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}
