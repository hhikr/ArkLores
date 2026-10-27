/// In-app update: the app's releases on GitHub (`hhikr/ArkLores`), the
/// newest APK downloaded to the cache, checked against its `.sha256` and
/// handed to Android's package installer ([AppInstaller]).
///
/// A release is an app release when its tag is `v<x>.<y>.<z>`, it is neither
/// a draft nor a pre-release and it carries `ArkLores-<x.y.z>.apk` and that
/// file's `.sha256` (`tools/release_app.ps1`). The knowledge-base release
/// (`gamedata-channel`) and anything else are skipped. Versions compare as
/// three numbers; the release does not say its Android build number, and
/// every release raises the version.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../../shared/app_version.dart';
import '../gamedata/resumable_download.dart';

/// The app's releases, newest first (the knowledge-base release among them).
final Uri appReleasesUrl = Uri.parse(
  'https://api.github.com/repos/hhikr/ArkLores/releases?per_page=30',
);

/// `v0.19.1` or `0.19.1` as three numbers; null for anything else.
List<int>? parseAppVersion(String text) {
  final match = RegExp(r'^v?(\d+)\.(\d+)\.(\d+)$').firstMatch(text.trim());
  if (match == null) return null;
  return [for (var i = 1; i <= 3; i++) int.parse(match.group(i)!)];
}

/// Negative when [a] is older than [b], 0 when the same, positive when newer.
int compareAppVersions(List<int> a, List<int> b) {
  for (var i = 0; i < 3; i++) {
    final d = a[i].compareTo(b[i]);
    if (d != 0) return d;
  }
  return 0;
}

/// One app release on GitHub.
class AppRelease {
  const AppRelease({
    required this.tag,
    required this.version,
    required this.notes,
    required this.apkName,
    required this.apkUrl,
    required this.apkSize,
    required this.shaUrl,
    this.pageUrl,
  });

  final String tag;
  final List<int> version;

  /// The release notes (Markdown, as written for the release page).
  final String notes;
  final String apkName;
  final String apkUrl;
  final int apkSize;
  final String shaUrl;
  final String? pageUrl;

  String get versionName => version.join('.');

  /// The start of [notes] as plain lines: headings, list marks and emphasis
  /// dropped, at most [maxChars] characters.
  String notesExcerpt({int maxChars = 280}) {
    final lines = <String>[];
    for (final raw in const LineSplitter().convert(notes)) {
      var line = raw.trim();
      if (line.isEmpty) continue;
      line = line
          .replaceFirst(RegExp(r'^#+\s*'), '')
          .replaceFirst(RegExp(r'^[-*+]\s+'), '· ')
          .replaceAll(RegExp(r'\*\*|__|`'), '')
          .replaceAllMapped(
            RegExp(r'\[([^\]]*)\]\([^)]*\)'),
            (m) => m.group(1)!,
          );
      if (line.isNotEmpty) lines.add(line);
    }
    final text = lines.join('\n');
    if (text.length <= maxChars) return text;
    return '${text.substring(0, maxChars).trimRight()}…';
  }

  /// [json] as an app release, or null when it is not one.
  static AppRelease? fromJson(Object? json) {
    if (json is! Map) return null;
    if (json['draft'] == true || json['prerelease'] == true) return null;
    final tag = json['tag_name']?.toString() ?? '';
    if (!RegExp(r'^v\d+\.\d+\.\d+$').hasMatch(tag)) return null;
    final version = parseAppVersion(tag);
    if (version == null) return null;
    final name = 'ArkLores-${version.join('.')}.apk';
    Map<Object?, Object?>? asset(String fileName) {
      final assets = json['assets'];
      if (assets is! List) return null;
      for (final a in assets) {
        if (a is Map && a['name'] == fileName) return a;
      }
      return null;
    }

    final apk = asset(name);
    final sha = asset('$name.sha256');
    final apkUrl = apk?['browser_download_url']?.toString() ?? '';
    final shaUrl = sha?['browser_download_url']?.toString() ?? '';
    if (apkUrl.isEmpty || shaUrl.isEmpty) return null;
    final size = apk!['size'];
    return AppRelease(
      tag: tag,
      version: version,
      notes: json['body']?.toString() ?? '',
      apkName: name,
      apkUrl: apkUrl,
      apkSize: size is int ? size : int.tryParse('$size') ?? 0,
      shaUrl: shaUrl,
      pageUrl: json['html_url']?.toString(),
    );
  }
}

