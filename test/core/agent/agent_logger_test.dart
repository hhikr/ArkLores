// The opt-in AI session log: off by default, what it writes, its privacy
// limits (truncated query and content), pruning and clearing.
import 'dart:io';

import 'package:arklores/core/agent/agent_logger.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../support/temp_dir.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory docs;

  setUp(() {
    docs = Directory.systemTemp.createTempSync('agent_logger');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => docs.path,
    );
  });
  tearDown(() async {
    AgentLogger.setEnabled(false);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
    await deleteTempDir(docs);
  });

  Directory logDir() => Directory(p.join(docs.path, 'ArkLores', 'agent_logs'));

  test('off by default: nothing is written', () async {
    expect(AgentLogger.isEnabled, isFalse);
    final logger = AgentLogger('问题')..logObservation('原文');
    expect(await logger.flush(), isNull);
    expect(logDir().existsSync(), isFalse);
    expect(await AgentLogger.clearLogs(), 0);
  });

  test('a session log has every step, with long text cut', () async {
    AgentLogger.setEnabled(true);
    final logger = AgentLogger('问' * 300, agentName: 'Test')
      ..logIteration(1)
      ..logRawResponse('回复')
      ..logParsed(thought: '想', action: 'sql', actionInput: '{}', finalAnswer: '')
      ..logToolCall('sql', {'q': 'SELECT 1'})
      ..logObservation('行' * 2500)
      ..logToolDiagnostics('  ')
      ..logToolDiagnostics('慢查询')
      ..logFallback('提示', '兜底')
      ..logError('出错')
      ..logFinalAnswer('答案');
    final path = await logger.flush();
    expect(p.dirname(path!), logDir().path);
    final text = File(path).readAsStringSync();
    for (final part in [
      'Agent  : Test',
      '[Iteration 1]',
      '▶ RAW LLM RESPONSE:',
      '  Action      : sql',
      '▶ TOOL CALL: sql',
      '▶ TOOL DIAGNOSTICS:\n慢查询',
      '▶ FALLBACK RESPONSE:\n兜底',
      '▶ ERROR: 出错',
      '▶ FINAL ANSWER:\n答案',
      'Session complete',
    ]) {
      expect(text, contains(part));
    }
    // The question is kept to 200 characters, a step's text to 2000.
    expect(text, contains('…[truncated 100 chars]'));
    expect(text, contains('…[truncated 500 chars]'));
    expect(text, isNot(contains('问' * 201)));
    expect('▶ TOOL DIAGNOSTICS'.allMatches(text), hasLength(1));
  });

  test('only the 20 newest logs are kept; clearing removes them', () async {
    AgentLogger.setEnabled(true);
    logDir().createSync(recursive: true);
    for (var i = 0; i < 22; i++) {
      File(p.join(logDir().path, 'old_$i.log'))
        ..writeAsStringSync('x')
        ..setLastModifiedSync(DateTime(2026, 1, 1, 0, i));
    }
    await AgentLogger('问题').flush();
    final names = logDir().listSync().map((f) => p.basename(f.path)).toSet();
    expect(names, hasLength(20));
    expect(names, isNot(contains('old_0.log')));
    expect(names, isNot(contains('old_2.log')));
    expect(names.where((n) => n.startsWith('session_')), hasLength(1));

    expect(await AgentLogger.clearLogs(), 20);
    expect(logDir().listSync(), isEmpty);
  });
}
