// Asks a question in the ArkLores app on a phone connected by USB and shows,
// as it runs, what the app shows: the work steps, the thinking, the status
// line, the answer, the cost.
//
//   dart run tools/phone_ask.dart "问题"            # ask, wait for the answer
//   dart run tools/phone_ask.dart -i "问题"         # ... then type follow-ups
//   dart run tools/phone_ask.dart                  # only watch questions asked on the phone
//   dart run tools/phone_ask.dart --new --wiki=off --full "问题"
//
// Options: --new (a new conversation first), --wiki/--review/--digest/
// --delegate/--think=on|off (the answer options, saved in the app as the
// menu does), --full (every tool output in full), --device=<serial>,
// --port=<n> (default 47321), --no-adb (no phone: an app on this computer,
// e.g. `flutter run -d windows --dart-define=ARKLORES_PHONE_BRIDGE=true`).
//
// The app must be built with the bridge (`tools/install_local.ps1 -Build
// -Bridge`; release builds do not have it). This tool runs
// `adb reverse tcp:<port> tcp:<port>` and listens on the computer; the app
// connects to it within a few seconds of starting (it is launched when it
// does not). Everything shown is also written to build/phone_sessions/
// (<time>.log as shown, <time>.jsonl the events), and when the app records
// conversations (Settings > "保存 AI 对话记录") the session file is pulled
// there after each answer.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

const _package = 'com.arklores.arklores';
const _sessionsOnPhone = '/sdcard/Android/data/$_package/files/chat_sessions';

late final String _adb;
String? _device;
var _useAdb = true;
late final IOSink _log;
late final IOSink _events;
final bool _color = stdout.supportsAnsiEscapes;

Future<void> main(List<String> args) async {
  var port = 47321;
  var interactive = false;
  var fresh = false;
  var full = false;
  final options = <String, bool>{};
  final words = <String>[];
  for (final a in args) {
    final kv = RegExp(r'^--([\w-]+)(?:=(.*))?$').firstMatch(a);
    if (a == '-i' || a == '--interactive') {
      interactive = true;
    } else if (kv == null) {
      words.add(a);
    } else {
      final (name, value) = (kv.group(1)!, kv.group(2));
      switch (name) {
        case 'new':
          fresh = true;
        case 'full':
          full = true;
        case 'no-adb':
          _useAdb = false;
        case 'port':
          port = int.parse(value!);
        case 'device':
          _device = value;
        case 'wiki' || 'review' || 'digest' || 'delegate' || 'think':
          options[name] = value == null || value == 'on' || value == 'true';
        case 'help':
          stdout.writeln(
            File.fromUri(Platform.script)
                .readAsLinesSync()
                .takeWhile((l) => l.startsWith('//'))
                .map((l) => l.replaceFirst(RegExp(r'^// ?'), ''))
                .join('\n'),
          );
          return;
        default:
          stderr.writeln('unknown option --$name (see --help)');
          exit(64);
      }
    }
  }
  final question = words.join(' ').trim();

  if (_useAdb) {
    _adb = _findAdb();
    await _adbRun(['reverse', 'tcp:$port', 'tcp:$port']);
  }

  final stamp = DateTime.now()
      .toIso8601String()
      .substring(0, 19)
      .replaceAll(RegExp('[-:]'), '')
      .replaceFirst('T', '_');
  final dir = Directory('build/phone_sessions')..createSync(recursive: true);
  _log = File('${dir.path}/$stamp.log').openWrite();
  _events = File('${dir.path}/$stamp.jsonl').openWrite();

  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
  final view = _View(full: full);
  WebSocket? app;
  final connected = StreamController<WebSocket>.broadcast();
  final done = StreamController<Map<String, dynamic>>.broadcast();
  final sessions = StreamController<Object?>.broadcast();
  server.listen((request) async {
    if (!WebSocketTransformer.isUpgradeRequest(request)) {
      request.response.statusCode = HttpStatus.badRequest;
      await request.response.close();
      return;
    }
    final socket = await WebSocketTransformer.upgrade(request);
    await app?.close();
    app = socket;
    connected.add(socket);
    socket.listen(
      (data) {
        if (data is! String) return;
        _events.writeln(data);
        final event = jsonDecode(data) as Map<String, dynamic>;
        view.show(event);
        if (event['t'] == 'done') done.add(event);
        if (event['t'] == 'session') sessions.add(event['id']);
        if (event['t'] == 'busy') done.add(event);
      },
      onDone: () {
        if (identical(app, socket)) {
          app = null;
          view.note('App 断开了连接（切到后台被系统暂停，或 App 已关闭）；重新连上后会继续显示。');
        }
      },
    );
  });

  var asking = false;
  var interrupts = 0;
  ProcessSignal.sigint.watch().listen((_) async {
    interrupts++;
    if (asking && interrupts == 1 && app != null) {
      view.note('取消当前问题（再按一次 Ctrl+C 直接退出）');
      app!.add(jsonEncode({'cmd': 'cancel'}));
      return;
    }
    await _finish(server);
  });

  view.note('等待 App 连接（端口 $port）…');
  final first = connected.stream.first;
  final launched = Timer(const Duration(seconds: 4), () {
    if (!_useAdb) return;
    view.note('没有连上：启动 App（手机需亮屏解锁；App 要用 -Bridge 构建）');
    _adbRun(
      [
        'shell',
        'monkey',
        '-p',
        _package,
        '-c',
        'android.intent.category.LAUNCHER',
        '1',
      ],
      quiet: true,
    );
  });
  await first;
  launched.cancel();

  Future<void> ask(String text, {required bool fresh}) async {
    while (app == null) {
      await connected.stream.first;
    }
    asking = true;
    interrupts = 0;
    final answered = done.stream.first;
    final session = sessions.stream.first;
    app!.add(
      jsonEncode({
        'cmd': 'ask',
        'text': text,
        if (fresh) 'new': true,
        if (options.isNotEmpty) 'options': options,
      }),
    );
    final end = await answered;
    asking = false;
    // The session file is written right after the answer.
    if (end['t'] == 'done') {
      final id = await session.timeout(
        const Duration(seconds: 10),
        onTimeout: () => null,
      );
      await _pullSession(id, dir);
    }
  }

  if (question.isEmpty && !interactive) {
    view.note('只看模式：在手机上提问，这里实时显示；Ctrl+C 退出。');
    await Completer<void>().future;
  }
  var next = question;
  var firstQuestion = true;
  while (true) {
    if (next.isEmpty) {
      if (!interactive) break;
      stdout.write('\n追问（空行退出）> ');
      next = (stdin.readLineSync(
                encoding: Platform.isWindows && stdin.hasTerminal
                    ? systemEncoding
                    : utf8,
              ) ??
              '')
          .trim();
      if (next.isEmpty) break;
    }
    await ask(next, fresh: fresh && firstQuestion);
    firstQuestion = false;
    next = '';
  }
  await _finish(server);
}

