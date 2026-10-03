/// R17c: the story agent's final answer as JSON.
///
/// The model writes one object:
///
/// ```json
/// {"verdict": "...",                       // fact check only
///  "entries": [{"heading": "..."},
///              {"text": "...", "cite": [["<story_id>", 12, 30], ["record", "<id>"]]}],
///  "coverage": "full|gaps", "gaps": "..."}
/// ```
///
/// [LoreAnswerStream] turns it into the answer markdown the rest of the app
/// reads (each entry's citations at its end, as `story_id:a-b` /
/// `record:id`), chunk by chunk so the answer can stream. Entries before the
/// first heading become paragraphs, later ones list items.
library;

/// Start of a JSON answer: `{` followed by one of its keys.
final RegExp loreAnswerJsonStart =
    RegExp(r'\{\s*"(?:verdict|entries|coverage|gaps)"');

/// The markdown of a complete JSON answer in [content], or null when
/// [content] holds no JSON answer (the model wrote markdown instead).
String? loreAnswerMarkdown(String content) {
  final start = loreAnswerJsonStart.firstMatch(content);
  if (start == null) return null;
  final stream = LoreAnswerStream()..add(content.substring(start.start));
  return stream.finish();
}

enum _Role { root, entries, entry, cites, tuple, ignore }

class _Frame {
  _Frame(this.role, {required this.isObject});
  final _Role role;
  final bool isObject;
  String? key;
  bool expectKey = true;
}

enum _Block { none, heading, item, paragraph }

/// Incremental JSON answer → markdown. [add] returns the markdown appended
/// by each chunk; [finish] the whole answer (with the fact-check verdict
/// first and the coverage line last).
class LoreAnswerStream {
  final StringBuffer _md = StringBuffer();
  final List<_Frame> _stack = [];
  bool _started = false;
  bool _closed = false;

  // Lexer state.
  bool _inString = false;
  bool _stringIsKey = false;
  bool _escape = false;
  StringBuffer? _unicode;
  final StringBuffer _key = StringBuffer();
  final StringBuffer _scalar = StringBuffer();

  // Value being collected (verdict, coverage, citation strings).
  StringBuffer? _collect;
  String? _streamKey; // 'heading' | 'text' | 'gaps' while streaming a string

  // Output state.
  _Block _last = _Block.none;
  bool _sectionOpen = false;
  bool _entryOpen = false; // the current entry has started its block
  final List<Object?> _tuple = [];
  String? _verdict;
  String? _coverage;

  /// Markdown produced so far.
  String get markdown => _md.toString();

  /// Feeds [chunk]; returns the markdown it added.
  String add(String chunk) {
    final before = _md.length;
    for (var i = 0; i < chunk.length; i++) {
      _char(chunk[i]);
    }
    return _md.toString().substring(before);
  }

  /// The complete answer markdown.
  String finish() {
    if (_scalar.isNotEmpty) _endScalar();
    final body = _md.toString().trim();
    return [
      if (_verdict != null) '[FACT_CHECK_VERDICT:${_verdict!.trim()}]',
      if (body.isNotEmpty) body,
      if (_coverage != null) '[COVERAGE: ${_coverage!.trim()}]',
    ].join('\n\n');
  }

  void _char(String c) {
    if (_closed) return;
    if (!_started) {
      if (c == '{') {
        _started = true;
        _stack.add(_Frame(_Role.root, isObject: true));
      }
      return;
    }
    if (_inString) return _stringChar(c);
    if (_scalar.isNotEmpty) {
      if (',}] \n\r\t'.contains(c)) {
        _endScalar();
      } else {
        _scalar.write(c);
        return;
      }
    }
    final top = _stack.last;
    switch (c) {
      case '{':
      case '[':
        final role = _childRole(top, isObject: c == '{');
        _openValue(top, role);
        _stack.add(_Frame(role, isObject: c == '{'));
      case '}':
      case ']':
        final frame = _stack.removeLast();
        _closeFrame(frame);
        if (_stack.isEmpty) _closed = true;
      case '"':
        _inString = true;
        _stringIsKey = top.isObject && top.expectKey;
        if (_stringIsKey) {
          _key.clear();
        } else {
          _startString(top);
        }
      case ',':
        if (top.isObject) top.expectKey = true;
      case ':':
        if (top.isObject) top.expectKey = false;
      default:
        if (c.trim().isEmpty) return;
        _scalar.write(c);
    }
  }

  void _stringChar(String c) {
    if (_unicode != null) {
      _unicode!.write(c);
      if (_unicode!.length == 4) {
        final code = int.tryParse(_unicode.toString(), radix: 16);
        _unicode = null;
        if (code != null) _decoded(String.fromCharCode(code));
      }
      return;
    }
    if (_escape) {
      _escape = false;
      switch (c) {
        case 'u':
          _unicode = StringBuffer();
        case 'n':
        case 'r':
        case 't':
          _decoded(' ');
        case 'b':
        case 'f':
          break;
        default:
          _decoded(c); // \" \\ \/
      }
      return;
    }
    if (c == '\\') {
      _escape = true;
    } else if (c == '"') {
      _inString = false;
      if (_stringIsKey) {
        _stack.last
          ..key = _key.toString()
          ..expectKey = false;
      } else {
        _endString();
      }
    } else {
      _decoded(c == '\n' || c == '\r' ? ' ' : c);
    }
  }

