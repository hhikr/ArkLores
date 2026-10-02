import 'dart:io';

import 'package:arklores/core/agent/agent_logger.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() => AgentLogger.setEnabled(false));

  test('logging is off by default', () {
    expect(AgentLogger.isEnabled, isFalse);
  });

  test('flush returns null while disabled', () async {
    AgentLogger.setEnabled(false);
    final logger = AgentLogger('测试问题');
    expect(await logger.flush(), isNull);
  });

  test('flush writes a session log file when enabled', () async {
    AgentLogger.setEnabled(true);
    final logger = AgentLogger('测试问题', agentName: 'Test');
    final path = await logger.flush();
    expect(path, isNotNull);
    final file = File(path!);
    expect(file.existsSync(), isTrue);
    final content = file.readAsStringSync();
    expect(content, contains('测试问题'));
    expect(content, contains('Agent  : Test'));
    expect(content, contains('Session complete'));
  });

  test('setEnabled controls subsequent sessions', () async {
    AgentLogger.setEnabled(false);
    expect(AgentLogger.isEnabled, isFalse);
    AgentLogger.setEnabled(true);
    expect(AgentLogger.isEnabled, isTrue);
  });
}
