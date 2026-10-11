// 0.14: the checks a model's tool calls pass before they run or enter the
// conversation. Generic: the same for every tool and question.
import 'dart:convert';

import 'package:arklores/core/agent/tool_call_gate.dart';
import 'package:arklores/core/agent/tools/agent_tool.dart';
import 'package:arklores/core/llm/llm_client.dart';
import 'package:flutter_test/flutter_test.dart';

class _Tool extends AgentTool {
  @override
  String get name => 'look';
  @override
  String get description => 'test tool';
  @override
  Map<String, dynamic> get parameters => {
        'type': 'object',
        'properties': {
          'pattern': {'type': 'string', 'description': '要找的词'},
          'count': {'type': 'integer'},
          'ids': {'type': 'array', 'items': {'type': 'string'}},
        },
        'required': ['pattern'],
      };
  @override
  Future<String> execute(Map<String, dynamic> arguments) async => '';
}

void main() {
  final tool = _Tool();
  ToolCall call(String args) => ToolCall(id: 'c', name: 'look', arguments: args);

  test('objects written back to back become separate calls', () {
    expect(splitJsonObjects('{"a":1}{"b":"}{"}'), ['{"a":1}', '{"b":"}{"}']);
    expect(splitJsonObjects(' {"a":1} , {"b":2} '), ['{"a":1}', '{"b":2}']);
    expect(splitJsonObjects('{"a":1}'), ['{"a":1}']);
    expect(splitJsonObjects('{"a":1}x{"b":2}'), ['{"a":1}x{"b":2}']);
    expect(splitJsonObjects('{"a":'), ['{"a":']);
    final split = splitGluedCalls([call('{"pattern":"甲"}{"pattern":"乙"}')]);
    expect(split.map((c) => (c.id, c.arguments)), [
      ('c', '{"pattern":"甲"}'),
      ('c_1', '{"pattern":"乙"}'),
    ]);
  });

  test('a good call runs; numbers and single strings are read', () {
    final checked =
        checkToolCall(call('{"pattern":"甲","count":"5","ids":"x.txt"}'), tool, ['look']);
    expect(checked.ok, isTrue);
    expect(checked.arguments, {'pattern': '甲', 'count': 5, 'ids': ['x.txt']});
    expect(checked.note, isNull);
  });

  test('unknown arguments are dropped with a note', () {
    final checked = checkToolCall(call('{"pattern":"甲","scope":"all"}'), tool, ['look']);
    expect(checked.ok, isTrue);
    expect(checked.arguments, {'pattern': '甲'});
    expect(checked.note, contains('scope'));
  });

  test('a missing argument is refused with what came and a correct call', () {
    final checked =
        checkToolCall(call('{"description":"pattern: 甲"}'), tool, ['look']);
    expect(checked.ok, isFalse);
    expect(checked.error, startsWith('错误：look 缺少必填参数 pattern'));
    expect(checked.error, contains('字符串，要找的词'));
    expect(checked.error, contains('description 不是这个工具的参数'));
    expect(checked.error, contains('正确的写法：{"pattern":"<pattern>"}'));
    // What enters the conversation is valid JSON whatever came.
    expect(jsonDecode(checked.sanitized.arguments), isA<Map<String, dynamic>>());
  });

  test('arguments that are not one JSON object are refused', () {
    final checked = checkToolCall(call('pattern=甲'), tool, ['look']);
    expect(checked.ok, isFalse);
    expect(checked.error, contains('不是一个 JSON 对象'));
    expect(checked.sanitized.arguments, '{}');
  });

  test('an unknown tool is refused with the tools there are', () {
    final checked = checkToolCall(
      const ToolCall(id: 'c', name: 'nope', arguments: '{}'),
      null,
      ['look', 'read'],
    );
    expect(checked.error, contains('look、read'));
  });
}
