import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/agent/agent_provider.dart';
import '../../core/agent/story_answer.dart';
import '../../core/agent/turn_stats.dart';
import '../../core/llm/llm_client.dart';
import '../../core/llm/llm_provider.dart';
import '../../shared/providers/handoff_provider.dart';
import '../../shared/providers/settings_provider.dart';
import 'investigation_ui.dart';
import 'work_steps.dart';

/// Developer bridge for testing Ask on a phone (0.14).
///
/// Only in an app built with `--dart-define=ARKLORES_PHONE_BRIDGE=true`
/// (`tools/install_local.ps1 -Build -Bridge`); release builds have none of
/// it. Such an app keeps trying to reach `ws://127.0.0.1:<port>` on the
/// phone, which `adb reverse` (set up by `tools/phone_ask.dart`) carries to
/// the computer: nothing listens on the phone. The computer sends a question
/// and the app asks it as if it was typed, and every question asked on the
/// phone, from the computer or by hand, is sent back as it runs: the work
/// steps, the thinking, the status line, the answer text, the cost.
const bool phoneBridgeEnabled = bool.fromEnvironment('ARKLORES_PHONE_BRIDGE');

const int phoneBridgePort =
    int.fromEnvironment('ARKLORES_PHONE_BRIDGE_PORT', defaultValue: 47321);

/// Turns successive states of the Ask chat into events, each what the
/// reader saw change: `question`, `start`, `step` (a tool call, a note, a
/// rewrite, an error), `output` (a call's result), `think`, `status`,
/// `answer` (text appended) or `answer_reset` (text replaced), `done`.
class BridgeTranscriber {
  /// [baseline] is the chat when the bridge connected: what it holds is not
  /// sent again.
  BridgeTranscriber([List<ChatMessage> baseline = const []])
      : _seen = baseline.length,
        _finished = {
          for (final m in baseline)
            if (!m.isStreaming) m.id,
        };

  int _seen;
  final Set<String> _finished;
  String? _current;
  int _steps = 0;
  final Set<int> _outputs = {};
  String _thinking = '';
  String _status = '';
  String _answer = '';

  List<Map<String, Object?>> update(List<ChatMessage> messages) {
    final out = <Map<String, Object?>>[];
    if (messages.length < _seen) {
      // A new conversation (or one restored from the history).
      out.add({'t': 'cleared'});
      _seen = 0;
      _finished
        ..clear()
        ..addAll([
          for (final m in messages)
            if (!m.isStreaming) m.id,
        ]);
      _seen = messages.length;
      _current = null;
      return out;
    }
    for (var i = _seen; i < messages.length; i++) {
      final m = messages[i];
      if (m.role == MessageRole.user) {
        out.add({'t': 'question', 'text': m.content});
      }
    }
    _seen = messages.length;
    for (final m in messages) {
      if (m.role != MessageRole.assistant || _finished.contains(m.id)) {
        continue;
      }
      out.addAll(_answerEvents(m));
    }
    return out;
  }

  List<Map<String, Object?>> _answerEvents(ChatMessage m) {
    final out = <Map<String, Object?>>[];
    if (m.id != _current) {
      _current = m.id;
      _steps = 0;
      _outputs.clear();
      _thinking = '';
      _status = '';
      _answer = '';
      out.add({'t': 'start'});
    }
    final steps = workStepsOf(m.steps);
    for (var i = 0; i < steps.length; i++) {
      final s = steps[i];
      if (i >= _steps) out.add(stepEvent(s, i));
      if (s.isTool && s.done && _outputs.add(i)) {
        out.add({
          't': 'output',
          'i': i,
          'tool': s.tool,
          if (s.subtask != null) 'subtask': s.subtask,
          'summary': stepSummary(s),
          'failed': s.failed,
          'text': s.text,
        });
      }
    }
    _steps = steps.length;
    if (m.reasoning != _thinking) {
      out.add(
        m.reasoning.startsWith(_thinking)
            ? {'t': 'think', 'text': m.reasoning.substring(_thinking.length)}
            : {'t': 'think', 'text': m.reasoning, 'reset': true},
      );
      _thinking = m.reasoning;
    }
    if (m.liveStatus != _status) {
      _status = m.liveStatus;
      if (_status.isNotEmpty) out.add({'t': 'status', 'text': _status});
    }
    if (m.content != _answer && m.content != '[ASK_ERROR]') {
      out.add(
        m.content.startsWith(_answer)
            ? {'t': 'answer', 'text': m.content.substring(_answer.length)}
            : {'t': 'answer_reset', 'text': m.content},
      );
      _answer = m.content;
    }
    if (!m.isStreaming) {
      _finished.add(m.id);
      final errors = [
        for (final s in steps)
          if (s.kind == WorkKind.error) s.text,
      ];
      out.add({
        't': 'done',
        'status': outcomeOf(m),
        'answer': isStoryAnswer(m.content)
            ? stripStoryAnswerMarkers(m.content)
            : m.content,
        if (m.factCheckVerdict != null) 'verdict': m.factCheckVerdict!.name,
        if (errors.isNotEmpty) 'error': errors.last,
        if (m.stats != null) 'stats': formatUsageLine(m.stats!),
      });
    }
    return out;
  }

  static Map<String, Object?> stepEvent(WorkStep s, int i) => {
        't': 'step',
        'i': i,
        'kind': s.kind.name,
        if (s.tool != null) 'tool': s.tool,
        if (s.args.isNotEmpty) 'args': s.args,
        if (s.subtask != null) 'subtask': s.subtask,
        if (!s.isTool) 'text': s.text,
      };

