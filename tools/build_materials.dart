import 'dart:convert';
import 'dart:io';

import 'package:arklores/core/llm/embedding_client.dart';
import 'package:arklores/core/materials/material_document.dart';
import 'package:arklores/core/materials/material_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> main(List<String> args) async {
  String? arg(String name) => args
      .where((a) => a.startsWith('$name='))
      .map((a) => a.substring(name.length + 1))
      .firstOrNull;
  final input = arg('--input');
  if (input == null) throw const FormatException('需要 --input=<正式 Markdown 目录>');
  final dir = Directory(input);
  final output = File(arg('--output') ?? 'assets/materials/terra.json.gz');
  final metadata = arg('--regions');
  final regions = metadata == null
      ? <Map<String, dynamic>>[]
      : [
          for (final r
              in jsonDecode(await File(metadata).readAsString()) as List)
            Map<String, dynamic>.from(r as Map),
        ];
  final files = await dir
      .list(recursive: true)
      .where(
        (f) =>
            f is File && f.path.endsWith('.md') && !f.path.endsWith('目录导航.md'),
      )
      .cast<File>()
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  const source = MaterialSource(
    id: 'terra',
    game: 'arknights',
    title: '大地巡旅',
    enabled: true,
    builtin: true,
    kind: '官方世界观补充',
    policy:
        '官方设定集，采用世界观内人物叙述。埃里克森为默认正文作者，按用户配置采用中高等认知，涉及世界本源、远古历史和复杂历史情境时可能存在认识局限。已确认属于凯尔希的批注采用高等认知，其针对同一命题的明确纠正优先于对应正文；补充、评价不等同于纠正，较高认知不代表确认整章。未知批注作者不得猜定。上述认知说明是资料配置，不是系统独立验证的事实。',
  );
  final docs = <MaterialDocument>[];
  for (final (i, file) in files.indexed) {
    final relative =
        file.path.substring(dir.path.length + 1).replaceAll('\\', '/');
    final body = await file.readAsString();
    final title =
        RegExp(r'^#\s+(.+)', multiLine: true).firstMatch(body)?.group(1) ??
            relative.split('/').last.replaceAll('.md', '');
    docs.add(
      parseMaterial(
        id: 'terra/${materialHash(relative)}',
        sourceId: source.id,
        title: title,
        body: body,
        order: i,
        regions: regions.where((r) => r['file'] == relative).toList(),
        defaultAuthor: '埃里克森',
      ),
    );
  }
  final chunks = [for (final d in docs) ...materialChunks(d, source.title)];
  final chars = chunks.fold<int>(0, (n, c) => n + c.text.length);
  stdout.writeln(
    '正文 ${docs.length} 篇 / ${docs.fold<int>(0, (n, d) => n + d.blocks.length)} 段 / ${chunks.length} 检索块 / 嵌入文本 $chars 字符 / 预计 ${(chars * 0.7).round()} tokens',
  );
  if (args.contains('--dry-run')) return;
  sqfliteFfiInit();
  await Directory('build/materials').create(recursive: true);
  final store =
      await MaterialStore.open(databaseFactoryFfi, 'build/materials/terra.db');
  await store.saveSource(source);
  for (final d in docs) {
    await store.saveDocument(d);
  }
  final csv = File(arg('--config') ?? 'tools/embedding-apiKey.csv');
  final lines = await csv.readAsLines();
  final config = {
    for (final line in lines)
      if (line.contains(','))
        line.substring(0, line.indexOf(',')).trim():
            line.substring(line.indexOf(',') + 1).trim(),
  };
  final client = OpenAICompatibleEmbeddingClient(
    config: EmbeddingConfig(
      baseUrl: config['openAiCompatible'] ?? '',
      apiKey: config['apiKey'] ?? '',
      model: 'qwen3.7-text-embedding',
      dimensions: 512,
    ),
  );
  try {
    final pending = await store.pending(source.id, client);
    stdout.writeln('待建立 $pending 块；缓存将复用。');
    await store.updateVectors(
      source.id,
      client,
      onProgress: () => stdout.writeln('索引进度已保存'),
    );
    if (await store.pending(source.id, client) != 0) {
      throw StateError('预置向量不完整');
    }
    final hashes = chunks.map((c) => c.hash).toSet();
    final vectors = (await store.vectors())
        .where(
          (v) =>
              hashes.contains(v.hash) &&
              v.model == client.model &&
              v.dims == client.dimensions,
        )
        .toList();
    final package = {
      'format': 1,
      'source': source.toJson(),
      'documents': docs.map((d) => d.toJson()).toList(),
      'vectors': vectors.map((v) => v.toJson()).toList(),
    };
    await output.parent.create(recursive: true);
    await output.writeAsBytes(gzip.encode(utf8.encode(jsonEncode(package))));
    stdout.writeln(
      '已生成 ${output.path} / ${await output.length()} bytes / ${vectors.length} 个向量 / 实际 ${client.tokensUsed} tokens',
    );
  } finally {
    client.dispose();
    await store.db.close();
  }
}
