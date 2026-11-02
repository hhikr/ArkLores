const String speakerLinkScheme = 'arklores-speaker';

class _Node {
  final children = <int, _Node>{};
  String? name;
}

/// A stretch of plain text: a name, or what lies between names.
class NameRun {
  const NameRun(this.text, {this.isName = false});
  final String text;
  final bool isName;
}

/// Longest, non-overlapping name matches outside Markdown syntax.
class SpeakerMatcher {
  SpeakerMatcher(Iterable<String> names) {
    for (final name in names) {
      if (name.runes.length < 2) continue;
      var node = _root;
      for (final unit in name.codeUnits) {
        node = node.children.putIfAbsent(unit, _Node.new);
      }
      node.name = name;
    }
  }

  final _root = _Node();

  /// [text] cut into the names in it and what lies between them.
  List<NameRun> runs(String text) {
    final result = <NameRun>[];
    var start = 0, i = 0;
    while (i < text.length) {
      final match = _nameAt(text, i);
      if (match == null) {
        i++;
        continue;
      }
      if (i > start) result.add(NameRun(text.substring(start, i)));
      result.add(NameRun(match, isName: true));
      i += match.length;
      start = i;
    }
    if (start < text.length) result.add(NameRun(text.substring(start)));
    return result;
  }

  String? _nameAt(String text, int start) {
    var node = _root;
    String? match;
    var j = start;
    while (j < text.length) {
      final next = node.children[text.codeUnitAt(j)];
      if (next == null) break;
      node = next;
      j++;
      if (node.name != null && !_insideWord(text, start, j)) {
        match = node.name;
      }
    }
    return match;
  }

  String linkNames(String markdown) {
    if (markdown.isEmpty || _root.children.isEmpty) return markdown;
    final out = StringBuffer();
    var i = 0;
    while (i < markdown.length) {
      var end = i;
      final c = markdown[i];
      if ((i == 0 || markdown[i - 1] == '\n') && c == '#') {
        end = markdown.indexOf('\n', i);
        if (end < 0) end = markdown.length;
      } else if (c == '`') {
        var ticks = 1;
        while (i + ticks < markdown.length && markdown[i + ticks] == '`') {
          ticks++;
        }
        final marker = '`' * ticks;
        final close = markdown.indexOf(marker, i + ticks);
        end = close < 0 ? markdown.length : close + ticks;
      } else if (c == '<') {
        final close = markdown.indexOf('>', i + 1);
        if (close >= 0) end = close + 1;
      } else if (c == '[' ||
          (c == '!' && i + 1 < markdown.length && markdown[i + 1] == '[')) {
        end = _linkEnd(markdown, c == '!' ? i + 1 : i);
      }
      if (end > i) {
        out.write(markdown.substring(i, end));
        i = end;
        continue;
      }
      final match = _nameAt(markdown, i);
      if (match == null) {
        out.write(c);
        i++;
      } else {
        final label =
            match.replaceAllMapped(RegExp(r'[\[\]\\]'), (m) => '\\${m[0]}');
        out.write(
          '[$label]($speakerLinkScheme:${Uri.encodeComponent(match)})',
        );
        i += match.length;
      }
    }
    return out.toString();
  }

  static final _latin = RegExp('[A-Za-z0-9]');

  /// A Latin name is a match only as a whole word ("Ace" in "Space" is
  /// not); a Chinese name has no word boundaries to check.
  static bool _insideWord(String text, int start, int end) =>
      (_latin.hasMatch(text[start]) &&
          start > 0 &&
          _latin.hasMatch(text[start - 1])) ||
      (_latin.hasMatch(text[end - 1]) &&
          end < text.length &&
          _latin.hasMatch(text[end]));

  int _linkEnd(String text, int start) {
    var depth = 1;
    var i = start + 1;
    for (; i < text.length && depth > 0; i++) {
      if (text[i] == '\\') {
        i++;
        continue;
      }
      if (text[i] == '[') depth++;
      if (text[i] == ']') depth--;
    }
    if (depth != 0 || i >= text.length || text[i] != '(') return start;
    depth = 1;
    for (i++; i < text.length; i++) {
      if (text[i] == '\\') {
        i++;
        continue;
      }
      if (text[i] == '(') depth++;
      if (text[i] == ')' && --depth == 0) return i + 1;
    }
    return start;
  }
}
