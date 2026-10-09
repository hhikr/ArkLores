/// 0.14: what a model's tool calls must pass before they run or enter the
/// conversation.
///
/// Weaker models (and relays) write calls the tools cannot use: two calls
/// glued into one (`{…}{…}`), arguments under a name the tool does not have,
/// a required argument missing. Such a call is never run and never kept in
/// the conversation as written (a provider may reject the whole request for
/// arguments that are not JSON); the model gets an error that says what came
/// in, what is missing and how a correct call looks, and tries again. The
/// same checks hold for every tool and every question.
library;

import 'dart:convert';

import '../llm/llm_client.dart';
import 'tools/agent_tool.dart';

/// One call after the gate: the arguments to run it with, or the error to
/// hand back instead.
class CheckedCall {
  const CheckedCall(this.call, this.arguments, {this.error, this.note});

  final ToolCall call;

  /// Arguments the tool runs with (unknown keys dropped, numbers read).
  final Map<String, dynamic> arguments;

  /// Why the call was not run; null when it runs.
  final String? error;

  /// A remark that goes with the result of a call that runs (dropped keys).
  final String? note;

  bool get ok => error == null;

  /// The call as kept in the conversation: its name and the arguments as
  /// valid JSON, whatever the model wrote.
  ToolCall get sanitized => ToolCall(
        id: call.id,
        name: call.name,
        arguments: jsonEncode(arguments),
      );
}

/// Splits calls whose arguments are several JSON objects written one after
/// another into one call per object (same tool).
List<ToolCall> splitGluedCalls(List<ToolCall> calls) => [
      for (final call in calls) ...() {
        final parts = splitJsonObjects(call.arguments);
        if (parts.length < 2) return [call];
        return [
          for (final (i, part) in parts.indexed)
            ToolCall(
              id: i == 0 ? call.id : '${call.id}_$i',
              name: call.name,
              arguments: part,
            ),
        ];
      }(),
    ];

/// The top-level JSON objects of [text] when it is two or more of them
/// written back to back (`{…}{…}`, possibly with whitespace or commas
/// between); otherwise [text] alone.
List<String> splitJsonObjects(String text) {
  final trimmed = text.trim();
  if (!trimmed.startsWith('{')) return [text];
  final parts = <String>[];
  var depth = 0;
  var inString = false;
  var escaped = false;
  var start = -1;
  for (var i = 0; i < trimmed.length; i++) {
    final c = trimmed[i];
    if (inString) {
      if (escaped) {
        escaped = false;
      } else if (c == r'\') {
        escaped = true;
      } else if (c == '"') {
        inString = false;
      }
      continue;
    }
    if (c == '"') {
      inString = true;
    } else if (c == '{') {
      if (depth == 0) start = i;
      depth++;
    } else if (c == '}') {
      depth--;
      if (depth == 0 && start >= 0) {
        parts.add(trimmed.substring(start, i + 1));
        start = -1;
      }
      if (depth < 0) return [text];
    } else if (depth == 0 && c.trim().isNotEmpty && c != ',') {
      return [text];
    }
  }
  if (depth != 0 || parts.length < 2) return [text];
  for (final part in parts) {
    try {
      if (jsonDecode(part) is! Map) return [text];
    } on FormatException {
      return [text];
    }
  }
  return parts;
}

/// Checks [call] against [tool]'s parameter schema.
CheckedCall checkToolCall(
  ToolCall call,
  AgentTool? tool,
  Iterable<String> available,
) {
  if (tool == null) {
    return CheckedCall(
      call,
      const {},
      error: '错误：没有名为 ${call.name} 的工具。可用的工具：${available.join('、')}。',
    );
  }
  final raw = call.arguments.trim();
  Map<String, dynamic> args;
  if (raw.isEmpty) {
    args = {};
  } else {
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      decoded = null;
    }
    if (decoded is! Map) {
      return CheckedCall(
        call,
        const {},
        error: '错误：${call.name} 的参数不是一个 JSON 对象（收到：${_clip(raw, 300)}）。'
            '每次调用只写一个 JSON 对象；要做几件事就发几个调用。'
            '正确的写法：${exampleArguments(tool)}',
      );
    }
    args = Map<String, dynamic>.from(decoded);
  }

  final properties =
      (tool.parameters['properties'] as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{};
  final required = [
    for (final r in (tool.parameters['required'] as List?) ?? const [])
      '$r',
  ];
  final unknown = [
    for (final key in args.keys)
      if (!properties.containsKey(key)) key,
  ];
  final kept = <String, dynamic>{
    for (final MapEntry(:key, :value) in args.entries)
      if (properties.containsKey(key))
        key: _coerce(value, properties[key] as Map?),
  };
  final missing = [
    for (final r in required)
      if (_isBlank(kept[r])) r,
  ];
  if (missing.isNotEmpty) {
    return CheckedCall(
      call,
      kept,
      error: [
        '错误：${call.name} 缺少必填参数 ${missing.join('、')}'
            '（${missing.map((m) => '$m：${_describe(properties[m] as Map?)}').join('；')}）。',
        '收到的参数：${_clip(jsonEncode(args), 300)}'
            '${unknown.isEmpty ? '' : '（${unknown.join('、')} 不是这个工具的参数）'}。',
        '正确的写法：${exampleArguments(tool)}',
      ].join('\n'),
    );
  }
  return CheckedCall(
    call,
    kept,
    note: unknown.isEmpty
        ? null
        : '（参数 ${unknown.join('、')} 不是 ${call.name} 的参数，已忽略；'
            '可用参数：${properties.keys.join('、')}）',
  );
}

/// A minimal correct call of [tool]: its required arguments with
/// placeholders.
String exampleArguments(AgentTool tool) {
  final properties =
      (tool.parameters['properties'] as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{};
  final required = [
    for (final r in (tool.parameters['required'] as List?) ?? const []) '$r',
  ];
  final example = <String, Object>{
    for (final r in required)
      r: switch ((properties[r] as Map?)?['type']) {
        'integer' || 'number' => 0,
        'array' => ['<$r>'],
        _ => '<$r>',
      },
  };
  return jsonEncode(example);
}

/// Numbers written as text become numbers; a single string for a list
/// becomes a one-element list.
Object? _coerce(Object? value, Map<dynamic, dynamic>? schema) {
  final type = schema?['type'];
  if ((type == 'integer' || type == 'number') && value is String) {
    return num.tryParse(value.trim()) ?? value;
  }
  if (type == 'array' && value is String && value.trim().isNotEmpty) {
    return [value.trim()];
  }
  return value;
}

bool _isBlank(Object? value) =>
    value == null ||
    (value is String && value.trim().isEmpty) ||
    (value is List && value.isEmpty);

String _describe(Map<dynamic, dynamic>? schema) {
  final type = switch (schema?['type']) {
    'string' => '字符串',
    'integer' => '整数',
    'number' => '数字',
    'array' => '数组',
    'boolean' => '真/假',
    _ => '值',
  };
  final description = '${schema?['description'] ?? ''}'.trim();
  return description.isEmpty ? type : '$type，$description';
}

String _clip(String text, int max) =>
    text.length <= max ? text : '${text.substring(0, max)}…';
