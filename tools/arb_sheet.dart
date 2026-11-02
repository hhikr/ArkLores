// The Chinese strings as a sheet that is easy to read and edit by hand: grouped
// by the file that uses them, one string per entry. Local, in notes/.
//
//   dart run tools/arb_sheet.dart export   writes notes/arb_zh.txt
//   dart run tools/arb_sheet.dart import   writes the edits back to app_zh.arb
//
// Only the indented lines are edited. Import changes only the strings that
// differ, keeps the file's order and metadata, and refuses a string whose
// placeholders changed.
import 'dart:convert';
import 'dart:io';

const _arb = 'lib/shared/l10n/app_zh.arb';
const _sheet = 'notes/arb_zh.txt';
const _unused = '（代码里没找到用处）';

Map<String, String> _strings() => {
      for (final e
          in (jsonDecode(File(_arb).readAsStringSync()) as Map<String, dynamic>)
              .entries)
        if (!e.key.startsWith('@') && e.value is String)
          e.key: e.value as String,
    };

void _export() {
  final strings = _strings();
  // The first file that uses each key, by the whole word after a dot.
  final usedIn = <String, String>{};
  final word = RegExp(r'\.([a-z][A-Za-z0-9]*)\b');
  final files = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart') && !f.path.contains('generated'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  for (final file in files) {
    final name = file.path
        .replaceAll(r'\', '/')
        .replaceFirst('lib/', '')
        .replaceFirst('features/', '');
    for (final m in word.allMatches(file.readAsStringSync())) {
      if (strings.containsKey(m[1])) usedIn.putIfAbsent(m[1]!, () => name);
    }
  }
  final groups = <String, List<String>>{};
  for (final key in strings.keys) {
    (groups[usedIn[key] ?? _unused] ??= []).add(key);
  }
  final out = StringBuffer(
    '# 只改缩进的那一行；{n} 这样的占位符要保留，换行写成 \\n。\n'
    '# 改完运行：dart run tools/arb_sheet.dart import\n',
  );
  for (final file in groups.keys.toList()..sort()) {
    out.write('\n== $file\n');
    for (final key in groups[file]!) {
      out.write('$key\n    ${strings[key]!.replaceAll('\n', r'\n')}\n');
    }
  }
  File(_sheet).writeAsStringSync(out.toString());
  stdout.writeln('${strings.length} strings -> $_sheet');
}

Set<String> _placeholders(String text) =>
    {for (final m in RegExp(r'\{(\w+)').allMatches(text)) m[1]!};

void _import() {
  final strings = _strings();
  final edited = <String, String>{};
  String? key;
  for (final line in File(_sheet).readAsLinesSync()) {
    if (line.startsWith('    ') && key != null) {
      edited[key] = line.substring(4).trim().replaceAll(r'\n', '\n');
      key = null;
    } else if (strings.containsKey(line.trim())) {
      key = line.trim();
    }
  }
  final changed = {
    for (final e in edited.entries)
      if (strings[e.key] != e.value) e.key: e.value,
  };
  final problems = [
    for (final e in changed.entries)
      if (!_setEquals(_placeholders(e.value), _placeholders(strings[e.key]!)))
        '${e.key}: 占位符变了（原来是 ${_placeholders(strings[e.key]!).join('、')}）',
  ];
  if (problems.isNotEmpty) {
    stderr.writeln(problems.join('\n'));
    stderr.writeln('没有写入。');
    exit(1);
  }
  var text = File(_arb).readAsStringSync();
  for (final e in changed.entries) {
    final line = RegExp(
      '^  "${RegExp.escape(e.key)}": "(?:[^"\\\\]|\\\\.)*"',
      multiLine: true,
    );
    text = text.replaceFirstMapped(
      line,
      (_) => '  "${e.key}": ${jsonEncode(e.value)}',
    );
  }
  File(_arb).writeAsStringSync(text);
  for (final e in changed.entries) {
    stdout.writeln('${e.key}\n  - ${strings[e.key]}\n  + ${e.value}');
  }
  stdout.writeln('${changed.length} changed.');
  jsonDecode(text);
}

bool _setEquals(Set<String> a, Set<String> b) =>
    a.length == b.length && a.containsAll(b);

void main(List<String> args) {
  switch (args.firstOrNull) {
    case 'export':
      _export();
    case 'import':
      _import();
    default:
      stderr.writeln('usage: dart run tools/arb_sheet.dart export|import');
      exit(2);
  }
}
