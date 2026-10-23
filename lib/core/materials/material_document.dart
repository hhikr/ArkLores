import 'dart:convert';
import 'package:crypto/crypto.dart';

String materialHash(String text) =>
    sha256.convert(utf8.encode(text)).toString().substring(0, 24);

final materialCitationPattern = RegExp(
  r'material:([\w/-]+)@([a-f0-9]+)\s*[:：]\s*[Pp]?(\d+)(?:\s*[-–~]\s*[Pp]?(\d+))?',
);

class MaterialBlock {
  factory MaterialBlock.fromJson(Map<String, dynamic> j) => MaterialBlock(
        j['text'] as String,
        j['heading'] as String? ?? '',
        kind: j['kind'] as String? ?? '正文',
        author: j['author'] as String? ?? '',
      );
  const MaterialBlock(
    this.text,
    this.heading, {
    this.kind = '正文',
    this.author = '',
  });
  final String text, heading, kind, author;
  Map<String, Object?> toJson() =>
      {'text': text, 'heading': heading, 'kind': kind, 'author': author};
}

class MaterialDocument {
  factory MaterialDocument.fromJson(Map<String, dynamic> j) => MaterialDocument(
        id: j['id'] as String,
        sourceId: j['source'] as String,
        title: j['title'] as String,
        body: j['body'] as String,
        order: j['order'] as int? ?? 0,
        blocks: List.unmodifiable(
          (j['blocks'] as List).map(
            (b) => MaterialBlock.fromJson(Map<String, dynamic>.from(b as Map)),
          ),
        ),
      );
  MaterialDocument({
    required this.id,
    required this.sourceId,
    required this.title,
    required this.body,
    required List<MaterialBlock> blocks,
    this.order = 0,
  }) : blocks = List.unmodifiable(blocks);
  final String id, sourceId, title, body;
  final List<MaterialBlock> blocks;
  final int order;
  late final String version = materialHash(
    jsonEncode({
      'title': title,
      'body': body,
      'blocks': blocks.map((b) => b.toJson()).toList(),
    }),
  );
  late final String pageId = 'material:$id@$version';
  Map<String, Object?> toJson() => {
        'id': id,
        'source': sourceId,
        'title': title,
        'body': body,
        'order': order,
        'blocks': blocks.map((b) => b.toJson()).toList(),
      };
}

/// Offsets remain tied to the immutable document version, independent of vectors.
MaterialDocument parseMaterial({
  required String id,
  required String sourceId,
  required String title,
  required String body,
  int order = 0,
  List<Map<String, dynamic>> regions = const [],
  String defaultAuthor = '',
}) {
  final blocks = <MaterialBlock>[];
  final headings = <String>[];
  for (final raw in body.replaceAll('\r\n', '\n').split(RegExp(r'\n\s*\n'))) {
    if (raw.trim().isEmpty) continue;
    final heading =
        RegExp(r'^(#{1,6})\s+(.+)$', multiLine: true).firstMatch(raw);
    if (heading != null && heading.group(0)!.trim() == raw.trim()) {
      final depth = heading.group(1)!.length;
      while (headings.length >= depth) {
        headings.removeLast();
      }
      headings.add(heading.group(2)!.trim());
    }
    final text = raw.trim();
    String normalized(String value) => value
        .replaceAll(RegExp(r'^#{1,6}\s+', multiLine: true), '')
        .replaceAll(RegExp(r'\s+'), '');
    final normalizedText = normalized(text);
    final matches = regions
        .where((r) => normalized('${r['text']}').contains(normalizedText))
        .toList();
    final kinds = matches.map((r) => '${r['kind']}').toSet();
    final kind = kinds.length == 1 && kinds.single != '排除'
        ? kinds.single
        : (regions.isNotEmpty
            ? '未确认类别'
            : text.startsWith('>')
                ? '引文'
                : '正文');
    final authors = matches
        .map((r) => '${r['author'] ?? ''}')
        .where((s) => s.isNotEmpty)
        .toSet();
    final author = authors.length == 1
        ? authors.single
        : kind == '正文'
            ? defaultAuthor
            : '';
    // A long paragraph is split without dropping any characters or UTF-16 pair.
    var from = 0;
    while (from < text.length) {
      var end = (from + 800).clamp(0, text.length);
      if (end < text.length &&
          text.codeUnitAt(end - 1) >= 0xd800 &&
          text.codeUnitAt(end - 1) <= 0xdbff) {
        end--;
      }
      blocks.add(
        MaterialBlock(
          text.substring(from, end),
          headings.join(' / '),
          kind: kind,
          author: author,
        ),
      );
      from = end;
    }
  }
  return MaterialDocument(
    id: id,
    sourceId: sourceId,
    title: title,
    body: body,
    blocks: List.unmodifiable(blocks),
    order: order,
  );
}

class MaterialSource {
  factory MaterialSource.fromJson(Map<String, dynamic> j) => MaterialSource(
        id: j['id'] as String,
        title: j['title'] as String,
        enabled: j['enabled'] == true,
        builtin: j['builtin'] == true,
        kind: j['kind'] as String? ?? '用户提供资料',
        policy: j['policy'] as String? ?? '',
        game: j['game'] as String? ?? 'all',
      );
  const MaterialSource({
    required this.id,
    required this.title,
    this.enabled = false,
    this.builtin = false,
    this.kind = '用户提供资料',
    this.policy = '用户提供资料，用于讨论与查证，不等同于游戏原文。',
    this.game = 'all',
  });
  final String id, title, kind, policy, game;
  final bool enabled, builtin;
  String get policyVersion => materialHash('$kind\n$policy');
  MaterialSource copyWith({bool? enabled, String? kind, String? policy}) =>
      MaterialSource(
        id: id,
        title: title,
        enabled: enabled ?? this.enabled,
        builtin: builtin,
        kind: kind ?? this.kind,
        policy: policy ?? this.policy,
        game: game,
      );
  Map<String, Object?> toJson() => {
        'id': id,
        'title': title,
        'enabled': enabled,
        'builtin': builtin,
        'kind': kind,
        'policy': policy,
        'game': game,
      };
}

class MaterialChunk {
  const MaterialChunk(this.document, this.start, this.end, this.text);
  final MaterialDocument document;
  final int start, end;
  final String text;
  String get hash => materialHash(text);
}

List<MaterialChunk> materialChunks(MaterialDocument d, String sourceTitle) {
  final out = <MaterialChunk>[];
  var first = 0;
  while (first < d.blocks.length) {
    var last = first;
    final b = d.blocks[first];
    var text = b.text;
    while (last + 1 < d.blocks.length) {
      final next = d.blocks[last + 1];
      if (next.heading != b.heading ||
          next.author != b.author ||
          next.kind != b.kind ||
          text.length + next.text.length + 2 > 800) {
        break;
      }
      text += '\n\n${next.text}';
      last++;
    }
    out.add(
      MaterialChunk(
        d,
        first,
        last,
        '$sourceTitle / ${d.title} / ${b.heading}${b.author.isEmpty ? '' : ' / ${b.author}'}\n$text',
      ),
    );
    first = last + 1;
  }
  return out;
}
