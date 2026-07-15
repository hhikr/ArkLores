import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Debug-only agent logger.
///
/// Writes a human-readable log of every ReAct session to:
///   Android external storage → ArkLores/agent_logs/session_[timestamp].log
///
/// Only active in debug builds (kDebugMode). No-ops in release.
class AgentLogger {
  final StringBuffer _buf = StringBuffer();
  final DateTime _startTime;
  final String _userQuery;
  final String _agentName;

  AgentLogger(this._userQuery, {String agentName = 'ReAct'})
      : _agentName = agentName,
        _startTime = DateTime.now() {
    _header();
  }

  static bool get isEnabled => kDebugMode;

  void _header() {
    _buf.writeln('═' * 72);
    _buf.writeln('ArkLores Agent Debug Log');
    _buf.writeln('Agent  : $_agentName');
    _buf.writeln('Time   : ${_startTime.toIso8601String()}');
    _buf.writeln('Query  : $_userQuery');
    _buf.writeln('═' * 72);
    _buf.writeln();
  }

  void logIteration(int iteration, int maxIterations) {
    if (!isEnabled) return;
    _buf.writeln('─' * 60);
    _buf.writeln('[Iteration $iteration / $maxIterations]');
    _buf.writeln();
  }

  void logRawResponse(String response) {
    if (!isEnabled) return;
    _buf.writeln('▶ RAW LLM RESPONSE:');
    _buf.writeln(response);
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
    _buf.writeln('  Thought     : $thought');
    _buf.writeln('  Action      : $action');
    _buf.writeln('  Action Input: $actionInput');
    _buf.writeln('  Final Answer: $finalAnswer');
    _buf.writeln();
  }

  void logToolCall(String toolName, Map<String, dynamic> args) {
    if (!isEnabled) return;
    _buf.writeln('▶ TOOL CALL: $toolName');
    _buf.writeln('  Args: $args');
    _buf.writeln();
  }

  void logObservation(String observation) {
    if (!isEnabled) return;
    _buf.writeln('▶ OBSERVATION:');
    _buf.writeln(observation);
    _buf.writeln();
  }

  void logToolDiagnostics(String diagnostics) {
    if (!isEnabled || diagnostics.trim().isEmpty) return;
    _buf.writeln('▶ TOOL DIAGNOSTICS:');
    _buf.writeln(diagnostics.trim());
    _buf.writeln();
  }

  void logFinalAnswer(String answer) {
    if (!isEnabled) return;
    _buf.writeln('─' * 60);
    _buf.writeln('▶ FINAL ANSWER:');
    _buf.writeln(answer);
    _buf.writeln();
  }

  void logError(String error) {
    if (!isEnabled) return;
    _buf.writeln('▶ ERROR: $error');
    _buf.writeln();
  }

  void logFallback(String prompt, String response) {
    if (!isEnabled) return;
    _buf.writeln('▶ FALLBACK PROMPT: $prompt');
    _buf.writeln('▶ FALLBACK RESPONSE:');
    _buf.writeln(response);
    _buf.writeln();
  }

  /// Writes the log file to the most accessible directory on this platform.
  ///
  /// Android: /sdcard/ArkLores/agent_logs/
  /// Other:   [Documents]/ArkLores/agent_logs/
  Future<String?> flush() async {
    if (!isEnabled) return null;

    final elapsed = DateTime.now().difference(_startTime);
    _buf.writeln('═' * 72);
    _buf.writeln('Session complete. Elapsed: ${elapsed.inMilliseconds}ms');
    _buf.writeln('═' * 72);

    try {
      Directory logDir;
      if (Platform.isAndroid) {
        // Write to /sdcard/ArkLores/agent_logs — accessible via Files app or ADB
        final external = await getExternalStorageDirectory();
        if (external != null) {
          // external.path is something like /sdcard/Android/data/[pkg]/files
          // Go two levels up to reach /sdcard/Android/data/[pkg] then use a
          // sibling dir that is world-readable via the Files app shortcut.
          // Actually easier: just write to app external dir + agent_logs
          logDir = Directory(p.join(external.path, 'agent_logs'));
        } else {
          final docs = await getApplicationDocumentsDirectory();
          logDir = Directory(p.join(docs.path, 'agent_logs'));
        }
      } else {
        final docs = await getApplicationDocumentsDirectory();
        logDir = Directory(p.join(docs.path, 'ArkLores', 'agent_logs'));
      }

      await logDir.create(recursive: true);

      final ts = _startTime
          .toIso8601String()
          .replaceAll(':', '-')
          .replaceAll('.', '-');
      final file = File(p.join(logDir.path, 'session_$ts.log'));
      await file.writeAsString(_buf.toString(), flush: true);

      debugPrint('[AgentLogger] Log saved to: ${file.path}');
      return file.path;
    } catch (e) {
      debugPrint('[AgentLogger] Failed to write log: $e');
      return null;
    }
  }
}
