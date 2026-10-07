// The knowledge-base download notifier: when it downloads, the phases it
// reports, and cancelling.
import 'package:arklores/core/gamedata/gamedata_installer.dart';
import 'package:arklores/core/gamedata/gamedata_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_installer.dart';

void main() {
  ProviderContainer containerWith(GameDataInstaller installer) {
    final c = ProviderContainer(
      overrides: [gameDataInstallerProvider.overrideWithValue(installer)],
    );
    addTearDown(c.dispose);
    return c;
  }

  test('an installed, current knowledge base is not downloaded again unless '
      'forced', () async {
    final installer = FakeInstaller(
      installStatus(installed: true, installedSha: 'aa', releaseSha: 'aa'),
    );
    final notifier = containerWith(installer).read(gameDataDownloadProvider.notifier);
    await notifier.start();
    expect(installer.downloads, 0);
    await notifier.start(force: true);
    expect(installer.downloads, 1);
  });

  test('a newer official asset is downloaded', () async {
    final installer = FakeInstaller(
      installStatus(installed: true, installedSha: 'aa', releaseSha: 'bb'),
    );
    await containerWith(installer).read(gameDataDownloadProvider.notifier).start();
    expect(installer.downloads, 1);
  });

  test('phases reach the state; cancel ends without an error', () async {
    final container =
        containerWith(SilentInstaller(installStatus(installed: false, releaseSha: 'aa')));
    final notifier = container.read(gameDataDownloadProvider.notifier);
    final running = notifier.start(force: true);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    var state = container.read(gameDataDownloadProvider);
    expect(state.downloading, isTrue);
    expect(state.phase, GameDataInstallPhase.connecting);
    expect(state.attempt, 2);
    notifier.cancel();
    await running;
    state = container.read(gameDataDownloadProvider);
    expect(state.downloading, isFalse);
    expect(state.error, isNull);
    expect(state.result, GameDataDownloadResult.none);
  });
}
