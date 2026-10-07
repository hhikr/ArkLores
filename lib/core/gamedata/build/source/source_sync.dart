/// Brings a local source directory up to date for an incremental update of an
/// installed knowledge base.
///
/// The installed database already holds every story, so an update needs only
/// - the changed files between the installed commit and the latest commit
///   (story files, data tables, level files), and
/// - the data tables the importer reads as context (owners, names, zones),
///   about 60 MB, when they are not on disk yet.
///
/// It does not need the 850 MB repository. A marker file records which
/// commit the directory reflects; a directory that is older than the
/// installed database (the database came from a release asset) has its
/// context tables fetched again, so no stale table is read.
///
/// Shared by the app (`gamedata_build_provider.dart`) and the developer tool
/// (`tools/update_gamedata.dart`).
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import 'arknights_source_client.dart';

/// Phases reported while syncing.
enum SourceSyncStage { comparing, contextTables, changedFiles }

/// What a sync found and did.
class SourceSyncResult {
  const SourceSyncResult({
    required this.changes,
    required this.latestSha,
    required this.contextTablesDownloaded,
  });

  /// Files that changed between the installed and the latest commit.
  final List<SourceFileChange> changes;
  final String latestSha;
  final int contextTablesDownloaded;

  SourceChangeSummary get summary => SourceChangeSummary.of(changes);
  bool get upToDate => changes.isEmpty;
}

class SourceSync {
  SourceSync({required this.client, required this.sourceDir});

  final ArknightsSourceClient client;
  final Directory sourceDir;

  File get _marker => File(p.join(sourceDir.path, '.source_commit'));

  /// The commit the files in [sourceDir] reflect, or null when unknown.
  Future<String?> localCommit() async =>
      await _marker.exists() ? (await _marker.readAsString()).trim() : null;

  /// Records that the directory now matches [sha] (call after the update
  /// built successfully).
  Future<void> markSynced(String sha) async {
    await sourceDir.create(recursive: true);
    await _marker.writeAsString(sha, flush: true);
  }

  /// What would change from [installedSha] to [latestSha]; nothing is
  /// downloaded. Throws [GameDataSourceRateLimitedException] and
  /// [GameDataSourceTooManyChangesException] from the compare API.
  Future<List<SourceFileChange>> check({
    required String installedSha,
    required String latestSha,
  }) =>
      client.compareCommits(baseSha: installedSha, headSha: latestSha);

  /// Downloads what an update from [installedSha] to [latestSha] needs.
  Future<SourceSyncResult> sync({
    required String installedSha,
    required String latestSha,
    void Function(SourceSyncStage stage, int done, int total)? onProgress,
  }) async {
    onProgress?.call(SourceSyncStage.comparing, 0, 0);
    final changes = await check(
      installedSha: installedSha,
      latestSha: latestSha,
    );
    if (changes.isEmpty) {
      return SourceSyncResult(
        changes: const [],
        latestSha: latestSha,
        contextTablesDownloaded: 0,
      );
    }

    // A directory that does not reflect the installed commit may hold stale
    // tables (changed before the installed commit but never refreshed).
    final local = await localCommit();
    if (local != null && local != installedSha) {
      for (final path in ArknightsSourcePaths.excelTables) {
        final file = File(p.join(sourceDir.path, path));
        if (await file.exists()) await file.delete();
      }
    }
    await sourceDir.create(recursive: true);

    // Tables the importer reads as context but that did not change are taken
    // at the latest commit (they equal the installed ones).
    final downloaded = await client.ensureContextTables(
      sourceDir: sourceDir,
      sha: latestSha,
      onProgress: (done, total) =>
          onProgress?.call(SourceSyncStage.contextTables, done, total),
    );

    // A few files at a time: an update after weeks of upstream changes is
    // thousands of small files, and one request after another is slow.
    var done = 0;
    var next = 0;
    Future<void> worker() async {
      while (next < changes.length) {
        final change = changes[next++];
        final target = File(p.join(sourceDir.path, change.path));
        final previous = change.previousPath;
        if (change.status == 'renamed' && previous != null) {
          final old = File(p.join(sourceDir.path, previous));
          if (await old.exists()) await old.delete();
        }
        if (change.isRemoval) {
          if (await target.exists()) await target.delete();
        } else {
          await client.downloadFile(
            sha: latestSha,
            path: change.path,
            outputPath: target.path,
          );
        }
        onProgress?.call(SourceSyncStage.changedFiles, ++done, changes.length);
      }
    }

    await Future.wait([for (var i = 0; i < 6; i++) worker()]);
    return SourceSyncResult(
      changes: changes,
      latestSha: latestSha,
      contextTablesDownloaded: downloaded,
    );
  }
}
