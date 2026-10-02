/// Background-isolate execution of the in-app GameData build (R2).
///
/// The build runs inside a spawned isolate using the pure-FFI SQLite backend
/// (no platform channels), so the UI stays responsive during a long build.
/// Progress and completion are streamed back over a [ReceivePort]. Cancel is
/// implemented as [Isolate.kill] followed by temp-file cleanup in the caller;
/// the installed database is never touched until the validated swap.
library;

import 'dart:isolate';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'gamedata_build_service.dart';
import 'source/arknights_source_client.dart';

/// Events emitted by the build isolate.
enum GameDataBuildEventType { progress, done, error, cancelled }

class GameDataBuildEvent {
  const GameDataBuildEvent({
    required this.type,
    this.stage = '',
    this.done = 0,
    this.total = 0,
    this.outputPath,
    this.incremental = false,
    this.message,
    this.stats = const {},
  });
  final GameDataBuildEventType type;
  final String stage;
  final int done;
  final int total;
  final String? outputPath;
  final bool incremental;
  final String? message;
  final Map<String, int> stats;

  static GameDataBuildEvent fromMap(Object? raw) {
    if (raw is! Map) {
      return const GameDataBuildEvent(
        type: GameDataBuildEventType.error,
        message: 'Unexpected build event',
      );
    }
    final type = switch ('${raw['type']}') {
      'progress' => GameDataBuildEventType.progress,
      'done' => GameDataBuildEventType.done,
      'cancelled' => GameDataBuildEventType.cancelled,
      _ => GameDataBuildEventType.error,
    };
    return GameDataBuildEvent(
      type: type,
      stage: '${raw['stage'] ?? ''}',
      done: (raw['done'] as num?)?.toInt() ?? 0,
      total: (raw['total'] as num?)?.toInt() ?? 0,
      outputPath: raw['outputPath'] as String?,
      incremental: raw['incremental'] == true,
      message: raw['message'] as String?,
      stats: {
        for (final entry in ((raw['stats'] as Map?) ?? const {}).entries)
          if (entry.value is num) '${entry.key}': (entry.value as num).toInt(),
      },
    );
  }
}

/// Runs one build in a background isolate. Create, call [start], listen to
/// [events], and call [kill] to abort.
class GameDataBuildRunner {
  ReceivePort? _eventsPort;
  Isolate? _isolate;

  /// Stream of decoded build events. Listen after [start].
  Stream<GameDataBuildEvent> get events {
    _eventsPort ??= ReceivePort();
    return _eventsPort!.asBroadcastStream().map(GameDataBuildEvent.fromMap);
  }

  Future<void> start(GameDataBuildOptions options) async {
    _eventsPort ??= ReceivePort();
    _isolate = await Isolate.spawn(
      gameDataBuildIsolateMain,
      {
        'sourceDir': options.sourceDir,
        'outputDbPath': options.outputDbPath,
        'existingDbPath': options.existingDbPath,
        'commitSha': options.commitSha,
        'changes': [
          for (final change in options.changedFiles)
            [
              change.path,
              change.status,
              change.previousPath,
            ],
        ],
        'sendPort': _eventsPort!.sendPort,
      },
    );
  }

  /// Terminates the build isolate immediately. The caller is responsible for
  /// cleaning up temp files; the installed database is never modified by the
  /// build itself.
  void kill() {
    _isolate?.kill();
    _isolate = null;
  }
}

/// Top-level isolate entry. Receives build parameters plus a [SendPort] for
/// events.
void gameDataBuildIsolateMain(Map<String, Object?> params) async {
  // The FFI factory must be initialized inside the isolate that uses it.
  sqfliteFfiInit();
  final sendPort = params['sendPort'] as SendPort;

  void progress(String stage, int done, int total) {
    sendPort.send({
      'type': 'progress',
      'stage': stage,
      'done': done,
      'total': total,
    });
  }

  try {
    final changes = <SourceFileChange>[];
    for (final raw in (params['changes'] as List? ?? const [])) {
      if (raw is! List || raw.isEmpty) continue;
      final path = '${raw[0]}';
      final status = raw.length > 1 ? '${raw[1]}' : 'modified';
      final previous = raw.length > 2 && raw[2] != null ? '${raw[2]}' : null;
      changes.add(
        SourceFileChange(
          path: path,
          status: status,
          previousPath: previous,
        ),
      );
    }

    final options = GameDataBuildOptions(
      sourceDir: '${params['sourceDir']}',
      outputDbPath: '${params['outputDbPath']}',
      commitSha: '${params['commitSha']}',
      existingDbPath: params['existingDbPath'] as String?,
      changedFiles: changes,
    );
    final result = await GameDataBuildService().build(
      options,
      onProgress: progress,
    );
    sendPort.send({
      'type': 'done',
      'outputPath': result.outputDbPath,
      'incremental': result.incremental,
      'stats': result.stats.toJson(),
    });
  } catch (error) {
    sendPort.send({'type': 'error', 'message': '$error'});
  }
}