  /// `answered` / `partial` / `not_covered`, or `error`, `canceled`.
  static String outcomeOf(ChatMessage m) {
    if (m.isError || m.content == '[ASK_ERROR]') return 'error';
    if (m.content == '[ASK_CANCELED]') return 'canceled';
    return parseStoryAnswerEnvelope(m.content)?.status.wireValue ?? 'answered';
  }
}

/// One line on what a finished tool call found, roughly as the work
/// timeline says it.
String stepSummary(WorkStep s) {
  if (s.failed) return s.failure;
  if (s.empty) return '没有结果';
  switch (s.kind) {
    case WorkKind.read:
      final range = s.lineRange;
      return '《${s.storyTitle}》'
          '${range == null ? '' : ' L${range.$1}–${range.$2}'}';
    case WorkKind.find:
      final n = s.searchStoryCount;
      return n == null ? _firstLine(s.text) : '$n 篇剧情';
    case WorkKind.sql:
      final n = s.rowCount;
      return n == null ? _firstLine(s.text) : '$n 行';
    case WorkKind.grep:
      final (hits, stories) = s.grepCounts;
      return '$hits 处，$stories 篇';
    case WorkKind.wikiSearch:
      final n = s.wikiPageCount;
      return n == null ? _firstLine(s.text) : '$n 个页面';
    case WorkKind.wikiRead:
      final range = s.paragraphRange;
      return '${s.wikiTitle}'
          '${range == null ? '' : ' P${range.$1}–${range.$2}'}';
    default:
      return _firstLine(s.text);
  }
}

String _firstLine(String text) {
  final line = text.trimLeft().split('\n').first.trim();
  return line.length <= 80 ? line : '${line.substring(0, 80)}…';
}

/// Runs the bridge while [child] is shown (wrap the app in it only when
/// [phoneBridgeEnabled]).
class PhoneBridgeHost extends ConsumerStatefulWidget {
  const PhoneBridgeHost({
    super.key,
    required this.child,
    this.port = phoneBridgePort,
  });

  final Widget child;
  final int port;

  @override
  ConsumerState<PhoneBridgeHost> createState() => _PhoneBridgeHostState();
}

class _PhoneBridgeHostState extends ConsumerState<PhoneBridgeHost> {
  bool _stopped = false;
  WebSocket? _socket;

  @override
  void initState() {
    super.initState();
    unawaited(_run());
  }

  @override
  void dispose() {
    _stopped = true;
    _socket?.close();
    super.dispose();
  }

  Future<void> _run() async {
    while (!_stopped) {
      try {
        final socket =
            await WebSocket.connect('ws://127.0.0.1:${widget.port}')
                .timeout(const Duration(seconds: 5));
        _socket = socket;
        await _serve(socket);
      } catch (_) {
        // No computer (yet): try again in a moment.
      }
      _socket = null;
      if (!_stopped) await Future<void>.delayed(const Duration(seconds: 3));
    }
  }

  Future<void> _serve(WebSocket socket) async {
    void send(Map<String, Object?> event) {
      if (socket.readyState == WebSocket.open) socket.add(jsonEncode(event));
    }

    final transcriber = BridgeTranscriber(ref.read(askChatProvider));
    final listener = ref.listenManual<List<ChatMessage>>(
      askChatProvider,
      (_, next) => transcriber.update(next).forEach(send),
    );
    send(_hello());
    try {
      await for (final data in socket) {
        if (data is! String) continue;
        final command = jsonDecode(data);
        if (command is Map<String, dynamic>) await _handle(command, send);
      }
    } finally {
      listener.close();
    }
  }

  Map<String, Object?> _hello() {
    final config = ref.read(apiConfigProvider);
    return {
      't': 'hello',
      'model': config.chatModel,
      'host': Uri.tryParse(config.chatBaseUrl)?.host ?? '',
      'options': ref.read(answerOptionsProvider).encode(),
      'think': ref.read(deepThinkingProvider),
      'vectors': ref.read(embeddingClientProvider) != null,
      'recording': AskChatNotifier.recordingEnabled,
    };
  }

  Future<void> _handle(
    Map<String, dynamic> command,
    void Function(Map<String, Object?>) send,
  ) async {
    final chat = ref.read(askChatProvider.notifier);
    switch (command['cmd']) {
      case 'ask':
        if (ref.read(askChatProvider).any((m) => m.isStreaming)) {
          send({'t': 'busy'});
          return;
        }
        if (command['new'] == true) chat.newSession();
        final options = command['options'];
        if (options is Map) await _applyOptions(options);
        // Show the question where it is answered.
        ref.read(mainTabRequestProvider.notifier).state = 1;
        send(_hello());
        unawaited(
          chat.sendMessage('${command['text'] ?? ''}').whenComplete(() {
            send({'t': 'session', 'id': chat.currentSession?.sessionId});
          }),
        );
      case 'cancel':
        chat.cancel();
      case 'new':
        chat.newSession();
      case 'hello':
        send(_hello());
    }
  }

  /// Sets the answer options named in [options] (saved, as the menu does).
  Future<void> _applyOptions(Map<dynamic, dynamic> options) async {
    bool? flag(String key) =>
        options[key] is bool ? options[key] as bool : null;
    final current = ref.read(answerOptionsProvider);
    final next = current.copyWith(
      review: flag('review'),
      digest: flag('digest'),
      wiki: flag('wiki'),
      delegate: flag('delegate'),
    );
    if (next != current) {
      await ref.read(answerOptionsProvider.notifier).set(next);
    }
    final think = flag('think');
    if (think != null) ref.read(deepThinkingProvider.notifier).state = think;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
