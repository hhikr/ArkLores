/// The "保存 AI 对话记录" switch (off by default): when on, every Ask turn
/// is recorded into the user-visible `chat_sessions/` files
/// (`ChatSessionStore`). Applied at startup via [AgentLogger.setEnabled] and
/// on toggle in Settings.
class AgentLogger {
  AgentLogger._();

  static bool _enabled = false;

  static bool get isEnabled => _enabled;

  static void setEnabled(bool value) => _enabled = value;
}
