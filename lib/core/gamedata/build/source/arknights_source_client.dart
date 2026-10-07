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

import 'dart:async';
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

  /// Repo-relative paths of the excel tables the importer reads: the
  /// operator, handbook and voice tables (dedicated stages) and the tables of
  /// the entry layer (EntryTables.all, 0.11). Gameplay tables (skills,
  /// buildings, shops …) are not imported and not downloaded. The levels/
  /// directory (500 MB, enemy ↔ stage bindings) is read by a complete build
  /// and deleted afterwards; an update follows only the level files that
  /// changed.
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
    'zh_CN/gamedata/excel/activity_table.json',
    'zh_CN/gamedata/excel/retro_table.json',
    'zh_CN/gamedata/excel/roguelike_table.json',
    'zh_CN/gamedata/excel/roguelike_topic_table.json',
    'zh_CN/gamedata/excel/sandbox_table.json',
    'zh_CN/gamedata/excel/sandbox_perm_table.json',
    'zh_CN/gamedata/excel/handbook_team_table.json',
    'zh_CN/gamedata/excel/tip_table.json',
    'zh_CN/gamedata/excel/charm_table.json',
    'zh_CN/gamedata/excel/display_meta_table.json',
    'zh_CN/gamedata/excel/arkvent_table.json',
    'zh_CN/gamedata/excel/ark_odc_table.json',
    // R14: story names / order / synopsis paths for the story catalog;
    // 0.11: the archive documents of the activities.
    'zh_CN/gamedata/excel/story_review_table.json',
    'zh_CN/gamedata/excel/story_review_meta_table.json',
  ];

  static bool isStoryFile(String path) =>
      path.startsWith('$languagePath/gamedata/story/') &&
      path.endsWith('.txt');

  /// A level file (`levels/**.json`): the source of the enemy ↔ stage
  /// bindings. `levels/enemydata/` and `levels_meta.json` are not.
  static bool isLevelFile(String path) =>
      path.startsWith('$languagePath/gamedata/levels/') &&
      path.endsWith('.json') &&
      !path.contains('/levels/enemydata/') &&
      !path.endsWith('/levels_meta.json');

  /// Files an incremental update applies. Changed level files are small
  /// (one stage each), so they are followed even though the whole `levels/`
  /// tree (500 MB) is never pulled.
  static bool isImporterRelevant(String path) =>
      isStoryFile(path) || excelTables.contains(path) || isLevelFile(path);

  /// Files taken from the repository zip of a first-time pull. The level
  /// files come too: without them a complete build has no enemy, trap or
  /// summon bindings and no battle dialogue links, unlike the released
  /// asset. The app removes them after the build (see
  /// `GameDataBuildNotifier`), an update only fetches the ones that change.
  static bool isZipRelevant(String path) => isImporterRelevant(path);
}

/// What an update changes, by kind of file (for the update check and the
/// report after an update).
class SourceChangeSummary {
  const SourceChangeSummary({
    this.storyAdded = 0,
    this.storyChanged = 0,
    this.storyRemoved = 0,
    this.tables = const [],
    this.levelFiles = 0,
  });

  factory SourceChangeSummary.of(Iterable<SourceFileChange> changes) {
    var added = 0, changed = 0, removed = 0, levels = 0;
    final tables = <String>[];
    for (final change in changes) {
      final path = change.path;
      if (ArknightsSourcePaths.isStoryFile(path)) {
        if (change.status == 'added') {
          added++;
        } else if (change.isRemoval) {
          removed++;
        } else {
          changed++;
        }
      } else if (ArknightsSourcePaths.isLevelFile(path)) {
        levels++;
      } else if (ArknightsSourcePaths.excelTables.contains(path)) {
        tables.add(p.posix.basename(path));
      }
    }
    return SourceChangeSummary(
      storyAdded: added,
      storyChanged: changed,
      storyRemoved: removed,
      tables: tables,
      levelFiles: levels,
    );
  }

  final int storyAdded;
  final int storyChanged;
  final int storyRemoved;

  /// File names of the changed data tables.
  final List<String> tables;
  final int levelFiles;

  int get storyFiles => storyAdded + storyChanged + storyRemoved;
  bool get isEmpty => storyFiles == 0 && tables.isEmpty && levelFiles == 0;
}

/// Thrown when an update changes more files than the compare API lists
/// (3000): the incremental result would silently miss some. A full rebuild
/// (or downloading the release asset) is the right way then.
class GameDataSourceTooManyChangesException implements Exception {
  const GameDataSourceTooManyChangesException();

  @override
  String toString() =>
      'The upstream changed more than 3000 files since the installed '
      'knowledge base; rebuild it completely instead of updating it.';
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
  ArknightsSourceClient({http.Client? client, this.githubToken})
      : _client = client ?? http.Client();

