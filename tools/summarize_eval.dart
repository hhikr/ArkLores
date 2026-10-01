// Aggregates live Ask-pipeline `*.summary.json` files (written by
// test/live/ask_pipeline_live_test.dart) into an evaluation report, and
// optionally compares against a baseline run.
//
//   dart run tools/summarize_eval.dart build/live_sessions/<tag> \
//     [--baseline=build/live_sessions/<older-tag>] [--out=build/eval/<tag>.md]

import 'dart:convert';
import 'dart:io';

void main(List<String> args) {
  final positional = args.where((a) => !a.startsWith('--')).toList();
  if (positional.isEmpty) {
    stderr.writeln('usage: summarize_eval.dart <run-dir> [--baseline=<dir>] [--out=<md>]');
    exitCode = 2;
    return;
  }
  final run = _load(positional.first);
  final baselineDir = _arg(args, '--baseline');
  final baseline = baselineDir == null ? null : _load(baselineDir);

  final buffer = StringBuffer()
    ..writeln('# Eval report: ${positional.first}')
    ..writeln()
    ..writeln('| metric | value${baseline == null ? '' : ' | baseline | Δ'} |')
    ..writeln('| --- | ---${baseline == null ? '' : ' | --- | ---'} |');
  final metrics = _metrics(run);
  final base = baseline == null ? null : _metrics(baseline);
  for (final entry in metrics.entries) {
    final b = base?[entry.key];
    final delta = b == null ? '' : (entry.value - b).toStringAsFixed(3);
    buffer.writeln('| ${entry.key} | ${_fmt(entry.value)}'
        '${base == null ? '' : ' | ${b == null ? '-' : _fmt(b)} | $delta'} |');
  }

  buffer
    ..writeln()
    ..writeln('| id | type | mode | terminal | iters | gold recall | cites | warn | s |')
    ..writeln('| --- | --- | --- | --- | --- | --- | --- | --- | --- |');
  for (final r in run) {
    final recall = r['gold_recall'];
    buffer.writeln('| ${r['id']} | ${r['type'] ?? ''} | ${r['effective_mode']} | '
        '${r['terminal']} | ${r['iterations']} | '
        '${recall == null ? '-' : (recall as num).toStringAsFixed(2)} | '
        '${r['citations']} | ${r['source_warning'] == true ? 'yes' : ''} | '
        '${((r['duration_ms'] as num? ?? 0) / 1000).round()} |');
  }

  final out = _arg(args, '--out');
  if (out != null) {
    File(out)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(buffer.toString());
  }
  stdout.write(buffer);
}

List<Map<String, dynamic>> _load(String dir) {
  final files = Directory(dir)
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.summary.json'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  return [
    for (final f in files)
      jsonDecode(f.readAsStringSync()) as Map<String, dynamic>,
  ];
}

Map<String, double> _metrics(List<Map<String, dynamic>> rows) {
  double mean(Iterable<num> xs) =>
      xs.isEmpty ? 0 : xs.fold<num>(0, (a, b) => a + b) / xs.length;
  final withGold = rows.where((r) => r['gold_recall'] != null);
  final answered = rows.where((r) => r['terminal'] == 'answered');
  final cited = rows.where((r) => (r['citations'] as num? ?? 0) > 0);
  return {
    'cases': rows.length.toDouble(),
    'gold_recall_mean': mean(withGold.map((r) => r['gold_recall'] as num)),
    'gold_any_hit_rate': mean(withGold.map((r) => (r['gold_recall'] as num) > 0 ? 1 : 0)),
    'answered_rate': mean(rows.map((r) => r['terminal'] == 'answered' ? 1 : 0)),
    'unresolved_rate': mean(rows.map((r) => r['terminal'] == 'unresolved' ? 1 : 0)),
    'error_rate': mean(rows.map((r) => r['terminal'] == 'error' ? 1 : 0)),
    'cited_answer_rate': answered.isEmpty
        ? 0
        : mean(answered.map((r) => (r['citations'] as num? ?? 0) > 0 ? 1 : 0)),
    'citation_valid_rate': cited.isEmpty
        ? 0
        : mean(cited.map((r) => r['source_warning'] == true ? 0 : 1)),
    'mean_iterations': mean(rows.map((r) => r['iterations'] as num? ?? 0)),
    'mean_empty_responses': mean(rows.map((r) => r['empty_responses'] as num? ?? 0)),
    'mean_seconds': mean(rows.map((r) => (r['duration_ms'] as num? ?? 0) / 1000)),
  };
}

String _fmt(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(3);

String? _arg(List<String> args, String name) {
  for (final a in args) {
    if (a.startsWith('$name=')) return a.substring(name.length + 1);
  }
  return null;
}
