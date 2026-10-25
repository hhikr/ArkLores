import 'package:arklores/core/agent/chat_session_models.dart';
import 'package:arklores/core/agent/chat_session_store.dart';

/// In-memory store: widget tests run under FakeAsync where real file IO never
/// completes, so every store method resolves immediately.
class MemoryChatSessionStore extends ChatSessionStore {
  final Map<String, ChatSessionFile> sessions = {};

  @override
  Future<void> save(ChatSessionFile session) async {
    sessions[session.sessionId] = session;
  }

  @override
  Future<ChatSessionFile?> load(String sessionId) async => sessions[sessionId];

  @override
  Future<List<ChatSessionSummary>> list() async {
    final summaries = [
      for (final session in sessions.values)
        ChatSessionSummary(
          sessionId: session.sessionId,
          title: session.title,
          updatedAt: session.updatedAt,
          createdAt: session.createdAt,
          turnCount: session.turnCount,
          lastQuery: session.lastQuery,
        ),
    ]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return summaries;
  }

  @override
  Future<int> count() async => sessions.length;

  @override
  Future<List<ChatSessionSummary>> page(int page, int size) async =>
      (await list()).skip(page * size).take(size).toList();

  @override
  Future<bool> delete(String sessionId) async {
    return sessions.remove(sessionId) != null;
  }
}
