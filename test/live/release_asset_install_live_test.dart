import 'dart:io';

import 'package:arklores/core/gamedata/gamedata_installer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Opt-in (`ARKLORES_RUN_ASSET_INSTALL=true`, `ARKLORES_ASSET_URL`,
/// `ARKLORES_ASSET_SHA`): installs the real release asset the way the app
/// does (download, checksum, unzip, validate, swap) into a temp directory.
void main() {
  final url = Platform.environment['ARKLORES_ASSET_URL'] ?? '';
  final sha = Platform.environment['ARKLORES_ASSET_SHA'] ?? '';
  final run = Platform.environment['ARKLORES_RUN_ASSET_INSTALL'] == 'true';

  test('the published asset installs', () async {
    sqfliteFfiInit();
    sqflite.databaseFactory = databaseFactoryFfi;
    final dir = Directory.systemTemp.createTempSync('arklores_asset_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final installer = GameDataInstaller(
      installDirectory: dir,
      releaseAssetUrl: url,
      releaseAssetSha: sha,
    );
    final sw = Stopwatch()..start();
    var last = -1;
    final ok = await installer.installFromReleaseAsset(
      onProgress: (received, total) {
        final pct = total == null ? -1 : received * 100 ~/ total;
        if (pct != last && pct % 10 == 0) {
          last = pct;
          // ignore: avoid_print
          print('${sw.elapsed.inSeconds}s download $pct% ($received / $total)');
        }
      },
    );
    // ignore: avoid_print
    print('${sw.elapsed.inSeconds}s installed=$ok');
    expect(ok, isTrue);
    final status = await installer.getStatus();
    // ignore: avoid_print
    print('bytes=${status.bytes} manifest=${status.manifest.length} '
        'marker=${status.installedAssetSha}');
    expect(status.installed, isTrue);
    expect(status.installedAssetSha, sha);
    final leftovers = dir
        .listSync()
        .map((e) => e.path.split(Platform.pathSeparator).last)
        .where((n) => n.contains('.download') || n.endsWith('.tmp'));
    expect(leftovers, isEmpty);
  },
      skip: run ? false : 'set ARKLORES_RUN_ASSET_INSTALL=true',
      timeout: const Timeout(Duration(minutes: 15)),);
}
