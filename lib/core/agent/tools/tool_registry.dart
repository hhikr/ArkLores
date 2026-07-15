import 'agent_tool.dart';

/// Registry to manage available agent tools.
class ToolRegistry {
  final Map<String, AgentTool> _tools = {};

  /// Registers a tool in the registry.
  void register(AgentTool tool) {
    _tools[tool.name] = tool;
  }

  /// Registers multiple tools at once.
  void registerAll(List<AgentTool> tools) {
    for (final tool in tools) {
      register(tool);
    }
  }

  /// Retrieves a tool by its name.
  AgentTool? getTool(String name) => _tools[name];

  /// Returns all registered tools.
  List<AgentTool> get allTools => _tools.values.toList();

  /// Converts all registered tools to their OpenAI API format.
  List<Map<String, dynamic>> get toJsonList =>
      _tools.values.map((t) => t.toJson()).toList();
}
