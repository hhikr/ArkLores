import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'gamedata_installer.dart';

final gameDataInstallerProvider = Provider<GameDataInstaller>((ref) {
  return GameDataInstaller();
});

final gameDataInstallStatusProvider =
    FutureProvider<GameDataInstallStatus>((ref) async {
  return ref.read(gameDataInstallerProvider).getStatus();
});
