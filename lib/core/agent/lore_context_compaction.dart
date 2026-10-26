part of 'lore_agent_loop.dart';

int _messageChars(List<Message> messages) => messages.fold(
      0,
      (n, m) =>
          n +
          m.content.length +
          (m.reasoningContent?.length ?? 0) +
          (m.toolCalls == null ? 0 : jsonEncode(m.toolCalls).length),
    );

(String, List<String>) _compactObject(String raw) {
  // The answer decoder only repairs answer entries, not arbitrary JSON.
  final start = raw.indexOf('{');
  if (start < 0) throw const FormatException('No compaction object');
  var depth = 0;
  var quoted = false;
  var escape = false;
  for (var i = start; i < raw.length; i++) {
    final c = raw[i];
    if (quoted) {
      if (escape) {
        escape = false;
      } else if (c == r'\') {
        escape = true;
      } else if (c == '"') {
        quoted = false;
      }
    } else if (c == '"') {
      quoted = true;
    } else if (c == '{') {
      depth++;
    } else if (c == '}' && --depth == 0) {
      final json =
          jsonDecode(raw.substring(start, i + 1)) as Map<String, dynamic>;
      final notes = json['notes'] as String;
      final refs = (json['keep'] as List).cast<String>();
      bool valid(String ref) => [
            _citation,
            _recordCitation,
            wikiCitationPattern,
            materialCitationPattern,
          ].any((pattern) {
            final m = pattern.matchAsPrefix(ref);
            return m != null && m.end == ref.length;
          });
      return (notes, refs.where(valid).toList());
    }
  }
  throw const FormatException('Unclosed compaction object');
}

class _RetainedOriginals {
  final texts = <String>[];
  final omitted = <String>[];
  final shown = SeenLines();
  int get count => texts.length;
}

Future<_RetainedOriginals> _retainOriginals(
  List<String> refs,
  int budget,
  GameDataRetrieval store,
  SeenLines seen,
  WikiLookup? wiki,
  MaterialSnapshot? materials,
) async {
  final out = _RetainedOriginals();
  var size = 0;
  for (final (index, ref) in refs.indexed) {
    final shown = SeenLines();
    final text = StringBuffer();
    try {
      final story = _citation.matchAsPrefix(ref);
      final record = _recordCitation.matchAsPrefix(ref);
      final w = wikiCitationPattern.firstMatch(ref);
      final m = materialCitationPattern.matchAsPrefix(ref);
      if (story != null) {
        final id = story[1]!;
        final a = int.parse(story[2]!), b = int.parse(story[3] ?? story[2]!);
        final name = (await store.storyCatalogEntries([id]))[id]?.label ?? fallbackStoryLabel(id);
        // Bound reads by the actual previously displayed line ranges.
        for (final (lo, hi) in seen.seenRanges(id, a < b ? a : b, a < b ? b : a)) {
          var next = lo;
          while (next <= hi) {
            final page = await store.readStoryLines(storyId: id,
              startLine: next, endLine: hi, maxLines: hi - next + 1,
            );
            if (page.lines.isEmpty) break;
            for (final line in page.lines) {
              if (line.lineIndex > hi || !seen.covers(id, line.lineIndex, line.lineIndex) ||
                  !isStoryEvidence(line.kind)) {
                continue;
              }
              if (text.isEmpty) text.writeln('《$name》 $id');
              text.writeln(formatStoryLine(line.lineIndex, line.speaker, line.content, kind: line.kind));
              shown.add(id, line.lineIndex);
            }
            final after = page.lines.last.lineIndex + 1;
            if (after <= next) break;
            next = after;
          }
        }
      } else if (record != null && seen.hasRecord(record[1]!)) {
        final r = await store.readRecord(record[1]!);
        if (r != null) {
          final partial = r.content.length > 1500;
          final kind = r.subtype.isEmpty || r.subtype == r.category ? r.category : '${r.category}·${r.subtype}';
          text.writeln(
              'record:${r.id} | $kind | ${r.title}${r.owner.isEmpty ? '' : ' | 所属：${r.owner}'}',);
          text.write(
              partial ? '${r.content.substring(0, 1500)}（片段，全文更长）' : r.content,);
          shown.addRecord(r.id, partial: partial);
        }
      } else if (w != null) {
        final id = LoreAgentLoop._wikiPageIdOf(w);
        final page = await wiki?.snapshot(id);
        if (page != null) {
          final (lo, hi) = LoreAgentLoop._wikiRange(w);
          for (final (i, block) in page.range(lo, hi)) {
            if (!seen.covers(id, i, i)) continue;
            if (text.isEmpty) text.writeln('《${page.title}》 $id');
            text.writeln(
                'P$i ${block.section.isEmpty ? '' : '[${block.section}] '}${block.text}',);
            shown.add(id, i);
          }
        }
      } else if (m != null) {
        final id = 'material:${m[1]}@${m[2]}';
        final doc = materials?.document(id);
        if (doc != null) {
          final a = int.parse(m[3]!), b = int.parse(m[4] ?? m[3]!);
          for (var i = 0; i < doc.blocks.length; i++) {
            if (i < (a < b ? a : b) ||
                i > (a < b ? b : a) ||
                !seen.covers(id, i, i)) {
              continue;
            }
            final block = doc.blocks[i];
            if (text.isEmpty) text.writeln('《${doc.title}》 $id');
            text.writeln(
                'P$i [${block.kind} / ${block.author.isEmpty ? '作者未确认' : block.author}] ${block.heading}\n${block.text}',);
            shown.add(id, i);
          }
        }
      }
    } catch (_) {
      // A missing local source must not stop an otherwise usable answer.
      continue;
    }
    if (shown.isEmpty) continue;
    final original = text.toString().trimRight();
    final added = original.length + (out.texts.isEmpty ? 0 : 2);
    if (size + added > budget) {
      out.omitted.addAll(refs.skip(index));
      break;
    }
    out.texts.add(original);
    out.shown.addAll(shown);
    size += added;
  }
  return out;
}

/// The last answer for the memo: its entries as text with their citations
/// (the answer JSON is a third longer for the same content), or the reply as
/// it was when it was not a JSON answer.
String _answerForMemo(LoreConversation? prior) {
  if (prior == null) return '';
  if (prior.entries.isEmpty) return prior.lastAnswer;
  return [
    for (final e in prior.entries)
      e.isText
          ? '- ${e.text}${e.cites.isEmpty ? '' : '（${e.cites.join('、')}）'}'
          : '### ${e.heading}',
  ].join('\n');
}

String _compactMemo(
  int n,
  List<String> questions,
  String answer,
  String notes,
  _RetainedOriginals kept,
  SeenLines seen,
  String? current,
) =>
    [
      '【对话纪要 #$n】上下文过长，较早的内容已压缩。下面是到目前为止的纪要；之后的对话接着这里。',
      if (questions.isNotEmpty)
        '## 这个对话问过的问题\n${[
          for (final (i, q) in questions.indexed) '${i + 1}. $q',
        ].join('\n')}',
      if (answer.isNotEmpty) '## 上一个回答\n$answer',
      if (notes.isNotEmpty) '## 要点\n$notes',
      if (kept.texts.isNotEmpty) '## 保留的原文\n${kept.texts.join('\n\n')}',
      if (kept.omitted.isNotEmpty) '（没有放进来的保留请求：${kept.omitted.join('、')}）',
      if (!seen.isEmpty)
        '## 已读但不在上文的原文\n可以引用；要用其中的内容，先重新读取。\n${seen.summary(maxChars: 1500)}',
      if (current != null) '## 当前问题\n$current',
    ].join('\n');
