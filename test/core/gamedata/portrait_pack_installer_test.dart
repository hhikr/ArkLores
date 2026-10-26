import 'dart:async';
import 'dart:io';

import 'package:arklores/core/gamedata/gamedata_channel.dart';
import 'package:arklores/core/gamedata/portrait_pack.dart';
import 'package:arklores/core/gamedata/portrait_pack_installer.dart';
import 'package:arklores/core/gamedata/resumable_download.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../support/portrait_pack_fixture.dart';
import '../../support/sqlite.dart';
import '../../support/temp_dir.dart';

void main() {
  late Directory dir;
  late PortraitPackInstaller installer;
  late PortraitPack pack;
  setUpAll(useSqfliteFfi);
  setUp(() async {
    dir = Directory.systemTemp.createTempSync('portrait-install');
    installer = PortraitPackInstaller(installDirectory: dir);
    pack = PortraitPack(await installer.path);
  });
  tearDown(() async {
    await pack.close();
    await deleteTempDir(dir);
  });
  PortraitPackAsset asset(List<int> bytes, {String? sha}) => PortraitPackAsset(
        url: 'https://example.test/pack.db',
        sha256: sha ?? sha256.convert(bytes).toString(),
        size: bytes.length,
      );
  Future<void> seed() async {
    final source = await createPortraitPack(dir, name: 'old.db', commit: 'old');
    await source.copy(await installer.path);
    expect(await pack.installed, isTrue);
  }

  void noPartial() {
    expect(File('${pack.path}.download').existsSync(), isFalse);
    expect(File('${pack.path}.download.key').existsSync(), isFalse);
  }

  test('installs, records SHA, reopens old connection, deletes', () async {
    await seed();
    final bytes = await (await createPortraitPack(dir)).readAsBytes();
    final offered = asset(bytes);
    await installer.install(
      offered,
      pack: pack,
      client: MockClient((_) async => http.Response.bytes(bytes, 200)),
    );
    expect((await pack.manifest())['kb_commit'], 'fixture');
    final status = await installer.status(asset: offered);
    expect(status.installed, isTrue);
    expect(status.spriteCount, 4);
    expect(status.bytes, bytes.length);
    expect(status.updateAvailable, isFalse);
    expect(
        (await installer.status(asset: asset(bytes, sha: 'other')))
            .updateAvailable,
        isTrue,);
    noPartial();
    await installer.delete(pack);
    expect(await pack.installed, isFalse);
    expect((await installer.status()).installed, isFalse);
  });
  test('wrong SHA preserves installed pack', () async {
    await seed();
    final before = await File(pack.path).readAsBytes();
    await expectLater(
      installer.install(
        asset([1, 2], sha: 'wrong'),
        pack: pack,
        client: MockClient((_) async => http.Response.bytes([1, 2], 200)),
      ),
      throwsStateError,
    );
    expect(await File(pack.path).readAsBytes(), before);
    noPartial();
  });
  for (final kind in ['version', 'empty', 'garbage']) {
    test('invalid $kind preserves installed pack', () async {
      await seed();
      final before = await File(pack.path).readAsBytes();
      final bytes = kind == 'garbage'
          ? [1, 2, 3]
          : await (await createPortraitPack(
              dir,
              version: kind == 'version' ? '2' : '1',
              empty: kind == 'empty',
            ))
              .readAsBytes();
      await expectLater(
        installer.install(
          asset(bytes),
          pack: pack,
          client: MockClient((_) async => http.Response.bytes(bytes, 200)),
        ),
        throwsA(isA<Object>()),
      );
      expect(await File(pack.path).readAsBytes(), before);
      noPartial();
    });
  }
  test('cancels silent server without changing installed file', () async {
    await seed();
    final before = await File(pack.path).readAsBytes();
    final token = GameDataDownloadToken();
    final requested = Completer<void>();
    final client = MockClient.streaming((_, __) {
      requested.complete();
      return Completer<http.StreamedResponse>().future;
    });
    final future = installer.install(
      asset([1]),
      pack: pack,
      client: client,
      cancelToken: token,
      connectTimeout: const Duration(milliseconds: 100),
    );
    final assertion =
        expectLater(future, throwsA(isA<GameDataDownloadCancelled>()));
    await requested.future;
    token.cancel();
    await assertion;
    expect(await File(pack.path).readAsBytes(), before);
    noPartial();
  });
  test('dropped stream resumes within installation', () async {
    final bytes = await (await createPortraitPack(dir)).readAsBytes();
    final half = bytes.length ~/ 2;
    final ranges = <String?>[];
    final client = MockClient.streaming((request, _) async {
      ranges.add(request.headers['Range']);
      if (ranges.length == 1) {
        final stream = StreamController<List<int>>()
          ..add(bytes.sublist(0, half))
          ..addError(const SocketException('dropped'));
        unawaited(stream.close());
        return http.StreamedResponse(stream.stream, 200,
            contentLength: bytes.length,);
      }
      return http.StreamedResponse(Stream.value(bytes.sublist(half)), 206,
          contentLength: bytes.length - half,);
    });
    await installer.install(asset(bytes),
        pack: pack, client: client, retryDelay: Duration.zero,);
    expect(ranges, [null, 'bytes=$half-']);
    expect(await pack.installed, isTrue);
    noPartial();
  });
}
