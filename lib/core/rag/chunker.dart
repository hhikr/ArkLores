import 'package:uuid/uuid.dart';

/// A single chunk of text produced by [Chunker].
///
/// Each chunk carries metadata about its origin (page, section, sequence)
/// so the retrieval layer can present context alongside the content.
class Chunk {
  final String id;
  final String content;
  final String pageTitle;
  final String section;
  final int seqIndex;
  final int tokenCount;

  Chunk({
    String? id,
    required this.content,
    required this.pageTitle,
    this.section = '',
    required this.seqIndex,
    required this.tokenCount,
  }) : id = id ?? const Uuid().v4();

  Map<String, dynamic> toMap() => {
        'id': id,
        'content': content,
        'page_title': pageTitle,
        'section': section,
        'seq_index': seqIndex,
        'token_count': tokenCount,
      };

  factory Chunk.fromMap(Map<String, dynamic> map) => Chunk(
        id: map['id'] as String,
        content: map['content'] as String,
        pageTitle: map['page_title'] as String,
        section: (map['section'] as String?) ?? '',
        seqIndex: map['seq_index'] as int,
        tokenCount: (map['token_count'] as int?) ?? _estimateTokens(map['content'] as String),
      );

  @override
  String toString() => 'Chunk($id, "$pageTitle" / "$section", #$seqIndex, ${tokenCount}tok)';
}

/// Rough token count estimation for mixed Chinese/English text.
///
/// - English: ~1 token per 1.3 words
/// - Chinese: ~1 token per 1.8 characters
/// - Mixed: weighted average
int _estimateTokens(String text) {
  if (text.isEmpty) return 0;

  int chineseChars = 0;
  int englishWords = 0;
  bool inWord = false;

  for (final ch in text.codeUnits) {
    // CJK Unified Ideographs (0x4E00–0x9FFF) and CJK Extension A (0x3400–0x4DBF).
    if ((ch >= 0x4E00 && ch <= 0x9FFF) || (ch >= 0x3400 && ch <= 0x4DBF)) {
      chineseChars++;
      if (inWord) {
        englishWords++;
        inWord = false;
      }
    } else if (ch == 0x20 || ch == 0x0A || ch == 0x0D) {
      // Space, newline, carriage return → word boundary.
      if (inWord) {
        englishWords++;
        inWord = false;
      }
    } else if (ch >= 0x41 && ch <= 0x5A || ch >= 0x61 && ch <= 0x7A) {
      // ASCII letter.
      inWord = true;
    } else {
      if (inWord) {
        inWord = false;
        englishWords++;
      }
    }
  }
  if (inWord) englishWords++;

  final enTokens = englishWords / 1.3;
  final zhTokens = chineseChars / 1.8;

  return (enTokens + zhTokens).round().clamp(1, 10000);
}

/// Detects whether [line] is a Markdown heading.
///
/// Supports:
/// - `# Heading` / `## Heading` / `### Heading` etc.
/// - `=====` overline (level 1)
/// - `------` overline (level 2)
(String text, int level, bool isHeading)? _detectHeading(String line) {
  // Atx-style: # ## ### etc.
  final atxMatch = RegExp(r'^(#{1,6})\s+(.+)$').matchAsPrefix(line);
  if (atxMatch != null) {
    return (atxMatch.group(2)!, atxMatch.group(1)!.length, true);
  }
  return null;
}

/// Configuration for [Chunker].
class ChunkerConfig {
  /// Target token count per chunk.
  final int targetTokens;

  /// Overlap token count between adjacent chunks (sliding-window mode).
  final int overlapTokens;

  /// Maximum characters to consider per chunk (safety limit).
  final int maxChars;

  const ChunkerConfig({
    this.targetTokens = 500,
    this.overlapTokens = 50,
    this.maxChars = 4000,
  });
}

/// Text chunker that splits documents into passages suitable for embedding.
///
/// Two strategies:
/// 1. **Heading-based** — splits by Markdown headings, keeping each section
///    intact (further split with sliding window if oversize).
/// 2. **Sliding-window** — splits long plain text into fixed-size windows
///    with configurable overlap.
class Chunker {
  final ChunkerConfig config;

