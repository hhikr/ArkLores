import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'build/gamedata_schema.dart';
import 'game.dart';
import 'gamedata_installer.dart';

/// The official knowledge bases of the moment, read from a file the developer
/// replaces with each data release (`gamedata_channel.json` on the
/// `gamedata-channel` Release, see `docs/GAMEDATA_BUILD_PIPELINE.md`).
///
/// The asset an app build points at is baked in when it is built, so a
/// knowledge base uploaded later was not seen until the next app release.
/// With the channel the knowledge-base page finds it; without one (no
/// network, no file, a file this build cannot use) the baked-in asset stays.
class GameDataChannel {
  const GameDataChannel(this.assets, {this.storyArt});

  final StoryArtPackAsset? storyArt;

  final Map<Game, GameDataChannelAsset> assets;

  /// The file's JSON: one object per game key (`arknights`, `endfield`).
  /// Null when it is not that shape; a game whose object lacks a URL or a
  /// SHA-256 is left out.
  static GameDataChannel? parse(String text) {
    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException {
      return null;
    }
    if (decoded is! Map) return null;
    return GameDataChannel(
      {
        for (final game in Game.values)
          if (GameDataChannelAsset.fromJson(decoded[game.key])
              case final asset?)
            game: asset,
      },
      storyArt: StoryArtPackAsset.fromJson(decoded['arknights_story_art']),
    );
  }
}

/// One game's official asset in the channel file.
class GameDataChannelAsset {
  const GameDataChannelAsset({
    required this.url,
    required this.sha256,
    this.commit = '',
    this.commitDate = '',
    this.schemaVersion,
    this.minAppBuild,
  });

  final String url;
  final String sha256;

  /// The game-data commit the asset was made from and when it was made
  /// (Arknights; '' for Endfield, which is not made from a repository).
  final String commit;
  final String commitDate;

  /// The database schema the asset has; a build installs only its own.
  final int? schemaVersion;

  /// The first app build that can install the asset (the validator of an
  /// older build may ask for tables the asset no longer has).
  final int? minAppBuild;

  static GameDataChannelAsset? fromJson(Object? json) {
    if (json is! Map) return null;
    String text(String key) =>
        json[key] is String ? (json[key] as String).trim() : '';
    int? number(String key) => switch (json[key]) {
          final int n => n,
          final String s => int.tryParse(s.trim()),
          _ => null,
        };
    final url = text('url');
    final sha = text('sha256');
    if (url.isEmpty || sha.isEmpty) return null;
    return GameDataChannelAsset(
      url: url,
      sha256: sha,
      commit: text('commit'),
      commitDate: text('commit_date'),
      schemaVersion: number('schema_version'),
      minAppBuild: number('min_app_build'),
    );
  }

  /// Whether a build of [appBuild] (null: not known, as in development runs)
  /// can install this asset.
  bool usableBy(int? appBuild) =>
      schemaVersion == gamedataSchemaVersion &&
      (minAppBuild == null || appBuild == null || appBuild >= minAppBuild!);
}

/// The build number of this app (`pubspec.yaml`, after the `+`), which the
/// Flutter tool passes to every build; null when it is not given.
final int? appBuildNumber =
    int.tryParse(const String.fromEnvironment('FLUTTER_BUILD_NUMBER'));

/// [base] pointed at the channel's asset for its game, when there is one
/// this build can install and it is not of older game data than the asset
/// baked in; otherwise [base] itself.
GameDataInstaller withChannel(
  GameDataInstaller base,
  GameDataChannel? channel, {
  int? appBuild,
}) {
  final asset = channel?.assets[base.game];
  if (asset == null || !asset.usableBy(appBuild ?? appBuildNumber)) return base;
  if (asset.url == base.releaseAssetUrl.trim() &&
      asset.sha256.toLowerCase() == base.releaseAssetSha.trim().toLowerCase()) {
    return base;
  }
  final baked = DateTime.tryParse(base.releaseAssetCommitDate.trim());
  final offered = DateTime.tryParse(asset.commitDate);
  if (baked != null && offered != null && offered.isBefore(baked)) return base;
  return GameDataInstaller(
    installDirectory: base.installDirectory,
    releaseAssetUrl: asset.url,
    releaseAssetSha: asset.sha256,
    releaseAssetCommit: asset.commit,
    releaseAssetCommitDate: asset.commitDate,
    game: base.game,
  );
}

/// Where the channel file is (dart-define, set from
/// `tools/release_gamedata.env` by the release build); '' reads nothing.
const String gameDataChannelUrl =
    String.fromEnvironment('ARKLORES_GAMEDATA_CHANNEL_URL');

/// Reads the channel at [url]; null when it cannot be read (no network, no
/// file yet, not the expected shape), which leaves the baked-in assets.
Future<GameDataChannel?> fetchGameDataChannel({
  String url = gameDataChannelUrl,
  http.Client? client,
  Duration timeout = const Duration(seconds: 15),
}) async {
  if (url.trim().isEmpty) return null;
  final http.Client c = client ?? http.Client();
  try {
    final response = await c.get(Uri.parse(url.trim())).timeout(timeout);
    if (response.statusCode != 200) return null;
    return GameDataChannel.parse(utf8.decode(response.bodyBytes));
  } catch (_) {
    return null;
  } finally {
    if (client == null) c.close();
  }
}

/// The channel, read once per app run and again when the knowledge-base
/// page opens or is refreshed (it invalidates this).
final gameDataChannelProvider = FutureProvider<GameDataChannel?>(
  (ref) => fetchGameDataChannel(),
);

class StoryArtPackAsset {
  const StoryArtPackAsset({
    required this.url,
    required this.sha256,
    this.size = 0,
    this.kbCommit = '',
    this.packVersion = 2,
    this.minAppBuild,
  });
  final String url, sha256, kbCommit;
  final int size, packVersion;
  final int? minAppBuild;

  static StoryArtPackAsset? fromJson(Object? value) {
    if (value is! Map) return null;
    String text(String key) =>
        value[key] is String ? (value[key] as String).trim() : '';
    int? number(String key) => int.tryParse('${value[key]}');
    if (text('url').isEmpty || text('sha256').isEmpty) return null;
    return StoryArtPackAsset(
      url: text('url'),
      sha256: text('sha256'),
      size: number('size') ?? 0,
      kbCommit: text('kb_commit'),
      packVersion: number('pack_version') ?? 1,
      minAppBuild: number('min_app_build'),
    );
  }

  /// The pack format this app reads (A.4).
  static const supportedPackVersion = 2;

  /// A pack in a format this app does not read is never offered, whatever
  /// its `min_app_build` says (it would fail the check after the download).
  bool usableBy(int? appBuild) =>
      packVersion == supportedPackVersion &&
      (minAppBuild == null || appBuild == null || appBuild >= minAppBuild!);
}