  void _decoded(String c) {
    if (_stringIsKey) {
      _key.write(c);
    } else if (_collect != null) {
      _collect!.write(c);
    } else if (_streamKey != null) {
      _md.write(c);
    }
  }

  _Role _childRole(_Frame parent, {required bool isObject}) =>
      switch ((parent.role, parent.key, isObject)) {
        (_Role.root, 'entries', false) => _Role.entries,
        (_Role.entries, _, true) => _Role.entry,
        (_Role.entry, 'cite', false) => _Role.cites,
        (_Role.cites, _, false) => _Role.tuple,
        _ => _Role.ignore,
      };

  /// A value (container or string) starts inside [parent].
  void _openValue(_Frame parent, _Role role) {
    if (role == _Role.entry) _entryOpen = false;
    if (role == _Role.cites) _openEntryBlock();
  }

  void _startString(_Frame parent) {
    _collect = null;
    _streamKey = null;
    switch ((parent.role, parent.key)) {
      case (_Role.root, 'verdict'):
      case (_Role.root, 'coverage'):
      case (_Role.cites, _):
      case (_Role.tuple, _):
        _collect = StringBuffer();
      case (_Role.root, 'gaps'):
        _block(_Block.paragraph);
        _streamKey = 'gaps';
      case (_Role.entry, 'heading'):
        _block(_Block.heading);
        _md.write('## ');
        _sectionOpen = true;
        _entryOpen = false;
        _streamKey = 'heading';
      case (_Role.entry, 'text'):
        _openEntryBlock(force: true);
        _streamKey = 'text';
      default:
        break;
    }
  }

  void _endString() {
    final parent = _stack.last;
    final value = _collect?.toString();
    _collect = null;
    _streamKey = null;
    if (value == null) return;
    switch ((parent.role, parent.key)) {
      case (_Role.root, 'verdict'):
        _verdict = value;
      case (_Role.root, 'coverage'):
        _coverage = value;
      case (_Role.cites, _):
        _cite([value]);
      case (_Role.tuple, _):
        _tuple.add(value);
      default:
        break;
    }
  }

  void _endScalar() {
    final raw = _scalar.toString();
    _scalar.clear();
    if (_stack.isNotEmpty && _stack.last.role == _Role.tuple) {
      _tuple.add(int.tryParse(raw) ?? raw);
    }
  }

  void _closeFrame(_Frame frame) {
    if (frame.role == _Role.tuple) {
      _cite(List.of(_tuple));
      _tuple.clear();
    }
  }

  /// Starts the current entry's block (a list item after a heading, a
  /// paragraph before one). [force]: a text after a heading in the same
  /// entry starts a new block.
  void _openEntryBlock({bool force = false}) {
    if (_entryOpen && !force) return;
    if (_entryOpen && force && _last != _Block.heading) return;
    _block(_sectionOpen ? _Block.item : _Block.paragraph);
    if (_sectionOpen) _md.write('- ');
    _entryOpen = true;
  }

  void _block(_Block kind) {
    if (_md.isNotEmpty) {
      _md.write(kind == _Block.item && _last == _Block.item ? '\n' : '\n\n');
    }
    _last = kind;
  }

  /// Appends one citation (a tuple, or a single string) to the entry.
  void _cite(List<Object?> parts) {
    final ref = _citationRef(parts);
    if (ref == null) return;
    _openEntryBlock();
    _md.write(' `$ref`');
  }
}

/// `story_id:a-b` / `record:id` of a citation tuple, or null.
String? _citationRef(List<Object?> parts) {
  if (parts.isEmpty) return null;
  final first = '${parts.first}'.trim().replaceAll('`', '');
  if (first == 'record' && parts.length > 1) return 'record:${parts[1]}';
  if (parts.length == 1) {
    // Written as one string ("story_id:3-5" / "record:id").
    return first.contains(':') ? first : null;
  }
  int? line(Object? v) => v is int ? v : int.tryParse('$v'.trim());
  final a = line(parts[1]);
  if (a == null) return null;
  final b = parts.length > 2 ? line(parts[2]) ?? a : a;
  return b == a ? '$first:$a' : '$first:$a-$b';
}

final RegExp _quotedSpan =
    RegExp(r'“([^”\n]{1,300})”|「([^」\n]{1,300})」|『([^』\n]{1,300})』|"([^"\n]{1,300})"');
final RegExp _notWordChar = RegExp(r'[^\p{L}\p{N}]', unicode: true);

/// R17c: quoted passages of [answer] that copy original lines — the text in
/// quotation marks matches [sourceText] (the lines the answer cites)
/// verbatim or nearly so. Phrases under five characters are not counted.
List<String> quotedSourceLines(String answer, String sourceText) {
  final source = sourceText.replaceAll(_notWordChar, '');
  if (source.isEmpty) return const [];
  final found = <String>[];
  for (final m in _quotedSpan.allMatches(answer)) {
    final span = [m.group(1), m.group(2), m.group(3), m.group(4)]
        .firstWhere((g) => g != null)!;
    final norm = span.replaceAll(_notWordChar, '');
    if (norm.length < 5) continue;
    var copied = source.contains(norm);
    if (!copied) {
      var hits = 0;
      for (var i = 0; i + 1 < norm.length; i++) {
        if (source.contains(norm.substring(i, i + 2))) hits++;
      }
      copied = hits / (norm.length - 1) >= 0.7;
    }
    if (copied && !found.contains(span)) found.add(span);
  }
  return found;
}