/// The newest app release in a releases listing ([json] as GitHub gives
/// it), by version; null when there is none.
AppRelease? pickLatestAppRelease(Object? json) {
  if (json is! List) return null;
  AppRelease? best;
  for (final item in json) {
    final release = AppRelease.fromJson(item);
    if (release == null) continue;
    if (best == null || compareAppVersions(release.version, best.version) > 0) {
      best = release;
    }
  }
  return best;
}

/// The SHA-256 in a `.sha256` file (`<hex>  <file name>`); null when there
/// is none.
String? parseSha256File(String text) =>
    RegExp(r'\b[0-9a-fA-F]{64}\b').firstMatch(text)?.group(0)?.toLowerCase();

/// Why an update step failed, for the page to word.
enum AppUpdateFailure {
  /// The releases could not be read (network, rate limit, bad answer).
  check,

  /// The APK or its checksum could not be downloaded.
  download,

  /// The downloaded APK is not the one the release names.
  checksum,

  /// The package installer could not be opened.
  install,
}

class AppUpdateException implements Exception {
  const AppUpdateException(this.failure, [this.detail]);

  final AppUpdateFailure failure;
  final Object? detail;

  @override
  String toString() => 'AppUpdateException(${failure.name}: $detail)';
}

/// Reads the releases and downloads an APK.
class AppUpdater {
  AppUpdater({
    http.Client Function()? client,
    Future<Directory> Function()? cacheDirectory,
    Uri? releasesUrl,
    this.connectTimeout = const Duration(seconds: 30),
    this.stallTimeout = const Duration(seconds: 60),
    this.maxAttempts = 4,
    this.retryDelay = const Duration(seconds: 3),
  })  : _client = client ?? http.Client.new,
        _cacheDirectory = cacheDirectory ?? getTemporaryDirectory,
        releasesUrl = releasesUrl ?? appReleasesUrl;

  final http.Client Function() _client;
  final Future<Directory> Function() _cacheDirectory;
  final Uri releasesUrl;
  final Duration connectTimeout;
  final Duration stallTimeout;
  final int maxAttempts;
  final Duration retryDelay;

  static const _headers = {
    'Accept': 'application/vnd.github+json',
    'User-Agent': 'ArkLores/$appVersion',
  };

  /// The newest app release; null when there is none.
  Future<AppRelease?> latest() async {
    final client = _client();
    try {
      final response = await client
          .get(releasesUrl, headers: _headers)
          .timeout(connectTimeout);
      if (response.statusCode != 200) {
        throw AppUpdateException(
          AppUpdateFailure.check,
          'HTTP ${response.statusCode}',
        );
      }
      final latest =
          pickLatestAppRelease(jsonDecode(utf8.decode(response.bodyBytes)));
      if (latest == null) {
        throw const AppUpdateException(
          AppUpdateFailure.check,
          'No app release',
        );
      }
      return latest;
    } on AppUpdateException {
      rethrow;
    } catch (e) {
      throw AppUpdateException(AppUpdateFailure.check, e);
    } finally {
      client.close();
    }
  }

  /// The SHA-256 the release gives for its APK.
  Future<String> expectedSha(
    AppRelease release, {
    GameDataDownloadToken? cancelToken,
  }) async {
    if (cancelToken?.cancelled ?? false) {
      throw const GameDataDownloadCancelled();
    }
    final client = _client();
    cancelToken?.attachClient(client);
    try {
      final request = client.get(
        Uri.parse(release.shaUrl),
        headers: {
          'User-Agent': _headers['User-Agent']!,
        },
      ).timeout(connectTimeout);
      final response = await Future.any([
        request,
        if (cancelToken != null)
          cancelToken.whenCancelled.then<http.Response>(
            (_) => throw const GameDataDownloadCancelled(),
          ),
      ]);
      final sha = response.statusCode == 200
          ? parseSha256File(
              utf8.decode(response.bodyBytes, allowMalformed: true),
            )
          : null;
      if (sha == null) {
        throw AppUpdateException(
          AppUpdateFailure.download,
          'no checksum (HTTP ${response.statusCode})',
        );
      }
      return sha;
    } on GameDataDownloadCancelled {
      rethrow;
    } on AppUpdateException {
      rethrow;
    } catch (e) {
      throw AppUpdateException(AppUpdateFailure.download, e);
    } finally {
      cancelToken?.attachClient(null);
      client.close();
    }
  }

  /// Where downloaded APKs are kept (the app's cache, `updates/`; the
  /// Android shell shares this folder with the installer).
  Future<Directory> updatesDirectory() async =>
      Directory('${(await _cacheDirectory()).path}/updates');