  /// Optional GitHub Personal Access Token. When set, API requests are
  /// authenticated (quota raised from 60 to 5000 requests/hour per account).
  /// Stored in OS secure storage; never logged.
  final String? githubToken;
  final http.Client _client;

  static Uri _api(String path, [Map<String, String>? query]) => Uri.https(
        'api.github.com',
        '/repos/${ArknightsSourcePaths.repo}$path',
        query,
      );

  Map<String, String> get _headers {
    final token = githubToken?.trim();
    return {
      'Accept': 'application/vnd.github+json',
      'User-Agent': 'ArkLores',
      if (token != null && token.isNotEmpty)
        'Authorization': 'Bearer $token',
    };
  }

  /// Returns the current commit SHA of the default branch.
  ///
  /// Primary source is the GitHub REST API; on rate limiting (403/429) it
  /// falls back to the commits Atom feed (a non-API endpoint that shares the
  /// egress but is not quota-limited), so the builder keeps working even when
  /// the API quota is exhausted. An invalid token surfaces as HTTP 401 with
  /// an explicit diagnostic instead of a silent fallback.
  Future<String> fetchLatestCommit() async {
    final response = await _client
        .get(
          _api('/commits/${ArknightsSourcePaths.branch}'),
          headers: _headers,
        )
        .timeout(stallTimeout);
    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      final sha = decoded is Map ? decoded['sha'] : null;
      if (sha is String && sha.isNotEmpty) return sha;
    } else if (response.statusCode == 401) {
      throw StateError(
        'GitHub Token is invalid (HTTP 401). Check the token you entered in '
        'the knowledge base settings. ${_shortBody(response.body)}',
      );
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

  /// What changed between [baseSha] and [headSha], limited to the files the
  /// importer reads. Read from the two commits' git trees (the excel, story
  /// and levels folders, by blob hash), not from the compare API: that one
  /// lists at most 300 files, and a range with one big commit (hundreds of
  /// unrelated model files) came back without a single table or story file
  /// while the files existed. A tree diff is exact however large the commits
  /// are, and takes about ten requests.
  ///
  /// Throws [GameDataSourceRateLimitedException] on 403/429 so callers can
  /// fall back to a full zip pull (codeload is not quota-limited), and
  /// [GameDataSourceTooManyChangesException] when the installed commit is
  /// gone from the repository or a folder is too large for one tree response.
  Future<List<SourceFileChange>> compareCommits({
    required String baseSha,
    required String headSha,
  }) async {
    if (baseSha == headSha) return const [];
    final Map<String, String> before;
    try {
      before = await _relevantBlobs(baseSha);
    } on StateError catch (e) {
      // The installed commit no longer exists upstream (history rewritten).
      if ('$e'.contains('HTTP 404')) {
        throw const GameDataSourceTooManyChangesException();
      }
      rethrow;
    }
    final after = await _relevantBlobs(headSha);
    return [
      for (final e in after.entries)
        if (before[e.key] == null)
          SourceFileChange(path: e.key, status: 'added')
        else if (before[e.key] != e.value)
          SourceFileChange(path: e.key, status: 'modified'),
      for (final path in before.keys)
        if (!after.containsKey(path))
          SourceFileChange(path: path, status: 'removed'),
    ];
  }

  /// The importer-relevant files of a commit with their blob hashes.
  Future<Map<String, String>> _relevantBlobs(String commit) async {
    Future<Map<dynamic, dynamic>> tree(String sha, {bool recursive = false}) =>
        _getJson(
          '/git/trees/$sha',
          {if (recursive) 'recursive': '1'},
          'read a GameData tree',
        );
    String? child(Map<dynamic, dynamic> t, String name) {
      for (final e in (t['tree'] as List? ?? const [])) {
        if (e is Map && e['path'] == name && e['type'] == 'tree') {
          return '${e['sha']}';
        }
      }
      return null;
    }

    var node = await tree(commit);
    for (final name in [ArknightsSourcePaths.languagePath, 'gamedata']) {
      final sha = child(node, name);
      if (sha == null) return const {};
      node = await tree(sha);
    }
    final out = <String, String>{};
    for (final dir in const ['excel', 'story', 'levels']) {
      final sha = child(node, dir);
      if (sha == null) continue;
      final sub = await tree(sha, recursive: true);
      if (sub['truncated'] == true) {
        throw const GameDataSourceTooManyChangesException();
      }
      for (final e in (sub['tree'] as List? ?? const [])) {
        if (e is! Map || e['type'] != 'blob') continue;
        final path =
            '${ArknightsSourcePaths.languagePath}/gamedata/$dir/${e['path']}';
        if (ArknightsSourcePaths.isImporterRelevant(path)) {
          out[path] = '${e['sha']}';
        }
      }
    }
    return out;
  }

  Future<Map<dynamic, dynamic>> _getJson(
    String path,
    Map<String, String> query,
    String what,
  ) async {
    final response = await _client
        .get(_api(path, query), headers: _headers)
        .timeout(stallTimeout);
    if (response.statusCode != 200) {
      if (response.statusCode == 401) {
        throw StateError(
          'GitHub Token is invalid (HTTP 401). Check the token you entered '
          'in the knowledge base settings. ${_shortBody(response.body)}',
        );
      }
      if (response.statusCode == 403 || response.statusCode == 429) {
        throw GameDataSourceRateLimitedException(
          'Failed to $what: HTTP ${response.statusCode} (GitHub API rate '
          'limit or blocked egress). Falling back to a full source pull is '
          'recommended. ${_shortBody(response.body)}',
        );
      }
      throw StateError(
        'Failed to $what: HTTP ${response.statusCode}. '
        '${_shortBody(response.body)}',
      );
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw StateError('Unexpected GitHub response: ${response.body}');
    }
    return decoded;
  }

  /// Downloads the data tables the importer reads as context (owners, names,
  /// zones …) that are missing from [sourceDir] at [sha]. An update of an
  /// installed knowledge base does not need the story files or the 850 MB
  /// repository: the database already holds the stories; only these tables
  /// (about 60 MB) and the changed files are needed. Returns how many were
  /// downloaded.
  Future<int> ensureContextTables({
    required Directory sourceDir,
    required String sha,
    void Function(int done, int total)? onProgress,
  }) async {
    final missing = [
      for (final path in ArknightsSourcePaths.excelTables)
        if (!File(p.join(sourceDir.path, path)).existsSync()) path,
    ];
    for (var i = 0; i < missing.length; i++) {
      await downloadFile(
        sha: sha,
        path: missing[i],
        outputPath: p.join(sourceDir.path, missing[i]),
      );
      onProgress?.call(i + 1, missing.length);
    }
    return missing.length;
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
      // Uri.https encodes the path itself (`[uc]info` → `%5Buc%5Dinfo`);
      // encoding it first would escape the percent signs a second time.
      '/${ArknightsSourcePaths.repo}/$sha/$path',
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
        if (rel == null || !ArknightsSourcePaths.isZipRelevant(rel)) {
          continue;
        }
        final outFile = File(p.join(outputDir.path, rel));
        await outFile.parent.create(recursive: true);
        await outFile.writeAsBytes(entry.content as List<int>, flush: true);
      }
    }
  }

  /// A stalled connection (the app was in the background, the network
  /// changed) fails after this long instead of hanging.
  static const Duration stallTimeout = Duration(seconds: 60);

  /// Whole-file attempts; the file is fetched again from the start.
  static const int downloadAttempts = 3;

  Future<void> _downloadToFile(
    Uri uri,
    String outputPath,
    void Function(int receivedBytes, int? totalBytes)? onProgress,
  ) async {
    for (var attempt = 1;; attempt++) {
      try {
        await _downloadOnce(uri, outputPath, onProgress);
        return;
      } on TimeoutException {
        if (attempt >= downloadAttempts) rethrow;
      } on http.ClientException {
        if (attempt >= downloadAttempts) rethrow;
      } on SocketException {
        if (attempt >= downloadAttempts) rethrow;
      }
      await Future<void>.delayed(Duration(seconds: 2 * attempt));
    }
  }

  Future<void> _downloadOnce(
    Uri uri,
    String outputPath,
    void Function(int receivedBytes, int? totalBytes)? onProgress,
  ) async {
    final request = http.Request('GET', uri);
    request.headers.addAll(_headers);
    final response = await _client.send(request).timeout(stallTimeout);
    if (response.statusCode != 200) {
      throw StateError('Download failed: HTTP ${response.statusCode} for $uri');
    }
    final file = File(outputPath);
    await file.parent.create(recursive: true);
    final sink = file.openWrite();
    var received = 0;
    final total = response.contentLength;
    try {
      await for (final chunk in response.stream.timeout(stallTimeout)) {
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(received, total);
      }
    } finally {
      await sink.close();
    }
  }

  static String? _stripTopLevel(String entryName) {
    final parts = entryName.split('/');
    if (parts.length <= 1) return null;
    return parts.sublist(1).join('/');
  }

  /// First 200 chars of a response body, for diagnostics.
  String _shortBody(String body) {
    final compact = body.replaceAll(RegExp(r'\s+'), ' ').trim();
    return compact.length <= 200
        ? compact
        : '${compact.substring(0, 200)}…';
  }
}
