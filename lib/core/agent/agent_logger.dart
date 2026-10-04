import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Agent session logger (debug AND release, user-controlled).
///
/// Writes a human-readable log of every ReAct session to the same user-visible
/// area as the GameData database:
///   Android external storage → agent_logs/session_[timestamp].log
///   Other:                    [Documents]/ArkLores/agent_logs/
///
/// Since R4 the logger is active in release builds too, but only when the user
/// enables it in Settings ("保存 AI 会话日志"); it defaults to OFF. The
/// setting is applied at startup via [AgentLogger.setEnabled] and on toggle.
///
/// Privacy constraints (kept in every build mode):
/// - Queries and model/observation content are truncated before writing so the
///   app never persists full user questions, full model reasoning, or full
///   GameData excerpts.
/// - Old log files are pruned automatically (see [_maxLogFiles]); apps can
///   also call [clearLogs] to wipe all agent logs.
class AgentLogger {
  AgentLogger(this._userQuery, {String agentName = 'ReAct'})
      : _agentName = agentName,
        _startTime = DateTime.now() {
    _header();
  }

  final StringBuffer _buf = StringBuffer();
  final DateTime _startTime;
  final String _userQuery;
  final String _agentName;

  static const int _maxQueryChars = 200;
  static const int _maxContentChars = 2000;
  static const int _maxLogFiles = 20;

  static bool _enabled = false;

  /// Logging is off by default; [setEnabled] is called from Settings when the
  /// user toggles "保存 AI 会话日志" (persisted via SettingsService).
  static bool get isEnabled => _enabled;

  /// Turns session logging on/off at runtime (user setting).
  static void setEnabled(bool value) => _enabled = value;

  static String _truncate(String text, int maxChars) {
    if (text.length <= maxChars) return text;
    final cut = text.substring(0, maxChars);
    return '$cut\n…[truncated ${text.length - maxChars} chars]';
  }

  void _header() {
    _buf.writeln('═' * 72);
    _buf.writeln('ArkLores Agent Debug Log');
    _buf.writeln('Agent  : $_agentName');
    _buf.writeln('Time   : ${_startTime.toIso8601String()}');
    _buf.writeln('Query  : ${_truncate(_userQuery, _maxQueryChars)}');
    _buf.writeln('═' * 72);
    _buf.writeln();
  }

  void logIteration(int iteration) {
    if (!isEnabled) return;
    _buf.writeln('─' * 60);
    _buf.writeln('[Iteration $iteration]');
    _buf.writeln();
  }

  void logRawResponse(String response) {
    if (!isEnabled) return;
    _buf.writeln('▶ RAW LLM RESPONSE:');
    _buf.writeln(_truncate(response, _maxContentChars));
    _buf.writeln();
  }

  void logParsed({
    required String thought,
    required String action,
    required String actionInput,
    required String finalAnswer,
  }) {
    if (!isEnabled) return;
    _buf.writeln('▶ PARSED:');
    _buf.writeln('  Thought     : ${_truncate(thought, _maxContentChars)}');
    _buf.writeln('  Action      : $action');
    _buf.writeln(
      '  Action Input: ${_truncate(actionInput, _maxContentChars)}',
    );
    _buf.writeln('  Final Answer: ${_truncate(finalAnswer, _maxContentChars)}');
    _buf.writeln();
  }

  void logToolCall(String toolName, Map<String, dynamic> args) {
    if (!isEnabled) return;
    _buf.writeln('▶ TOOL CALL: $toolName');
    _buf.writeln('  Args: ${_truncate(args.toString(), _maxContentChars)}');
    _buf.writeln();
  }

  void logObservation(String observation) {
    if (!isEnabled) return;
    _buf.writeln('▶ OBSERVATION:');
    _buf.writeln(_truncate(observation, _maxContentChars));
    _buf.writeln();
  }

  void logToolDiagnostics(String diagnostics) {
    if (!isEnabled || diagnostics.trim().isEmpty) return;
    _buf.writeln('▶ TOOL DIAGNOSTICS:');
    _buf.writeln(_truncate(diagnostics.trim(), _maxContentChars));
    _buf.writeln();
  }

  void logFinalAnswer(String answer) {
    if (!isEnabled) return;
    _buf.writeln('─' * 60);
    _buf.writeln('▶ FINAL ANSWER:');
    _buf.writeln(_truncate(answer, _maxContentChars));
    _buf.writeln();
  }

  void logError(String error) {
    if (!isEnabled) return;
    _buf.writeln('▶ ERROR: ${_truncate(error, _maxContentChars)}');
    _buf.writeln();
  }

