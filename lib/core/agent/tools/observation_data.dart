/// Machine-readable DATA block contract for investigation tools (R3,
/// design decision 1 in `docs/R3_DESIGN_DECISIONS.md`).
///
/// Tools append a single-line `DATA: <json>` block at the end of their
/// observation. Transforms parse the JSON with priority and fall back to text
/// markers when parsing fails. The JSON is produced by the tool, never by the
/// model, so its shape is reliable.
library;

import 'dart:convert';

const String dataBlockPrefix = 'DATA: ';

/// Appends a JSON data block to an observation text.
String appendDataBlock(String observation, Map<String, Object?> data) {
  final json = const JsonEncoder().convert(data);
  return '$observation\n\n$dataBlockPrefix$json';
}

/// Parses every DATA block in [text] (a single observation or observations
/// joined with newlines). Malformed blocks are skipped (text-marker fallback
/// applies).
List<Map<String, Object?>> parseDataBlocks(String text) {
  final blocks = <Map<String, Object?>>[];
  for (final line in text.split('\n')) {
    final trimmed = line.trim();
    if (!trimmed.startsWith(dataBlockPrefix)) continue;
    final raw = trimmed.substring(dataBlockPrefix.length);
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        blocks.add(decoded.cast<String, Object?>());
      }
    } on FormatException {
      // Not a JSON block; ignore.
    }
  }
  return blocks;
}
