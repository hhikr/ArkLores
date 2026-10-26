import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/settings/settings_service.dart';
import '../../shared/app_version.dart';
import '../../shared/providers/settings_provider.dart';
import '../background/background_work.dart';
import '../gamedata/resumable_download.dart';
import 'app_update.dart';

/// How often the automatic check runs at most.
const autoUpdateCheckInterval = Duration(hours: 24);

final appUpdaterProvider = Provider<AppUpdater>((ref) => AppUpdater());
final appInstallerProvider = Provider<AppInstaller>((ref) => AppInstaller());

/// The running app's version (tests put in another).
final currentAppVersionProvider = Provider<String>((ref) => appVersion);

/// Whether the app looks for a new version on start (default off), loaded
/// at startup.
final initialAutoUpdateCheckProvider = Provider<bool>((ref) => false);

final autoUpdateCheckProvider = StateProvider<bool>(
  (ref) => ref.watch(initialAutoUpdateCheckProvider),
);

/// Where the update is.
enum AppUpdatePhase {
  idle,
  checking,
  upToDate,

  /// A newer version: [AppUpdateState.release].
  available,
  downloading,
  verifying,

  /// Downloaded and checked; waiting for the system to allow installing.
  needsPermission,

  /// Downloaded and checked; handed to the installer (or to hand again).
  ready,
  failed,
}

class AppUpdateState {
  const AppUpdateState({
    this.phase = AppUpdatePhase.idle,
    this.release,
    this.received = 0,
    this.total,
    this.failure,
  });

  final AppUpdatePhase phase;
  final AppRelease? release;
  final int received;
  final int? total;
  final AppUpdateFailure? failure;

  bool get busy =>
      phase == AppUpdatePhase.checking ||
      phase == AppUpdatePhase.downloading ||
      phase == AppUpdatePhase.verifying;
}

final appUpdateProvider =
    StateNotifierProvider<AppUpdateNotifier, AppUpdateState>(
  (ref) => AppUpdateNotifier(
    updater: ref.watch(appUpdaterProvider),
    installer: ref.watch(appInstallerProvider),
    settings: ref.watch(settingsServiceProvider),
    currentVersion: ref.watch(currentAppVersionProvider),
  ),
);

class AppUpdateNotifier extends StateNotifier<AppUpdateState> {
  AppUpdateNotifier({
    required this.updater,
    required this.installer,
    required this.settings,
    required this.currentVersion,
  }) : super(const AppUpdateState());

  final AppUpdater updater;
  final AppInstaller installer;
  final SettingsService settings;
  final String currentVersion;

  GameDataDownloadToken? _token;
  File? _apk;
  bool _handingOver = false;

  /// Looks for a newer release. Returns it, or null (none, or the check
  /// failed: the state says which).
  Future<AppRelease?> check({DateTime? checkedAt}) async {
    if (state.busy) return null;
    state = const AppUpdateState(phase: AppUpdatePhase.checking);
    _apk = null;
    try {
      // Failed attempts also count towards the daily automatic limit.
      await settings.saveLastUpdateCheck(checkedAt ?? DateTime.now());
      final latest = await updater.latest();
      final current = parseAppVersion(currentVersion);
      final newer = latest != null &&
          (current == null || compareAppVersions(latest.version, current) > 0);
      if (!mounted) return null;
      state = newer
          ? AppUpdateState(phase: AppUpdatePhase.available, release: latest)
          : const AppUpdateState(phase: AppUpdatePhase.upToDate);
      return newer ? latest : null;
    } catch (e) {
      if (mounted) {
        state = AppUpdateState(
          phase: AppUpdatePhase.failed,
          failure: e is AppUpdateException ? e.failure : AppUpdateFailure.check,
        );
      }
      return null;
    }
  }

  /// On app start, with the automatic check on: checks when the last check
  /// is [autoUpdateCheckInterval] ago or more. Returns a newer release.
  /// Never downloads.
  Future<AppRelease?> autoCheck({required bool enabled, DateTime? now}) async {
    if (!enabled || state.phase != AppUpdatePhase.idle) return null;
    final last = await settings.loadLastUpdateCheck();
    final at = now ?? DateTime.now();
    if (last != null && at.difference(last) < autoUpdateCheckInterval) {
      return null;
    }
    if (!mounted || state.phase != AppUpdatePhase.idle) return null;
    return check(checkedAt: at);
  }

  /// Downloads the release found by [check], checks it and hands it to the
  /// installer (after the system allows installing). [label] is the
  /// background notification's text.
  Future<void> downloadAndInstall(String label) async {
    final release = state.release;
    if (release == null || state.busy) return;
    if (_apk != null) return _handOver();
    _token = GameDataDownloadToken();
    state = AppUpdateState(
      phase: AppUpdatePhase.downloading,
      release: release,
      total: release.apkSize > 0 ? release.apkSize : null,
    );
    try {
      var last = -256 * 1024;
      final apk = await BackgroundWork.instance.run(
        label,
        () => updater.download(
          release,
          cancelToken: _token,
          onProgress: (received, total) {
            if (!mounted ||
                (received - last < 256 * 1024 && received != total)) {
              return;
            }
            last = received;
            state = AppUpdateState(
              phase: AppUpdatePhase.downloading,
              release: release,
              received: received,
              total: total ?? state.total,
            );
          },
          onVerifying: () {
            if (mounted) {
              state = AppUpdateState(
                phase: AppUpdatePhase.verifying,
                release: release,
              );
            }
          },
        ),
      );
      _apk = apk;
      if (mounted) await _handOver();
    } on GameDataDownloadCancelled {
      if (mounted) {
        state =
            AppUpdateState(phase: AppUpdatePhase.available, release: release);
      }
    } catch (e) {
      if (mounted) {
        state = AppUpdateState(
          phase: AppUpdatePhase.failed,
          release: release,
          failure:
              e is AppUpdateException ? e.failure : AppUpdateFailure.download,
        );
      }
    } finally {
      _token = null;
    }
  }

  void cancel() => _token?.cancel();

  /// Opens the system page where installing is allowed.
  Future<void> openInstallSettings() async {
    try {
      await installer.openInstallSettings();
    } catch (_) {
      if (mounted) {
        state = AppUpdateState(
          phase: AppUpdatePhase.failed,
          release: state.release,
          failure: AppUpdateFailure.install,
        );
      }
    }
  }

  /// Back from the system's settings: installs when it is allowed now.
  Future<void> onResumed() async {
    if (state.phase != AppUpdatePhase.needsPermission) return;
    if (await installer.canInstall()) await _handOver();
  }

  Future<void> _handOver() async {
    final apk = _apk;
    final release = state.release;
    if (apk == null || release == null || _handingOver) return;
    _handingOver = true;
    try {
      if (!await installer.canInstall()) {
        if (mounted) {
          state = AppUpdateState(
            phase: AppUpdatePhase.needsPermission,
            release: release,
          );
        }
        return;
      }
      try {
        await installer.install(apk);
        if (mounted) {
          state = AppUpdateState(phase: AppUpdatePhase.ready, release: release);
        }
      } catch (e) {
        if (mounted) {
          state = AppUpdateState(
            phase: AppUpdatePhase.failed,
            release: release,
            failure: AppUpdateFailure.install,
          );
        }
      }
    } finally {
      _handingOver = false;
    }
  }

  @override
  void dispose() {
    _token?.cancel();
    super.dispose();
  }
}
