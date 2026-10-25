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
    this.lastQuery = '',
    this.corrupt = false,
  });

  final String sessionId;
  final String title;
  final DateTime updatedAt;
  final DateTime createdAt;
  final int turnCount;
  final String lastQuery;
  final bool corrupt;
}

// A recorded conversation holds every tool output and can run to megabytes:
// it is encoded and decoded off the UI isolate (a page of the history list
// decoded on it stalled the page opening it), with these.

String _encode(ChatSessionFile session) => session.encode();

ChatSessionSummary _summarize((String, String) file) {
  final (sessionId, source) = file;
  final session = ChatSessionFile.decode(source);
  return ChatSessionSummary(
    sessionId: sessionId,
    title: session.title,
    updatedAt: session.updatedAt,
    createdAt: session.createdAt,
    turnCount: session.turnCount,
    lastQuery: session.lastQuery,
  );
}

/// Persists AI chat sessions as JSON files in a user-visible directory
/// (same area as the GameData database):
///   Android external storage → chat_sessions/conversation_`<id>`.json
///   Other:                    `[Documents]`/ArkLores/chat_sessions/
///
/// Each file is one full conversation (multi-turn); writes are atomic
/// (temp file + rename) so a killed process
/// never leaves a half-written session. Corrupt files are surfaced in the
/// history list instead of crashing the app. Conversations are kept until
/// the user deletes them; the history list reads them a page at a time
/// ([count], [page]).
class ChatSessionStore {
  const ChatSessionStore({this.filePath});

  /// Overrides the directory (tests / desktop CLI).
  final String? filePath;

  /// Conversations on one page of the history list.
  static const int pageSize = 15;

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

  /// Atomically writes [session] (temp file + rename).
  Future<void> save(ChatSessionFile session) async {
    final file = await _fileFor(session.sessionId);
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(await compute(_encode, session), flush: true);
    await temporary.rename(file.path);
  }

  /// Loads one session; returns null when missing or corrupt.
  Future<ChatSessionFile?> load(String sessionId) async {
    final file = await _fileFor(sessionId);
    if (!await file.exists()) return null;
    try {
      return await compute(ChatSessionFile.decode, await file.readAsString());
    } on FormatException {
      debugPrint('[ChatSessionStore] corrupt session file: ${file.path}');
      return null;
    } on FileSystemException {
      return null;
    }
  }

  /// The session files with the time each was last written, newest first.
  Future<List<(File, DateTime)>> _files() async {
    final dir = await _directory();
    if (!await dir.exists()) return const [];
    final files = <(File, DateTime)>[];
    await for (final entity in dir.list()) {
      if (entity is! File ||
          !entity.path.endsWith('.json') ||
          entity.path.endsWith('.tmp')) {
        continue;
      }
      try {
        files.add((entity, (await entity.stat()).modified));
      } on FileSystemException {
        // Deleted meanwhile.
      }
    }
    files.sort((a, b) {
      final byTime = b.$2.compareTo(a.$2);
      return byTime != 0 ? byTime : b.$1.path.compareTo(a.$1.path);
    });
    return files;
  }

  /// What the history list shows of [file] (written at [modified]). A file
  /// that cannot be read is a summary with [ChatSessionSummary.corrupt].
  Future<ChatSessionSummary> _summary(File file, DateTime modified) async {
    final name = p.basenameWithoutExtension(file.path);
    final sessionId =
        name.startsWith('conversation_') ? name.substring(13) : name;
    try {
      return await compute(
        _summarize,
        (sessionId, await file.readAsString()),
      );
    } catch (_) {
      return ChatSessionSummary(
        sessionId: sessionId,
        title: '（损坏的会话文件）',
        updatedAt: modified,
        createdAt: modified,
        turnCount: 0,
        corrupt: true,
      );
    }
  }

  /// Lists sessions newest-first. Corrupt files are included with
  /// [ChatSessionSummary.corrupt] = true so the user can see and delete them.
  Future<List<ChatSessionSummary>> list() async {
    final summaries = [
      for (final (file, modified) in await _files())
        await _summary(file, modified),
    ]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return summaries;
  }

  /// How many sessions are saved.
  Future<int> count() async => (await _files()).length;

  /// One page (0-based, [size] a page) of the sessions, last written first.
  /// Only the files of that page are read.
  Future<List<ChatSessionSummary>> page(int page, int size) async {
    final files = await _files();
    return [
      for (final (file, modified) in files.skip(page * size).take(size))
        await _summary(file, modified),
    ];
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
  /// complete raw content: every iteration's raw LLM response, tool calls
  /// and observations, the final answer and what the turn cost.
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
        ..writeln('[Turn ${turn.turn}] ${turn.timestamp.toIso8601String()}');
      final usage = turn.usage;
      if (usage != null) {
        buffer.writeln(
          'Usage          : ${usage.calls} calls, ${usage.promptTokens} in '
          '(${usage.cachedPromptTokens} cached), ${usage.completionTokens} out, '
          '${usage.elapsed.inSeconds}s',
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
}
