const String speakerLinkScheme = 'arklores-speaker';

class _Node {
  final children = <int, _Node>{};
  String? name;
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

  String linkNames(String markdown) {
    if (markdown.isEmpty || _root.children.isEmpty) return markdown;
    final out = StringBuffer();
    final seen = <String>{};
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
      var node = _root;
      String? match;
      var j = i;
      while (j < markdown.length) {
        final next = node.children[markdown.codeUnitAt(j)];
        if (next == null) break;
        node = next;
        j++;
        if (node.name != null) match = node.name;
      }
      if (match == null) {
        out.write(c);
        i++;
      } else {
        if (seen.add(match)) {
          final label =
              match.replaceAllMapped(RegExp(r'[\[\]\\]'), (m) => '\\${m[0]}');
          out.write(
            '[$label]($speakerLinkScheme:${Uri.encodeComponent(match)})',
          );
        } else {
          out.write(match);
        }
        i += match.length;
      }
    }
    return out.toString();
  }

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
