import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'chat_session_models.dart';

/// Summary of one persisted chat session, for the history list UI.
class ChatSessionSummary {
  const ChatSessionSummary({
    required this.sessionId,
    required this.title,
    required this.updatedAt,
    required this.createdAt,
    required this.turnCount,
    this.lastMode,
    this.lastQuery = '',
    this.corrupt = false,
  });

  final String sessionId;
  final String title;
  final DateTime updatedAt;
  final DateTime createdAt;
  final int turnCount;
  final String? lastMode;
  final String lastQuery;
  final bool corrupt;
}

/// Persists AI chat sessions as JSON files in a user-visible directory
/// (same area as the GameData database):
///   Android external storage → chat_sessions/conversation_`<id>`.json
///   Other:                    `[Documents]`/ArkLores/chat_sessions/
///
/// Each file is one full conversation (multi-turn); writes are atomic
/// (temp file + rename, like [RoleplaySessionStore]) so a killed process
/// never leaves a half-written session. Corrupt files are surfaced in the
/// history list instead of crashing the app.
class ChatSessionStore {
  const ChatSessionStore({this.filePath});

  /// Overrides the directory (tests / desktop CLI).
  final String? filePath;

  static const int maxSessionFiles = 50;

  Future<Directory> _directory() async {
    if (filePath != null) return Directory(filePath!);
    if (Platform.isAndroid) {
      final external = await getExternalStorageDirectory();
      if (external != null) {
        return Directory(p.join(external.path, 'chat_sessions'));
      }
    }
    final docs = await getApplicationDocumentsDirectory();
    return Directory(p.join(docs.path, 'ArkLores', 'chat_sessions'));
  }

  Future<File> _fileFor(String sessionId) async {
    final dir = await _directory();
    return File(p.join(dir.path, 'conversation_$sessionId.json'));
  }

  /// Atomically writes [session] (temp file + rename). Also prunes the
  /// oldest files when the session count exceeds [maxSessionFiles].
  Future<void> save(ChatSessionFile session) async {
    final file = await _fileFor(session.sessionId);
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(session.encode(), flush: true);
    await temporary.rename(file.path);
    await _prune();
  }

  /// Loads one session; returns null when missing or corrupt.
  Future<ChatSessionFile?> load(String sessionId) async {
    final file = await _fileFor(sessionId);
    if (!await file.exists()) return null;
    try {
      return ChatSessionFile.decode(await file.readAsString());
    } on FormatException {
      debugPrint('[ChatSessionStore] corrupt session file: ${file.path}');
      return null;
    } on FileSystemException {
      return null;
    }
  }

  /// Lists sessions newest-first. Corrupt files are included with
  /// [ChatSessionSummary.corrupt] = true so the user can see and delete them.
  Future<List<ChatSessionSummary>> list() async {
    final dir = await _directory();
    if (!await dir.exists()) return const [];
    final summaries = <ChatSessionSummary>[];
    await for (final entity in dir.list()) {
      if (entity is! File ||
          !entity.path.endsWith('.json') ||
          entity.path.endsWith('.tmp')) {
        continue;
      }
      final name = p.basenameWithoutExtension(entity.path);
      final sessionId =
          name.startsWith('conversation_') ? name.substring(13) : name;
      try {
        final decoded = jsonDecode(await entity.readAsString());
        if (decoded is! Map<String, dynamic>) {
          throw const FormatException('not an object');
        }
        final session = ChatSessionFile.fromJson(decoded);
        summaries.add(ChatSessionSummary(
          sessionId: sessionId,
          title: session.title,
          updatedAt: session.updatedAt,
          createdAt: session.createdAt,
          turnCount: session.turnCount,
          lastMode: session.lastMode?.name,
          lastQuery: session.lastQuery,
        ),);
      } catch (_) {
        final stat = await entity.stat();
        summaries.add(ChatSessionSummary(
          sessionId: sessionId,
          title: '（损坏的会话文件）',
          updatedAt: stat.modified,
          createdAt: stat.modified,
          turnCount: 0,
          corrupt: true,
        ),);
      }
    }
    summaries.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return summaries;
  }

  /// Deletes one session file. Returns true when a file was removed.
  Future<bool> delete(String sessionId) async {
    final file = await _fileFor(sessionId);
    if (!await file.exists()) return false;
    await file.delete();
    return true;
  }

  /// Renders a human-readable transcript of [sessionId] (plain text).
  ///
  /// Returns null when the session is missing or corrupt. The text keeps the
  /// complete raw content: router decision, every iteration's raw LLM
  /// response, tool calls and observations, and the final answer.
  Future<String?> exportText(String sessionId) async {
    final session = await load(sessionId);
    if (session == null) return null;
    final buffer = StringBuffer()
      ..writeln('═' * 72)
      ..writeln('ArkLores Chat Session')
      ..writeln('Session : ${session.sessionId}')
      ..writeln('Created : ${session.createdAt.toIso8601String()}')
      ..writeln('Updated : ${session.updatedAt.toIso8601String()}')
      ..writeln('Title   : ${session.title}')
      ..writeln('═' * 72);
    for (final turn in session.turns) {
      buffer
        ..writeln()
        ..writeln('─' * 60)
        ..writeln('[Turn ${turn.turn}] ${turn.timestamp.toIso8601String()}')
        ..writeln('User Mode      : ${turn.userMode.name}')
        ..writeln('Effective Mode : ${turn.effectiveMode.name}');
      if (turn.router != null) {
        buffer
          ..writeln('Router Raw     : ${turn.router!.rawResponse}')
          ..writeln(
            'Router Error   : ${turn.router!.error ?? '-'}',
          );
      }
      buffer
        ..writeln('Model          : ${turn.model} @ ${turn.baseUrl}')
        ..writeln('Status         : ${turn.status.jsonValue}'
            '${turn.error != null ? ' (${turn.error})' : ''}')
        ..writeln('Query          : ${turn.query}')
        ..writeln();
      for (final iteration in turn.iterations) {
        buffer
          ..writeln('[Iteration ${iteration.iteration}]')
          ..writeln('RAW LLM RESPONSE:')
          ..writeln(iteration.rawResponse)
          ..writeln()
          ..writeln('  Thought     : ${iteration.thought}')
          ..writeln('  Action      : ${iteration.action}');
        if (iteration.actionInput.isNotEmpty) {
          buffer.writeln('  Action Input: ${iteration.actionInput}');
        }
        if (iteration.observation.isNotEmpty) {
          buffer
            ..writeln('  Observation :')
            ..writeln(iteration.observation);
        }
        buffer.writeln();
      }
      buffer
        ..writeln('FINAL ANSWER:')
        ..writeln(turn.answer)
        ..writeln();
    }
    return buffer.toString();
  }

  /// Keeps only the [maxSessionFiles] most recent sessions.
  Future<void> _prune() async {
    try {
      final dir = await _directory();
      if (!await dir.exists()) return;
      final files = <File>[];
      await for (final entity in dir.list()) {
        if (entity is File &&
            entity.path.endsWith('.json') &&
            !entity.path.endsWith('.tmp')) {
          files.add(entity);
        }
      }
      files.sort((a, b) =>
          a.statSync().modified.compareTo(b.statSync().modified),);
      final overflow = files.length - maxSessionFiles;
      for (var i = 0; i < overflow; i++) {
        await files[i].delete();
      }
    } catch (e) {
      debugPrint('[ChatSessionStore] Failed to prune sessions: $e');
    }
  }
}