  const Chunker({this.config = const ChunkerConfig()});

  /// Returns the estimated token count for [text].
  int estimateTokens(String text) => _estimateTokens(text);

  /// Splits [text] into chunks using heading boundaries.
  ///
  /// Each heading section becomes one chunk (or multiple if oversize).
  /// The [pageTitle] is attached to every chunk for provenance.
  List<Chunk> chunkByHeadings(String text, {String pageTitle = ''}) {
    if (text.trim().isEmpty) return [];

    final lines = text.split('\n');
    final sections = <_Section>[];
    _Section? current;

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final heading = _detectHeading(line);

      if (heading != null) {
        if (current != null) {
          sections.add(current);
        }
        current = _Section(
          heading: heading.text,
          level: heading.level,
          content: '',
        );
      } else {
        current ??= _Section(heading: pageTitle, level: 1, content: '');
        current.content += (current.content.isEmpty ? '' : '\n') + line;
      }
    }
    if (current != null) sections.add(current);

    // If no headings were found, fall back to sliding window.
    if (sections.isEmpty || (sections.length == 1 && sections.first.heading == pageTitle && _estimateTokens(text) > config.targetTokens)) {
      return chunkBySliding(text, pageTitle: pageTitle);
    }

    // Flatten sections into chunks, splitting oversize ones.
    final chunks = <Chunk>[];
    var seqIndex = 0;

    for (final section in sections) {
      final sectionContent = section.content.trim();
      if (sectionContent.isEmpty) continue;

      final estimatedTokens = _estimateTokens(sectionContent);
      final sectionTitle = section.heading;

      if (estimatedTokens <= config.targetTokens) {
        chunks.add(Chunk(
          content: sectionContent,
          pageTitle: pageTitle,
          section: sectionTitle,
          seqIndex: seqIndex++,
          tokenCount: estimatedTokens,
        ));
      } else {
        // Oversize section — split further with sliding window.
        final subChunks = _splitText(
          sectionContent,
          pageTitle: pageTitle,
          section: sectionTitle,
          startIndex: seqIndex,
        );
        chunks.addAll(subChunks);
        seqIndex += subChunks.length;
      }
    }

    return chunks;
  }

  /// Splits [text] into fixed-size sliding windows.
  ///
  /// Use for plain text without heading structure.
  List<Chunk> chunkBySliding(String text, {String pageTitle = ''}) {
    if (text.trim().isEmpty) return [];

    return _splitText(
      text,
      pageTitle: pageTitle,
      section: pageTitle,
      startIndex: 0,
    );
  }

  /// Internal sliding-window splitter.
  List<Chunk> _splitText(
    String text, {
    required String pageTitle,
    required String section,
    required int startIndex,
  }) {
    final chunks = <Chunk>[];
    final approxCharsPerChunk = (config.targetTokens * 1.8).round();
    final overlapChars = (config.overlapTokens * 1.8).round();
    final step = approxCharsPerChunk - overlapChars;

    if (step <= 0) return chunks;

    int pos = 0;
    int seqIndex = startIndex;

    while (pos < text.length) {
      final end = (pos + approxCharsPerChunk).clamp(0, text.length);
      final content = text.substring(pos, end).trim();
      if (content.isEmpty) break;
      if (content.length < 20 && pos + approxCharsPerChunk >= text.length) {
        // Skip near-empty tail fragment.
        break;
      }

      chunks.add(Chunk(
        content: content,
        pageTitle: pageTitle,
        section: section,
        seqIndex: seqIndex++,
        tokenCount: _estimateTokens(content),
      ));

      pos += step;
      if (pos >= text.length) break;
    }

    return chunks;
  }
}

/// Internal section parsed from markdown headings.
class _Section {
  final String heading;
  final int level;
  String content;

  _Section({
    required this.heading,
    required this.level,
    required this.content,
  });
}
