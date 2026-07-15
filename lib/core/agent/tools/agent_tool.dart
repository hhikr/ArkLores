/// Result returned by a tool when it needs to separate LLM-visible output from
/// developer diagnostics.
class ToolExecutionResult {
  final String observation;
  final String? debugLog;

  const ToolExecutionResult({
    required this.observation,
    this.debugLog,
  });
}

/// Abstract class representing a tool that can be used by AI agents.
abstract class AgentTool {
  /// Unique identifier for the tool.
  String get name;

  /// Description of what the tool does, used by the LLM.
  String get description;

  /// Parameter definition in JSON Schema format.
  Map<String, dynamic> get parameters;

  /// Executes the tool logic with the provided arguments.
  Future<dynamic> execute(Map<String, dynamic> arguments);

  /// Returns the OpenAI-compatible representation of this tool.
  Map<String, dynamic> toJson() => {
        'type': 'function',
        'function': {
          'name': name,
          'description': description,
          'parameters': parameters,
        },
      };
}