Future<void> _finish(HttpServer server) async {
  await server.close(force: true);
  await _log.flush();
  await _events.flush();
  exit(0);
}

String _findAdb() {
  final names = Platform.isWindows ? ['adb.exe'] : ['adb'];
  final dirs = [
    ...?Platform.environment['PATH']?.split(Platform.isWindows ? ';' : ':'),
    for (final v in ['ANDROID_HOME', 'ANDROID_SDK_ROOT'])
      if (Platform.environment[v] != null)
        '${Platform.environment[v]}/platform-tools',
    r'C:\Users\hhikr\dev\android-sdk\platform-tools',
  ];
  for (final d in dirs) {
    for (final n in names) {
      final f = File('$d${Platform.pathSeparator}$n');
      if (f.existsSync()) return f.path;
    }
  }
  stderr.writeln('adb not found (install platform-tools or add adb to PATH)');
  exit(69);
}

Future<String> _adbRun(List<String> args, {bool quiet = false}) async {
  final all = [
    if (_device != null) ...['-s', _device!],
    ...args,
  ];
  final r = await Process.run(_adb, all, stdoutEncoding: utf8);
  if (r.exitCode != 0 && !quiet) {
    stderr.writeln('adb ${args.join(' ')} failed: ${r.stderr}'.trim());
    stderr.writeln('检查：手机已用 USB 连接、已解锁并允许 USB 调试（adb devices 能看到它）。');
    exit(69);
  }
  return '${r.stdout}';
}

Future<void> _pullSession(Object? id, Directory dir) async {
  if (id is! String || !_useAdb) return;
  final name = 'conversation_$id.json';
  final r = await Process.run(_adb, [
    if (_device != null) ...['-s', _device!],
    'pull',
    '$_sessionsOnPhone/$name',
    '${dir.path}/$name',
  ]);
  if (r.exitCode == 0) _View.plain('会话记录：${dir.path}/$name');
}

final _envelope = RegExp(r'\[STORY_ANSWER:[^\]]*\]\s*');

/// Prints the events as text, roughly as the app shows them.
class _View {
  _View({required this.full});

  final bool full;
  final Stopwatch _clock = Stopwatch();

  /// What is being streamed on the current line: 'think', 'answer' or null.
  String? _stream;
  String _lastStatus = '';

  static void plain(String text) {
    stdout.writeln(text);
    _log.writeln(_bare(text));
  }

  static String _bare(String text) =>
      text.replaceAll(RegExp('\x1B\\[\\d+m'), '');

