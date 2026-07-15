class EvidenceRecord {
  final String title;
  final String? section;
  final String? contentType;
  final String? sourcePath;
  final String? rawId;
  final String retrievalType;
  final String rankingReason;
  final String trustNote;
  final String excerpt;
  final bool isDirectCandidate;

  const EvidenceRecord({
    required this.title,
    this.section,
    this.contentType,
    this.sourcePath,
    this.rawId,
    required this.retrievalType,
    required this.rankingReason,
    required this.trustNote,
    required this.excerpt,
    required this.isDirectCandidate,
  });
}

List<EvidenceRecord> parseGameDataEvidence(String observation) {
  if (!observation.contains('Source Kind: GameData')) return const [];
  final blocks = observation.split(RegExp(r'(?==== Result #\d+)'));
  return blocks.map(_parseBlock).whereType<EvidenceRecord>().toList();
}

EvidenceRecord? _parseBlock(String block) {
  if (!block.startsWith('=== Result #') ||
      !block.contains('Source Kind: GameData')) {
    return null;
  }
  final fields = <String, String>{};
  final excerpt = StringBuffer();
  var readingExcerpt = false;
  for (final line in block.split('\n')) {
    if (line == 'Content Excerpt:') {
      readingExcerpt = true;
      continue;
    }
    if (readingExcerpt) {
      excerpt.writeln(line);
      continue;
    }
    final separator = line.indexOf(': ');
    if (separator > 0) {
      fields[line.substring(0, separator)] = line.substring(separator + 2);
    }
  }
  final title = fields['Title'];
  final retrievalType = fields['Retrieval Type'];
  final rankingReason = fields['Ranking Reason'];
  final trust = fields['Trust'];
  if (title == null ||
      retrievalType == null ||
      rankingReason == null ||
      trust == null) {
    return null;
  }
  return EvidenceRecord(
    title: title,
    section: fields['Section'],
    contentType: fields['Content Type'],
    sourcePath: fields['Source Path'],
    rawId: fields['Raw ID'],
    retrievalType: retrievalType,
    rankingReason: rankingReason,
    trustNote: trust,
    excerpt: excerpt.toString().trim(),
    isDirectCandidate: fields['Evidence Level'] == 'direct candidate',
  );
}
