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
String? loreAnswerMarkdown(String content) => loreAnswerParsed(content)?.markdown;

/// [loreAnswerMarkdown] plus how many citation items of the answer gave no
/// usable ref (written in a shape that cannot be read).
///
/// 0.14 live: a weaker model wrote prose quoting the format's skeleton,
/// two partial versions and then the whole answer, all in one reply. Every
/// start is tried and the last complete object with entries wins (else
/// the first start, as before).
({String markdown, int dropped})? loreAnswerParsed(String content) {
  final starts = loreAnswerJsonStart.allMatches(content).toList();
  if (starts.isEmpty) return null;
  ({String markdown, int dropped}) parse(int at, [LoreAnswerStream? s]) {
    final stream = s ?? (LoreAnswerStream()..add(content.substring(at)));
    return (markdown: stream.finish(), dropped: stream.droppedCites);
  }

  for (final start in starts.reversed) {
    final stream = LoreAnswerStream()..add(content.substring(start.start));
    if (stream.complete && stream.hasEntries) return parse(start.start, stream);
  }
  return parse(starts.first.start);
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
  // Scalars written directly inside `cite` (the flat form), grouped when the
  // array closes or a nested tuple starts.
  final List<Object?> _flat = [];
  String? _verdict;
  String? _coverage;
  bool _hasGaps = false; // a non-empty "gaps" text says something is missing

  /// Citation items that gave no usable ref (the answer lost them).
  int droppedCites = 0;

  /// Markdown produced so far.
  String get markdown => _md.toString();

  /// The object has closed (its last brace came).
  bool get complete => _closed;

  /// At least one heading or text entry was written.
  bool get hasEntries => _md.toString().trim().isNotEmpty;

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
      if (_hasGaps)
        '[COVERAGE: gaps]'
      else if (_coverage != null)
        '[COVERAGE: ${_coverage!.trim()}]',
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
      if (_streamKey == 'gaps' && c.trim().isNotEmpty) _hasGaps = true;
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
    if (role == _Role.tuple || role == _Role.ignore) _flushFlat();
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
        _flat.add(value);
      case (_Role.tuple, _):
        _tuple.add(value);
      default:
        break;
    }
  }

  void _endScalar() {
    final raw = _scalar.toString();
    _scalar.clear();
    if (_stack.isEmpty) return;
    final value = int.tryParse(raw) ?? raw;
    if (_stack.last.role == _Role.tuple) {
      _tuple.add(value);
    } else if (_stack.last.role == _Role.cites) {
      _flat.add(value);
    }
  }

  void _closeFrame(_Frame frame) {
    if (frame.role == _Role.tuple) {
      _cite(List.of(_tuple));
      _tuple.clear();
    } else if (frame.role == _Role.cites) {
      _flushFlat();
    }
  }

  void _flushFlat() {
    if (_flat.isEmpty) return;
    final items = List.of(_flat);
    _flat.clear();
    for (final ref in loreCitationRefs(items, onDropped: () => droppedCites++)) {
      _openEntryBlock();
      _md.write(' `$ref`');
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
    final ref = loreCitationRef(parts);
    if (ref == null) {
      droppedCites++;
      return;
    }
    _openEntryBlock();
    _md.write(' `$ref`');
  }
}

// Story lines may be written "L97", wiki paragraphs "P3".
final RegExp _lineRange = RegExp(
  r'^\s*[LP]?(\d+)(?:\s*[-–~—]\s*[LP]?(\d+))?\s*$',
  caseSensitive: false,
);

/// A line number, or a "97-127" / "L97" string, read as (start, end).
(int, int)? _lineSpan(Object? v) {
  if (v is num) return (v.toInt(), v.toInt());
  final m = _lineRange.firstMatch('$v');
  if (m == null) return null;
  final a = int.parse(m.group(1)!);
  return (a, m.group(2) == null ? a : int.parse(m.group(2)!));
}

final RegExp _recordPrefixes = RegExp(r'^(?:record:)+');

/// `story_id:a-b` / `record:id` / `wiki:<page id>:a-b` (0.13: a wiki page's
/// paragraphs, cited like a story's lines) of a citation tuple, or null.
/// Also reads the slightly different shapes models write: lines as "L97" or
/// "97-127", a story id without `.txt`, a reversed range.
String? loreCitationRef(List<Object?> parts) {
  if (parts.isEmpty) return null;
  var first = '${parts.first}'.trim().replaceAll('`', '');
  if (first == 'record' && parts.length > 1) {
    return 'record:${'${parts[1]}'.trim().replaceFirst(_recordPrefixes, '')}';
  }
  if (parts.length == 1) {
    // Written as one string ("story_id:3-5" / "record:id"); 0.14: the
    // prefix written twice ("record:record:id", the id being shown as
    // `record:id`) counts once.
    if (first.startsWith(_recordPrefixes)) {
      return 'record:${first.replaceFirst(_recordPrefixes, '')}';
    }
    return first.contains(':') ? first : null;
  }
  final span = _lineSpan(parts[1]);
  if (span == null) return null;
  var a = span.$1;
  var b = span.$2;
  if (parts.length > 2) {
    final end = _lineSpan(parts[2]);
    if (end != null) b = end.$2;
  }
  if (b < a) (a, b) = (b, a);
  if (!first.contains('.') && !first.startsWith('wiki:')) first = '$first.txt';
  return b == a ? '$first:$a' : '$first:$a-$b';
}

/// The citation refs of a whole `cite` array. Besides the nested form
/// (`[["id", 1, 2], ...]`) it accepts the flat form some models write
/// (`["id", 1, 2]`, also several in a row) and plain strings (`"id:1-2"`).
/// [onDropped] is called once per item that gave no ref.
List<String> loreCitationRefs(List<Object?> items, {void Function()? onDropped}) {
  final out = <String>[];
  var group = <Object?>[];
  void add(String? ref) {
    if (ref == null) {
      onDropped?.call();
    } else if (!out.contains(ref)) {
      out.add(ref);
    }
  }

  void flush() {
    if (group.isEmpty) return;
    add(loreCitationRef(group));
    group = [];
  }

  for (final item in items) {
    if (item is List) {
      flush();
      add(loreCitationRef(item));
    } else if (item is! String && item is! num) {
      flush();
      onDropped?.call(); // an object or other shape that is not a citation
    } else if (item is num || (item is String && _lineRange.hasMatch(item))) {
      if (group.isEmpty) {
        onDropped?.call();
      } else {
        group.add(item);
      }
    } else if (group.length == 1 && '${group.first}'.trim() == 'record') {
      group.add(item);
    } else {
      flush();
      group = ['$item'];
    }
  }
  flush();
  return out;
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
