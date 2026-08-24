/// GitHub source client for the in-app GameData builder (R2).
///
/// Pulls the importer-relevant subset of Kengxxiao/ArknightsGameData:
///
/// - first-time pull: one codeload zip download + whitelist-filtered
///   extraction (the importer only needs ~168 MB out of the ~945 MB `zh_CN`
///   tree, so non-whitelisted entries are skipped during extraction);
/// - incremental updates: `compare` API between the installed commit and the
///   latest commit, then raw downloads of the changed whitelisted files.
///
/// Pure Dart (http + archive); no platform channels, safe to run in a
/// background isolate. Network access to GitHub is required.
library;

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

/// Source repository coordinates and the importer whitelist.
class ArknightsSourcePaths {
  ArknightsSourcePaths._();

  static const String repo = 'Kengxxiao/ArknightsGameData';
  static const String branch = 'master';
  static const String languagePath = 'zh_CN';

  /// Repo-relative paths of the excel tables the importer reads. The three
  /// character tables are handled by dedicated stages; the rest map to the
  /// 15-table structured spec list.
  static const List<String> excelTables = [
    'zh_CN/gamedata/excel/character_table.json',
    'zh_CN/gamedata/excel/handbook_info_table.json',
    'zh_CN/gamedata/excel/charword_table.json',
    'zh_CN/gamedata/excel/item_table.json',
    'zh_CN/gamedata/excel/skin_table.json',
    'zh_CN/gamedata/excel/medal_table.json',
    'zh_CN/gamedata/excel/uniequip_table.json',
    'zh_CN/gamedata/excel/enemy_handbook_table.json',
    'zh_CN/gamedata/excel/stage_table.json',
    'zh_CN/gamedata/excel/zone_table.json',
    'zh_CN/gamedata/excel/campaign_table.json',
    'zh_CN/gamedata/excel/activity_table.json',
    'zh_CN/gamedata/excel/retro_table.json',
    'zh_CN/gamedata/excel/mission_table.json',
    'zh_CN/gamedata/excel/roguelike_table.json',
    'zh_CN/gamedata/excel/roguelike_topic_table.json',
    'zh_CN/gamedata/excel/sandbox_table.json',
    'zh_CN/gamedata/excel/sandbox_perm_table.json',
  ];

  static bool isStoryFile(String path) =>
      path.startsWith('$languagePath/gamedata/story/') &&
      path.endsWith('.txt');

  static bool isImporterRelevant(String path) =>
      isStoryFile(path) || excelTables.contains(path);
}

/// One changed file reported by the GitHub compare API.
class SourceFileChange {
  const SourceFileChange({
    required this.path,
    required this.status,
    this.previousPath,
  });
  final String path;

  /// added | modified | removed | renamed
  final String status;
  final String? previousPath;

  bool get isRemoval => status == 'removed';

  /// Paths that need row deletion before re-import (the old path for
  /// renames, or the path itself).
  List<String> get stalePaths => [
        if (status == 'renamed' && previousPath != null) previousPath!,
        if (status != 'renamed') path,
      ];
}

