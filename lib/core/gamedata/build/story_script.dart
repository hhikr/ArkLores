/// Parser of the story script format (`story/**/*.txt` of the upstream repo).
///
/// A script line is either plain text (narration) or a bracketed command,
/// optionally followed by text: `[name="X"]text`, `[dialog(head=…)]text`,
/// `[Subtitle(text="…", …)]`, `[Decision(options="a;b")]`. The importer used
/// to keep only `[name="X"]text` and plain lines and dropped every other
/// command, which lost scene subtitles, letters and diaries (`Sticker`), the
/// player's choices and several dialogue spellings (about 4% of the lines,
/// including most of the main story's captions).
///
/// This parser is generic over the command set: it reads text from the
/// commands that carry text and ignores the rest (camera, music, delays…).
/// Each emitted line carries a [StoryLineKind] so readers and retrieval can
/// tell story from system (tutorial) text.
library;

/// What a story line is. Stored in `story_lines.kind`.
enum StoryLineKind {
  /// A named character speaks (or a speaker-less dialogue box).
  dialogue('dialogue'),

  /// Narration: plain lines, `[narration]`, `[name=""]` and inner voices.
  narration('narration'),

  /// A caption shown over the scene (`[Subtitle]`): place, time, chapter card.
  subtitle('subtitle'),

  /// A document shown in the scene (`[Sticker]`): letters, notes, reports.
  document('document'),

  /// The options of a player choice (`[Decision]`), joined with ` ／ `.
  choice('choice'),

  /// A heading line (`[Title]`, `[HEADER]`).
  title('title'),

  /// Tutorial and guide popups; not part of any story.
  system('system');

  const StoryLineKind(this.value);

  /// The value stored in the database.
  final String value;

  /// Kinds the earlier importer produced (dialogue and plain narration).
  /// Vector chunking over these reuses the vectors computed before the
  /// parser learned the other kinds.
  static const Set<StoryLineKind> legacy = {dialogue, narration};

  static StoryLineKind fromValue(String? value) => StoryLineKind.values
      .firstWhere((k) => k.value == value, orElse: () => dialogue);
}

/// One text line of a story script.
class StoryScriptLine {
  const StoryScriptLine(this.speaker, this.content, this.kind);

  /// Speaker name; null for narration and speaker-less boxes.
  final String? speaker;
  final String content;
  final StoryLineKind kind;
}

/// Removes rich-text tags and collapses whitespace.
String cleanStoryText(String value) {
  return value
      .replaceAll(RegExp(r'<[^>]+>'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

final RegExp _commandHead = RegExp(r'^([A-Za-z_][A-Za-z0-9_.]*)\s*(=|\(|$|\s)');
final RegExp _attribute = RegExp(
  r'([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(?:"([^"]*)"|([^,\s)\]]+))',
);

/// Parses a whole script into its text lines, in order.
List<StoryScriptLine> parseStoryScript(String raw) {
  final lines = <StoryScriptLine>[];
  for (final original in raw.split('\n')) {
    final line = original.trim();
    if (line.isEmpty) continue;
    if (!line.startsWith('[')) {
      final content = cleanStoryText(line);
      if (content.isNotEmpty) {
        lines.add(StoryScriptLine(null, content, StoryLineKind.narration));
      }
      continue;
    }
    final parsed = _parseCommandLine(line);
    if (parsed != null) lines.add(parsed);
  }
  return lines;
}

StoryScriptLine? _parseCommandLine(String line) {
  final end = _commandEnd(line);
  if (end < 0) return null;
  final body = line.substring(1, end).trim();
  final trailing = cleanStoryText(line.substring(end + 1));
  final head = _commandHead.firstMatch(body);
  if (head == null) return null;
  final command = head.group(1)!.toLowerCase();
  final attributes = _attributes(body);

  switch (command) {
    // `[name="X", avatarId=…]text`, `[multiline(name="X")]text`.
    case 'name':
    case 'multiline':
    case 'isavatarright':
    case 'avatarid':
      if (trailing.isEmpty) return null;
      final speaker = attributes['name']?.trim();
      return speaker == null || speaker.isEmpty
          ? StoryScriptLine(null, trailing, StoryLineKind.narration)
          : StoryScriptLine(speaker, trailing, StoryLineKind.dialogue);
    case 'dialog':
      return trailing.isEmpty
          ? null
          : StoryScriptLine(null, trailing, StoryLineKind.dialogue);
    case 'narration':
    case 'voicewithin':
    case 'animtext':
      return trailing.isEmpty
          ? null
          : StoryScriptLine(null, trailing, StoryLineKind.narration);
    case 'title':
    case 'header':
      return trailing.isEmpty
          ? null
          : StoryScriptLine(null, trailing, StoryLineKind.title);
    case 'popupdialog':
    case 'tutorial':
      return trailing.isEmpty
          ? null
          : StoryScriptLine(null, trailing, StoryLineKind.system);
    case 'subtitle':
      final text = cleanStoryText(attributes['text'] ?? '');
      return text.isEmpty
          ? null
          : StoryScriptLine(null, text, StoryLineKind.subtitle);
    case 'sticker':
      final text = cleanStoryText(attributes['text'] ?? '');
      return text.isEmpty
          ? null
          : StoryScriptLine(null, text, StoryLineKind.document);
    case 'decision':
      final options = (attributes['options'] ?? '')
          .split(';')
          .map(cleanStoryText)
          .where((option) => option.isNotEmpty)
          .toList();
      return options.isEmpty
          ? null
          : StoryScriptLine(null, options.join(' ／ '), StoryLineKind.choice);
    default:
      return null;
  }
}

/// Index of the `]` that closes the command opened at index 0, skipping
/// brackets inside quoted attribute values; -1 when the line is unbalanced.
int _commandEnd(String line) {
  var inQuote = false;
  for (var i = 1; i < line.length; i++) {
    final c = line.codeUnitAt(i);
    if (c == 0x22) {
      inQuote = !inQuote;
    } else if (c == 0x5d && !inQuote) {
      return i;
    }
  }
  return -1;
}

/// Lower-cased attribute names → values of a command body.
Map<String, String> _attributes(String body) {
  final values = <String, String>{};
  for (final match in _attribute.allMatches(body)) {
    values.putIfAbsent(
      match.group(1)!.toLowerCase(),
      () => match.group(2) ?? match.group(3) ?? '',
    );
  }
  return values;
}