  void note(String text) {
    _endStream();
    plain(_paint('2', '· $text'));
  }

  void show(Map<String, dynamic> e) {
    switch (e['t']) {
      case 'hello':
        final options = '${e['options']}'
            .split(';')
            .where((p) => !p.startsWith('v='))
            .join(' ');
        note('App 已连接：${e['model']} @ ${e['host']}；$options'
            '${e['think'] == true ? ' 深度思考' : ''}'
            '${e['vectors'] == true ? '' : '；没有向量服务'}'
            '${e['recording'] == true ? '' : '；没开“保存 AI 对话记录”，不拉会话文件'}');
      case 'cleared':
        note('手机上开始了新对话');
      case 'question':
        _clock
          ..reset()
          ..start();
        _endStream();
        plain(_paint('1', '\n■ 问题：${e['text']}'));
      case 'start':
        break;
      case 'step':
        _endStream();
        final who = e['subtask'] == null ? '' : '子助手${e['subtask']} · ';
        final text = '${e['text'] ?? ''}'.trim();
        switch (e['kind']) {
          case 'note':
            plain('${_t()}$who${_paint('36', '思路')}：$text');
          case 'redo':
            plain('${_t()}$who${_paint('33', '重写')}：$text');
          case 'error':
            plain('${_t()}$who${_paint('31', '错误')}：$text');
          default:
            plain('${_t()}$who${_paint('34', '→ ${e['tool']}')} '
                '${_args(e['args'])}');
        }
      case 'output':
        _endStream();
        final who = e['subtask'] == null ? '' : '子助手${e['subtask']} · ';
        final mark = e['failed'] == true ? _paint('31', '✗') : '←';
        plain('${_t()}$who$mark ${e['tool']}：${e['summary']}');
        if (full) {
          for (final line in '${e['text']}'.split('\n')) {
            plain(_paint('2', '    $line'));
          }
        }
      case 'status':
        final text = '${e['text']}';
        // The waiting line counts seconds: show it when it says something new.
        final shape = text.replaceAll(RegExp(r'\d+'), '#');
        if (shape == _lastStatus) return;
        _lastStatus = shape;
        _endStream();
        plain('${_t()}${_paint('2', '… $text')}');
      case 'think':
        _streamText('think', '${e['text']}', reset: e['reset'] == true);
      case 'answer':
        // The status line above the answer is the app's, not shown as text.
        final text = '${e['text']}'.replaceAll(_envelope, '');
        if (text.isNotEmpty) _streamText('answer', text);
      case 'answer_reset':
        _endStream();
        plain('${_t()}${_paint('33', '（答案文本被替换）')}');
        _streamText('answer', '${e['text']}'.replaceAll(_envelope, ''));
      case 'done':
        _endStream();
        _lastStatus = '';
        plain(
          _paint(
              '1',
              '\n══ ${e['status']}'
                  '${e['verdict'] == null ? '' : ' · 核查结论 ${e['verdict']}'}'
                  '${e['stats'] == null ? '' : ' · ${e['stats']}'}'),
        );
        if (e['error'] != null) plain(_paint('31', '错误：${e['error']}'));
        final answer = '${e['answer']}'.trim();
        if (answer.isNotEmpty && answer != '[ASK_ERROR]') {
          plain('──── 最终显示的答案 ────\n$answer\n────────────────');
        }
      case 'busy':
        note('手机上有问题正在回答，这个问题没有发出。');
    }
  }

  void _streamText(String kind, String text, {bool reset = false}) {
    if (_stream != kind || reset) {
      _endStream();
      final label = kind == 'think' ? _paint('35', '思考') : _paint('32', '答案');
      stdout.write('${_t()}$label｜');
      _log.write('${_bare(_t())}${kind == 'think' ? '思考' : '答案'}｜');
      _stream = kind;
    }
    final shown = kind == 'think' ? _paint('2', text) : text;
    stdout.write(shown);
    _log.write(text);
  }

  void _endStream() {
    if (_stream == null) return;
    stdout.writeln();
    _log.writeln();
    _stream = null;
  }

  String _t() {
    final s = _clock.elapsed.inSeconds;
    return _paint(
        '2',
        '[${(s ~/ 60).toString().padLeft(2, '0')}:'
            '${(s % 60).toString().padLeft(2, '0')}] ');
  }

  static String _args(Object? args) {
    if (args is! Map || args.isEmpty) return '';
    final text = args.entries.map((e) => '${e.key}=${e.value}').join('  ');
    return text.length <= 160 ? text : '${text.substring(0, 160)}…';
  }

  static String _paint(String code, String text) =>
      _color ? '\x1B[${code}m$text\x1B[0m' : text;
}