  void logFallback(String prompt, String response) {
    if (!isEnabled) return;
    _buf.writeln('▶ FALLBACK PROMPT: ${_truncate(prompt, _maxContentChars)}');
    _buf.writeln('▶ FALLBACK RESPONSE:');
    _buf.writeln(_truncate(response, _maxContentChars));
    _buf.writeln();
  }

  /// Writes the log file to the most accessible directory on this platform.
  ///
  /// Android: /sdcard/Android/data/[pkg]/files/agent_logs/
  /// Other:   [Documents]/ArkLores/agent_logs/
  Future<String?> flush() async {
    if (!isEnabled) return null;

    final elapsed = DateTime.now().difference(_startTime);
    _buf.writeln('═' * 72);
    _buf.writeln('Session complete. Elapsed: ${elapsed.inMilliseconds}ms');
    _buf.writeln('═' * 72);

    try {
      final logDir = await _logDirectory();
      await logDir.create(recursive: true);

      final ts = _startTime
          .toIso8601String()
          .replaceAll(':', '-')
          .replaceAll('.', '-');
      final file = File(p.join(logDir.path, 'session_$ts.log'));
      await file.writeAsString(_buf.toString(), flush: true);
      await _pruneOldLogs(logDir);

      debugPrint('[AgentLogger] Log saved to: ${file.path}');
      return file.path;
    } on MissingPluginException {
      final logDir = Directory(
        p.join(Directory.systemTemp.path, 'ArkLores', 'agent_logs'),
      );
      await logDir.create(recursive: true);

      final ts = _startTime
          .toIso8601String()
          .replaceAll(':', '-')
          .replaceAll('.', '-');
      final file = File(p.join(logDir.path, 'session_$ts.log'));
      await file.writeAsString(_buf.toString(), flush: true);
      await _pruneOldLogs(logDir);

      debugPrint(
        '[AgentLogger] Plugin unavailable, log saved to temp: ${file.path}',
      );
      return file.path;
    } catch (e) {
      debugPrint('[AgentLogger] Failed to write log: $e');
      return null;
    }
  }

  Future<Directory> _logDirectory() async {
    if (Platform.isAndroid) {
      final external = await getExternalStorageDirectory();
      if (external != null) {
        return Directory(p.join(external.path, 'agent_logs'));
      }
    }
    final docs = await getApplicationDocumentsDirectory();
    return Directory(p.join(docs.path, 'ArkLores', 'agent_logs'));
  }

  /// Keeps only the [_maxLogFiles] most recent session logs, deleting the
  /// oldest ones so debug storage cannot grow without bound.
  Future<void> _pruneOldLogs(Directory logDir) async {
    try {
      final logs = logDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.log'))
          .toList()
        ..sort((a, b) => a.statSync().modified.compareTo(b.statSync().modified));
      final overflow = logs.length - _maxLogFiles;
      for (var i = 0; i < overflow; i++) {
        await logs[i].delete();
      }
    } catch (e) {
      debugPrint('[AgentLogger] Failed to prune old logs: $e');
    }
  }

  /// Deletes every agent session log written by this app.
  ///
  /// Returns the number of files deleted (0 when logging is disabled or the
  /// directories are unavailable). Available for settings/privacy UI.
  static Future<int> clearLogs() async {
    if (!isEnabled) return 0;
    var deleted = 0;
    for (final dir in await _allLogDirectories()) {
      try {
        for (final file in dir.listSync().whereType<File>()) {
          if (file.path.endsWith('.log')) {
            await file.delete();
            deleted++;
          }
        }
      } catch (e) {
        debugPrint('[AgentLogger] Failed to clear logs in ${dir.path}: $e');
      }
    }
    return deleted;
  }

  static Future<List<Directory>> _allLogDirectories() async {
    final dirs = <Directory>[];
    try {
      if (Platform.isAndroid) {
        final external = await getExternalStorageDirectory();
        if (external != null) {
          dirs.add(Directory(p.join(external.path, 'agent_logs')));
        }
      }
      final docs = await getApplicationDocumentsDirectory();
      dirs.add(Directory(p.join(docs.path, 'ArkLores', 'agent_logs')));
    } on MissingPluginException {
      dirs.add(
        Directory(p.join(Directory.systemTemp.path, 'ArkLores', 'agent_logs')),
      );
    } catch (_) {
      // Ignore; empty list means nothing to clean.
    }
    return dirs;
  }
}
