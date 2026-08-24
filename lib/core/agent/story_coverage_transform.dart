/// Coverage report validation for narrative Summary answers (R1 / AI
/// retrieval P0).
///
/// The model must end narrative answers with a truthful coverage line:
///
/// ```text
/// Coverage: read=<实际精读 scope 数> | mapped=<仅浏览画像的 scope 数> | skipped=<未读+原因>
/// ```
///
/// Because the final answer is not trustworthy by itself, this transform
/// recomputes the counts from the actual tool observations (which carry
/// machine-readable markers) and rewrites the line to the honest values.
/// A model claiming to have read chapters it never read is corrected; a
/// missing line is appended; answers that never used the coverage tools are
/// left untouched.
library;

/// Pattern for the `Coverage:` report line (public for UI display stripping).
final RegExp coverageReportLinePattern = RegExp(
  r'Coverage:\s*read=\s*([^|]*?)\s*\|\s*mapped=\s*([^|]*?)\s*\|\s*skipped=(.*)',
  caseSensitive: false,
);

final RegExp _coverageLinePattern = coverageReportLinePattern;

final RegExp _scopeMarkerPattern = RegExp(
  r'^Scope:\s*(\S+)',
  multiLine: true,
);

/// Parsed `Coverage:` report line.
class CoverageReportLine {
  const CoverageReportLine({
    required this.read,
    required this.mapped,
    required this.skipped,
  });
  final String read;
  final String mapped;
  final String skipped;
}

/// Parses the `Coverage: read=.. | mapped=.. | skipped=..` line; null when
/// absent or malformed.
CoverageReportLine? parseCoverageReportLine(String content) {
  final match = _coverageLinePattern.firstMatch(content);
  if (match == null) return null;
  return CoverageReportLine(
    read: match.group(1)!.trim(),
    mapped: match.group(2)!.trim(),
    skipped: match.group(3)!.trim(),
  );
}

/// Validates the `Coverage:` line of [answer] against [observations].
String validateCoverageReport(String answer, List<String> observations) {
  final readScopes = _scopesWithMarker(observations, 'Read Lines:');
  final mappedScopes = _scopesWithMarker(observations, 'Mapped Stories:');
  final coveredScopes = _scopesWithMarker(observations, 'Coverage Scopes:');

  final hasCoverageActivity = readScopes.isNotEmpty ||
      mappedScopes.isNotEmpty ||
      coveredScopes.isNotEmpty;
  if (!hasCoverageActivity) return answer;

  final total = coveredScopes.length;
  final read = readScopes.length;
  final mapped = mappedScopes.length;
  final skipped = total > 0
      ? '${(total - read - mapped).clamp(0, total)}'
      : 'unknown';
  final honestLine = 'Coverage: read=$read | mapped=$mapped | skipped=$skipped';

  final match = _coverageLinePattern.firstMatch(answer);
  if (match == null) {
    return '$answer\n\n$honestLine';
  }
  return answer.replaceRange(match.start, match.end, honestLine);
}

/// Distinct `Scope:` keys from observations that carry [marker].
Set<String> _scopesWithMarker(List<String> observations, String marker) {
  final scopes = <String>{};
  for (final observation in observations) {
    if (!observation.contains(marker)) continue;
    for (final match in _scopeMarkerPattern.allMatches(observation)) {
      final scope = match.group(1);
      if (scope != null && scope.isNotEmpty) scopes.add(scope);
    }
  }
  return scopes;
}