/// Thrown when the GitHub REST API is rate-limited or blocked (HTTP 403/429).
///
/// GitHub's unauthenticated API quota (60 requests/hour per IP) is often
/// exhausted on shared proxy egress IPs. Callers may fall back to non-API
/// endpoints (atom feed, codeload zip) which are not quota-limited.
class GameDataSourceRateLimitedException implements Exception {
  const GameDataSourceRateLimitedException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// GitHub client for the ArknightsGameData source.
class ArknightsSourceClient {
  ArknightsSourceClient({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;

  static Uri _api(String path, [Map<String, String>? query]) => Uri.https(
        'api.github.com',
        '/repos/${ArknightsSourcePaths.repo}$path',
        query,
      );

  /// Returns the current commit SHA of the default branch.
  ///
  /// Primary source is the GitHub REST API; on rate limiting (403/429) it
  /// falls back to the commits Atom feed (a non-API endpoint that shares the
  /// egress but is not quota-limited), so the builder keeps working even when
  /// the API quota is exhausted.
  Future<String> fetchLatestCommit() async {
    final response = await _client.get(
      _api('/commits/${ArknightsSourcePaths.branch}'),
      headers: _headers,
    );
    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      final sha = decoded is Map ? decoded['sha'] : null;
      if (sha is String && sha.isNotEmpty) return sha;
    } else if (response.statusCode == 403 || response.statusCode == 429) {
      final atomSha = await _latestShaFromAtomFeed();
      if (atomSha != null) return atomSha;
      throw StateError(
        'Failed to fetch latest GameData commit: HTTP '
        '${response.statusCode} (GitHub API rate limit or blocked egress; '
        'atom feed also failed). ${_shortBody(response.body)}',
      );
    }
    throw StateError(
      'Failed to fetch latest GameData commit: HTTP '
      '${response.statusCode}. ${_shortBody(response.body)}',
    );
  }

  /// Parses the newest commit SHA from `commits/<branch>.atom` (non-API).
  Future<String?> _latestShaFromAtomFeed() async {
    final uri = Uri.https(
      'github.com',
      '/${ArknightsSourcePaths.repo}/commits/${ArknightsSourcePaths.branch}.atom',
    );
    try {
      final response = await _client.get(uri, headers: _headers);
      if (response.statusCode != 200) return null;
      final match = RegExp(r'Grit::Commit/([0-9a-f]{40})').firstMatch(
        response.body,
      );
      return match?.group(1);
    } catch (_) {
      return null;
    }
  }

  /// Compares [baseSha]..[headSha] and returns the changed files that are
  /// importer-relevant. Handles the compare API file pagination (page size
  /// capped at 300 files per response).
  ///
  /// Throws [GameDataSourceRateLimitedException] on 403/429 so callers can
  /// fall back to a full zip pull (codeload is not quota-limited).
  Future<List<SourceFileChange>> compareCommits({
    required String baseSha,
    required String headSha,
  }) async {
    if (baseSha == headSha) return const [];
    final changes = <SourceFileChange>[];
    const perPage = 100;
    var page = 1;
    while (true) {
      final response = await _client.get(
        _api(
          '/compare/$baseSha...$headSha',
          {'per_page': '$perPage', 'page': '$page'},
        ),
        headers: _headers,
      );
      if (response.statusCode != 200) {
        if (response.statusCode == 403 || response.statusCode == 429) {
          throw GameDataSourceRateLimitedException(
            'Failed to compare GameData commits: HTTP '
            '${response.statusCode} (GitHub API rate limit or blocked '
            'egress). Falling back to a full source pull is recommended. '
            '${_shortBody(response.body)}',
          );
        }
        throw StateError(
          'Failed to compare GameData commits: HTTP '
          '${response.statusCode}. ${_shortBody(response.body)}',
        );
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) {
        throw StateError('Unexpected compare response: ${response.body}');
      }
      final files = decoded['files'];
      if (files is! List || files.isEmpty) break;
      for (final raw in files) {
        if (raw is! Map) continue;
        final path = '${raw['filename'] ?? ''}';
        final status = '${raw['status'] ?? ''}';
        final previous = '${raw['previous_filename'] ?? ''}';
        if (!ArknightsSourcePaths.isImporterRelevant(path) &&
            (previous.isEmpty ||
                !ArknightsSourcePaths.isImporterRelevant(previous))) {
          continue;
        }
        changes.add(
          SourceFileChange(
            path: path,
            status: status,
            previousPath: previous.isEmpty ? null : previous,
          ),
        );
      }
      if (files.length < perPage) break;
      page++;
    }
    return changes;
  }

  /// Downloads one repo file at [sha] into [outputPath].
  Future<void> downloadFile({
    required String sha,
    required String path,
    required String outputPath,
    void Function(int receivedBytes, int? totalBytes)? onProgress,
  }) async {
    final uri = Uri.https(
      'raw.githubusercontent.com',
      '/${ArknightsSourcePaths.repo}/$sha/${_encodePath(path)}',
    );
    await _downloadToFile(uri, outputPath, onProgress);
  }

  /// Downloads the full-repo zip at [sha] into [outputPath] (first-time pull).
  Future<void> downloadZip({
    required String sha,
    required String outputPath,
    void Function(int receivedBytes, int? totalBytes)? onProgress,
  }) async {
    final uri = Uri.https(
      'codeload.github.com',
      '/${ArknightsSourcePaths.repo}/zip/$sha',
    );
    await _downloadToFile(uri, outputPath, onProgress);
  }

  /// Extracts only importer-relevant entries from [zipPath] into [outputDir].
  ///
  /// Codeload zips contain a top-level directory named
  /// `ArknightsGameData-<sha>/`; it is stripped from entry paths. Entries
  /// outside the whitelist are skipped, so the on-device source tree stays at
  /// the ~168 MB subset instead of the full ~945 MB tree.
  ///
  /// CPU/memory heavy (the decoder materializes the zip); callers should run
  /// it in a background isolate, e.g. `Isolate.run`.
  static Future<void> extractWhitelistedZip({
    required String zipPath,
    required Directory outputDir,
  }) async {
    final bytes = await File(zipPath).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);
    await outputDir.create(recursive: true);
    for (final entry in archive) {
      if (entry.isFile) {
        final rel = _stripTopLevel(entry.name);
        if (rel == null || !ArknightsSourcePaths.isImporterRelevant(rel)) {
          continue;
        }
        final outFile = File(p.join(outputDir.path, rel));
        await outFile.parent.create(recursive: true);
        await outFile.writeAsBytes(entry.content as List<int>, flush: true);
      }
    }
  }

  Future<void> _downloadToFile(
    Uri uri,
    String outputPath,
    void Function(int receivedBytes, int? totalBytes)? onProgress,
  ) async {
    final request = http.Request('GET', uri);
    request.headers.addAll(_headers);
    final response = await _client.send(request);
    if (response.statusCode != 200) {
      throw StateError('Download failed: HTTP ${response.statusCode} for $uri');
    }
    final file = File(outputPath);
    await file.parent.create(recursive: true);
    final sink = file.openWrite();
    var received = 0;
    final total = response.contentLength;
    await for (final chunk in response.stream) {
      sink.add(chunk);
      received += chunk.length;
      onProgress?.call(received, total);
    }
    await sink.close();
  }

  static String? _stripTopLevel(String entryName) {
    final parts = entryName.split('/');
    if (parts.length <= 1) return null;
    return parts.sublist(1).join('/');
  }

  String _encodePath(String path) =>
      path.split('/').map(Uri.encodeComponent).join('/');

  /// First 200 chars of a response body, for diagnostics.
  String _shortBody(String body) {
    final compact = body.replaceAll(RegExp(r'\s+'), ' ').trim();
    return compact.length <= 200
        ? compact
        : '${compact.substring(0, 200)}…';
  }

  static const _headers = {
    'Accept': 'application/vnd.github+json',
    'User-Agent': 'ArkLores',
  };
}
