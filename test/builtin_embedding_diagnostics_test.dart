import 'dart:math';

import 'package:arklores/core/rag/local_embedding/builtin_embedding_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'prints built-in embedding health diagnostics',
    () async {
      late final BuiltinEmbeddingClient client;
      try {
        client = await BuiltinEmbeddingClient.load();
      } catch (e) {
        // ignore: avoid_print
        print('[builtin_embedding] runtime unavailable: $e');
        return;
      }
      try {
        final samples = <String>[
          '阿米娅',
          '凯尔希',
          '罗德岛',
          '龙门',
          'apple banana',
          '阿米娅是罗德岛的公开领袖，也是剧情中的核心角色。',
          '陪伊冯进入车间并解决里面的天使。',
        ];
        final vectors = <String, List<double>>{};
        for (final sample in samples) {
          vectors[sample] = await client.embed(sample);
        }

        for (final entry in vectors.entries) {
          final vector = entry.value;
          final norm = sqrt(vector.fold<double>(
            0,
            (sum, value) => sum + value * value,
          ));
          // ignore: avoid_print
          print(
            '[builtin_embedding] sample="${entry.key}", '
            'dimension=${vector.length}, norm=${norm.toStringAsFixed(6)}, '
            'first8=${vector.take(8).map((v) => v.toStringAsFixed(6)).toList()}',
          );
        }

        for (var i = 0; i < samples.length; i++) {
          for (var j = i + 1; j < samples.length; j++) {
            final a = samples[i];
            final b = samples[j];
            // ignore: avoid_print
            print(
              '[builtin_embedding] cosine("$a", "$b") = '
              '${_cosine(vectors[a]!, vectors[b]!).toStringAsFixed(6)}',
            );
          }
        }
      } finally {
        client.dispose();
      }
    },
    skip: 'Diagnostic-only test. Run manually before publishing a seed DB.',
  );
}

double _cosine(List<double> a, List<double> b) {
  if (a.length != b.length) return 0;
  var dot = 0.0;
  var normA = 0.0;
  var normB = 0.0;
  for (var i = 0; i < a.length; i++) {
    dot += a[i] * b[i];
    normA += a[i] * a[i];
    normB += b[i] * b[i];
  }
  final denominator = sqrt(normA) * sqrt(normB);
  if (denominator == 0) return 0;
  return dot / denominator;
}
