// The channel file: official knowledge bases uploaded after the app was
// built are found, and only offered when this build can install them.
import 'dart:convert';
import 'dart:io';

import 'package:arklores/core/gamedata/build/gamedata_schema.dart';
import 'package:arklores/core/gamedata/game.dart';
import 'package:arklores/core/gamedata/gamedata_channel.dart';
import 'package:arklores/core/gamedata/gamedata_installer.dart';
import 'package:arklores/core/gamedata/gamedata_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../support/temp_dir.dart';

void main() {
  final newSha = 'b' * 64;
  Map<String, Object> asset({
    String sha = '',
    String? commitDate,
    int? schema,
    int? minBuild,
  }) =>
      {
        'url': 'https://example.org/kb.db.gz',
        'sha256': sha.isEmpty ? newSha : sha,
        'commit': 'c2',
        if (commitDate != null) 'commit_date': commitDate,
        'schema_version': schema ?? gamedataSchemaVersion,
        if (minBuild != null) 'min_app_build': minBuild,
      };
  GameDataChannel channelOf(Map<String, Object> arknights) =>
      GameDataChannel.parse(jsonEncode({'arknights': arknights}))!;

  const baked = GameDataInstaller(
    releaseAssetUrl: 'https://example.org/old.db.gz',
    releaseAssetSha: 'aaaa',
    releaseAssetCommit: 'c1',
    releaseAssetCommitDate: '2026-10-01T00:00:00Z',
  );

  test('a newer asset in the channel replaces the one baked into the build',
      () {
    final installer = withChannel(
      baked,
      channelOf(asset(commitDate: '2026-10-15T00:00:00Z')),
      appBuild: 40,
    );
    expect(installer.releaseAssetUrl, 'https://example.org/kb.db.gz');
    expect(installer.releaseAssetSha, newSha);
    expect(installer.releaseAssetCommit, 'c2');
    expect(installer.releaseAssetCommitDate, '2026-10-15T00:00:00Z');
    expect(installer.game, Game.arknights);
  });

  test('an asset this build cannot install, or of older data, is not offered',
      () {
    // Another schema.
    expect(
      withChannel(baked, channelOf(asset(schema: 99)), appBuild: 40),
      same(baked),
    );
    // A later app build is needed.
    expect(
      withChannel(baked, channelOf(asset(minBuild: 41)), appBuild: 40),
      same(baked),
    );
    // Older game data than the build's own asset.
    expect(
      withChannel(
        baked,
        channelOf(asset(commitDate: '2026-09-01T00:00:00Z')),
        appBuild: 40,
      ),
      same(baked),
    );
    // Nothing for this game, or no channel at all.
    const endfield = GameDataInstaller.forGame(Game.endfield);
    expect(withChannel(endfield, channelOf(asset())), same(endfield));
    expect(withChannel(baked, null), same(baked));
  });

  test('a file of another shape is no channel; a game without a URL is left '
      'out', () {
    expect(GameDataChannel.parse('not json'), isNull);
    expect(GameDataChannel.parse('[]'), isNull);
    final channel = GameDataChannel.parse(
      jsonEncode({
        'arknights': {'sha256': newSha},
        'endfield': asset(),
      }),
    )!;
    expect(channel.assets.keys, [Game.endfield]);
  });

  test('reading the channel: the file, or null when it cannot be read',
      () async {
    final body = jsonEncode({'arknights': asset()});
    final read = await fetchGameDataChannel(
      url: 'https://example.org/gamedata_channel.json',
      client: MockClient((_) async => http.Response(body, 200)),
    );
    expect(read!.assets[Game.arknights]!.sha256, newSha);
    expect(
      await fetchGameDataChannel(
        url: 'https://example.org/gamedata_channel.json',
        client: MockClient((_) async => http.Response('Not Found', 404)),
      ),
      isNull,
    );
    expect(
      await fetchGameDataChannel(
        url: 'https://example.org/gamedata_channel.json',
        client: MockClient((_) async => throw const SocketException('down')),
      ),
      isNull,
    );
    // A build without a channel address reads nothing.
    expect(await fetchGameDataChannel(url: ''), isNull);
  });

  test('the installation status offers the channel asset', () async {
    final dir = Directory.systemTemp.createTempSync('gamedata_channel');
    addTearDown(() => deleteTempDir(dir));
    final container = ProviderContainer(
      overrides: [
        gameDataInstallerProvider.overrideWithValue(
          GameDataInstaller(
            installDirectory: dir,
            releaseAssetUrl: 'https://example.org/old.db.gz',
            releaseAssetSha: 'aaaa',
          ),
        ),
        gameDataChannelProvider.overrideWith((ref) async => channelOf(asset())),
      ],
    );
    addTearDown(container.dispose);
    await container.read(gameDataChannelProvider.future);
    final status = await container.read(gameDataInstallStatusProvider.future);
    expect(status.releaseAssetSha, newSha);
  });
}
