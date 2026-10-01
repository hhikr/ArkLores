/// R12 evidence notebook: turns READ observations into line-anchored notes
/// and checks that a written answer only cites lines that were actually read.
///
/// Division of labor (CLAUDE.md principle 5): the extractor model only says
/// WHICH returned line supports WHAT fact; the quoted text is copied by code
/// from the story lines, so a note can never carry fabricated wording, and a
/// line number outside the returned page is dropped.
library;

import '../llm/llm_client.dart';
import 'investigation_state.dart';
import 'tools/observation_data.dart';

/// One story line parsed from a `read_story_lines` observation.
class ReadLine {
  const ReadLine({required this.index, required this.content, this.speaker});
  final int index;
  final String? speaker;
  final String content;

  String get text =>
      speaker == null || speaker!.isEmpty ? content : '$speaker：$content';
}

/// The lines one READ actually returned.
class ReadPage {
  const ReadPage({required this.storyId, required this.lines});
  final String storyId;
  final List<ReadLine> lines;

  int get firstLine => lines.first.index;
  int get lastLine => lines.last.index;

  ReadLine? line(int index) {
    for (final l in lines) {
      if (l.index == index) return l;
    }
    return null;
  }
}

final RegExp _storyHeader = RegExp(r'^Story:\s*(\S+)', multiLine: true);
final RegExp _lineRow = RegExp(r'^(\d+) \| (.*)$', multiLine: true);

/// Parses a `read_story_lines` observation (`Story:` header + `N | speaker |
/// content` rows). The DATA block, when present, is authoritative for the
/// story id and bounds the returned range. Null when no lines were returned.
ReadPage? parseReadObservation(String observation) {
  String? storyId;
  int? first;
  int? last;
  for (final block in parseDataBlocks(observation)) {
    if (block['type'] != 'read_story_lines') continue;
    storyId = block['story_id'] as String?;
    first = (block['first_line'] as num?)?.toInt();
    last = (block['last_line'] as num?)?.toInt();
  }
  storyId ??= _storyHeader.firstMatch(observation)?.group(1);
  if (storyId == null || storyId.isEmpty) return null;

  final lines = <ReadLine>[];
  for (final match in _lineRow.allMatches(observation)) {
    final index = int.parse(match.group(1)!);
    if (first != null && index < first) continue;
    if (last != null && index > last) continue;
    final rest = match.group(2)!;
    // Rows are `N | content` or `N | speaker | content`; a speaker never
    // contains the separator, so split on the first one only.
    final sep = rest.indexOf(' | ');
    lines.add(
      sep < 0
          ? ReadLine(index: index, content: rest.trim())
          : ReadLine(
              index: index,
              speaker: rest.substring(0, sep).trim(),
              content: rest.substring(sep + 3).trim(),
            ),
    );
  }
  if (lines.isEmpty) return null;
  return ReadPage(storyId: storyId, lines: lines);
}

const int _maxFactChars = 60;
const int _maxQuoteChars = 60;

/// Asks [client] which returned lines bear on [userQuery] and returns at most
/// [maxNotes] notes. Line numbers outside [page] are discarded; quotes are
/// copied from [page]. Returns an empty list on any failure (non-fatal).
Future<List<EvidenceNote>> extractEvidenceNotes(
  LLMClient client, {
  required String userQuery,
  required ReadPage page,
  int maxNotes = 6,
}) async {
  final numbered = page.lines.map((l) => '${l.index} | ${l.text}').join('\n');
  final ChatCompletionResult result;
  try {
    result = await client.chatCompletion(
      [
        Message.system(
          '你是剧情证据摘录员。给定用户问题和一段带行号的剧情原文，找出与回答该问题'
          '有关的行（人物动作、对话中的事实、因果、时间、身份等）。\n'
          '每条一行，严格格式：L<行号>: <该行表明的事实，不超过40字>\n'
          '最多 $maxNotes 条，只能使用给出的行号；没有相关内容时只输出 NONE。',
        ),
        Message.user('问题：$userQuery\n\n剧情 ${page.storyId}：\n$numbered'),
      ],
      temperature: 0,
      maxTokens: 512,
    );
  } catch (_) {
    return const [];
  }
  return parseEvidenceNotes(result.content, page, maxNotes: maxNotes);
}

final RegExp _noteRow = RegExp(r'^\s*L?(\d+)\s*[:：]\s*(.+?)\s*$', multiLine: true);

/// Parses extractor output into notes anchored to [page]; exposed for tests.
List<EvidenceNote> parseEvidenceNotes(
  String raw,
  ReadPage page, {
  int maxNotes = 6,
}) {
  final notes = <EvidenceNote>[];
  for (final match in _noteRow.allMatches(raw)) {
    if (notes.length >= maxNotes) break;
    final line = page.line(int.parse(match.group(1)!));
    if (line == null) continue; // hallucinated line number
    notes.add(EvidenceNote(
      storyId: page.storyId,
      line: line.index,
      fact: _clip(match.group(2)!, _maxFactChars),
      quote: _clip(line.text, _maxQuoteChars),
    ),);
  }
  return notes;
}

String _clip(String text, int max) {
  final normalized = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  return normalized.length <= max
      ? normalized
      : '${normalized.substring(0, max)}…';
}

/// `story_id:line` or `story_id:start-end` citations (story ids end in .txt).
final RegExp _citation =
    RegExp(r'([\w\-/\.\[\]]+\.txt)\s*[:：]\s*(\d+)(?:\s*[-–~]\s*(\d+))?');

/// Returns the citations in [answer] that point at lines never actually read
/// in [state]. A range is invalid when any of its lines was not read.
List<String> unreadCitations(String answer, InvestigationState state) {
  final invalid = <String>{};
  for (final match in _citation.allMatches(answer)) {
    final storyId = match.group(1)!;
    final start = int.parse(match.group(2)!);
    final end = int.tryParse(match.group(3) ?? '') ?? start;
    final hi = end < start ? start : end;
    var ok = true;
    for (var line = start; line <= hi && line - start < 500; line++) {
      if (!state.wasLineRead(storyId, line)) {
        ok = false;
        break;
      }
    }
    if (!ok) invalid.add(match.group(0)!);
  }
  return invalid.toList()..sort();
}