  /// Downloads [release]'s APK (resuming a partial file) and checks it
  /// against the release's SHA-256. Other files in the folder (older
  /// versions) are removed. A file that does not match is deleted and
  /// [AppUpdateFailure.checksum] thrown.
  Future<File> download(
    AppRelease release, {
    GameDataDownloadToken? cancelToken,
    void Function(int received, int? total)? onProgress,
    void Function()? onVerifying,
  }) async {
    final sha = await expectedSha(release, cancelToken: cancelToken);
    final dir = await updatesDirectory();
    await dir.create(recursive: true);
    final apk = File('${dir.path}/${release.apkName}');
    final part = File('${apk.path}.download');
    final key = File('${part.path}.key');
    await for (final entry in dir.list()) {
      final name = entry.uri.pathSegments.lastWhere((s) => s.isNotEmpty);
      if (!name.startsWith(release.apkName)) {
        await entry.delete(recursive: true).catchError((Object _) => entry);
      }
    }
    if (await apk.exists()) {
      onVerifying?.call();
      if (await _sha(apk) == sha) {
        if (cancelToken?.cancelled ?? false) {
          throw const GameDataDownloadCancelled();
        }
        return apk;
      }
      await apk.delete();
    }
    if (await part.exists() &&
        (!await key.exists() || await key.readAsString() != sha)) {
      await part.delete();
    }
    await key.writeAsString(sha, flush: true);
    for (var attempt = 1;; attempt++) {
      if (cancelToken?.cancelled ?? false) {
        throw const GameDataDownloadCancelled();
      }
      final client = _client();
      cancelToken?.attachClient(client);
      try {
        await downloadResumable(
          client,
          Uri.parse(release.apkUrl),
          part,
          connectTimeout: connectTimeout,
          stallTimeout: stallTimeout,
          cancelToken: cancelToken,
          onProgress: onProgress,
        );
        break;
      } catch (e) {
        if (cancelToken?.cancelled ?? false) {
          throw const GameDataDownloadCancelled();
        }
        if (e is GameDataDownloadCancelled) rethrow;
        if (attempt >= maxAttempts || !isTransientNetworkError(e)) {
          throw AppUpdateException(AppUpdateFailure.download, e);
        }
        await Future.any([
          Future<void>.delayed(retryDelay * attempt),
          if (cancelToken != null) cancelToken.whenCancelled,
        ]);
      } finally {
        cancelToken?.attachClient(null);
        client.close();
      }
    }
    onVerifying?.call();
    if (cancelToken?.cancelled ?? false) {
      throw const GameDataDownloadCancelled();
    }
    if (await _sha(part) != sha) {
      await part.delete();
      await key.delete().catchError((Object _) => key);
      throw const AppUpdateException(AppUpdateFailure.checksum);
    }
    if (cancelToken?.cancelled ?? false) {
      throw const GameDataDownloadCancelled();
    }
    await part.rename(apk.path);
    await key.delete().catchError((Object _) => key);
    return apk;
  }

  static Future<String> _sha(File file) async =>
      (await sha256.bind(file.openRead()).first).toString();
}

/// Android's package installer, through the shell (`MainActivity`).
class AppInstaller {
  AppInstaller({MethodChannel? channel, bool? enabled})
      : _channel = channel ?? const MethodChannel(channelName),
        supported = enabled ?? Platform.isAndroid;

  static const channelName = 'arklores/app_update';

  final MethodChannel _channel;

  /// Whether the app can install its own update here (Android only).
  final bool supported;

  /// Whether the system lets the app install packages ("install unknown
  /// apps" for this app, Android 8+).
  Future<bool> canInstall() async {
    if (!supported) return false;
    try {
      return await _channel.invokeMethod<bool>('canInstall') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Opens the system's "install unknown apps" page for this app.
  Future<void> openInstallSettings() async {
    if (!supported) return;
    try {
      await _channel.invokeMethod<void>('openInstallSettings');
    } on PlatformException catch (e) {
      throw AppUpdateException(AppUpdateFailure.install, e);
    } on MissingPluginException catch (e) {
      throw AppUpdateException(AppUpdateFailure.install, e);
    }
  }

  /// Hands [apk] to the package installer, which asks the user.
  Future<void> install(File apk) async {
    try {
      await _channel.invokeMethod<void>('install', {'path': apk.path});
    } on PlatformException catch (e) {
      throw AppUpdateException(AppUpdateFailure.install, e);
    } on MissingPluginException catch (e) {
      throw AppUpdateException(AppUpdateFailure.install, e);
    }
  }
}
