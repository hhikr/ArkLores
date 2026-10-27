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

import 'portrait_names.dart';
import 'text_harvest.dart' show stripMarkup;

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
  const StoryScriptLine(this.speaker, this.content, this.kind, {this.portrait});

  /// Speaker name; null for narration and speaker-less boxes.
  final String? speaker;
  final String content;
  final StoryLineKind kind;
  final String? portrait;
}

/// Removes rich-text tags and collapses whitespace. The script writes a
/// line break inside quoted text as a literal `\n` (letters, poems and
/// notes in `[Sticker]`/`[Subtitle]` are several lines; the game shows them
/// so): it becomes a real line break, kept, with blank lines at the start
/// and end dropped and at most one blank line in a row (`\n\n展信佳。` →
/// `展信佳。`). Other blanks collapse to one space within a line.
String cleanStoryText(String value) {
  final lines = stripMarkup(value)
      .replaceAll(r'\r', '')
      .replaceAll(r'\n', '\n')
      .replaceAll(r'\t', ' ')
      .split(RegExp(r'\r?\n'))
      .map((line) => line.replaceAll(RegExp(r'\s+'), ' ').trim())
      .toList();
  final out = <String>[];
  for (final line in lines) {
    if (line.isEmpty && (out.isEmpty || out.last.isEmpty)) continue;
    out.add(line);
  }
  while (out.isNotEmpty && out.last.isEmpty) {
    out.removeLast();
  }
  return out.join('\n');
}

final RegExp _commandHead = RegExp(r'^([A-Za-z_][A-Za-z0-9_.]*)\s*(=|\(|$|\s)');
final RegExp _attribute = RegExp(
  r'([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(?:"([^"]*)"|([^,\s)\]]+))',
);

/// The script's logical lines. A physical line ending in a backslash goes on
/// in the next one: a command's attributes are spread over several lines
/// (`[Tutorial(focusX=0, …,\` `animStyle="Highlight", …)] \`) and the text
/// that the command carries is on the line after its closing bracket. Read
/// line by line, the attribute lines would become "narration" made of
/// animation settings.
List<String> storyLogicalLines(String raw) {
  final physical = raw.split('\n');
  final out = <String>[];
  var i = 0;
  while (i < physical.length) {
    var line = physical[i++].trim();
    if (line.isEmpty) continue;
    var joined = 0;
    while (line.endsWith('\\') && i < physical.length && joined++ < 40) {
      final next = physical[i].trim();
      if (next.isEmpty) break;
      i++;
      line = '${line.substring(0, line.length - 1).trimRight()} $next';
    }
    // A backslash left at the end continued nothing.
    if (line.endsWith('\\')) {
      line = line.substring(0, line.length - 1).trimRight();
    }
    if (line.isNotEmpty) out.add(line);
  }
  return out;
}

/// What a story art event does. Stored in `story_art_events.kind`.
enum StoryArtKind {
  /// The background changes (`Background`, `largebg`, `verticalbg`,
  /// `gridbg`); a null image takes it away.
  background('background'),

  /// A picture covers the stage (`Image`), or another replaces it.
  cg('cg'),

  /// The picture is taken away (`Image` without one).
  cgOff('cg_off'),

  /// A close-up is laid over the scene (`cgitem`).
  item('item'),

  /// A close-up is taken away (`hidecgitem`): the one named, or all of them
  /// when the image is null.
  itemOff('item_off');

  const StoryArtKind(this.value);

  /// The value stored in the database.
  final String value;
}

/// A change of what the scene shows, between two text lines: [atLine] is
/// the number of lines the script had produced before it. [image] is lower
/// case and trimmed; a composite background joins its pieces with `/` in
/// the script's order, [layout] saying how they sit (`row`, `column`,
/// `grid2`).
class StoryArtEvent {
  const StoryArtEvent(
    this.atLine,
    this.kind, {
    this.image,
    this.layout,
    this.x,
    this.y,
    this.scale,
    this.alpha,
    this.layer,
  });
  final int atLine;
  final StoryArtKind kind;
  final String? image;
  final String? layout;
  final double? x, y, scale, alpha;
  final int? layer;
}

/// Parses a whole script into its text lines, in order.
List<StoryScriptLine> parseStoryScript(String raw) =>
    parseStoryScriptWithArt(raw).lines;

/// The text lines and, from the same pass, the art events between them.
({List<StoryScriptLine> lines, List<StoryArtEvent> art})
    parseStoryScriptWithArt(String raw) {
  final lines = <StoryScriptLine>[];
  final portraits = _PortraitState();
  final art = <StoryArtEvent>[];
  final artState = _ArtState(art);
  for (final line in storyLogicalLines(raw)) {
    if (!line.startsWith('[')) {
      final content = cleanStoryText(line);
      if (content.isNotEmpty) {
        artState.flush(lines.length);
        lines.add(StoryScriptLine(null, content, StoryLineKind.narration));
      }
      continue;
    }
    final parsed = _parseCommandLine(line);
    portraits.update(line, artState, lines.length);
    if (parsed != null) {
      artState.flush(lines.length);
      lines.add(
        StoryScriptLine(
          parsed.speaker,
          parsed.content,
          parsed.kind,
          portrait:
              parsed.kind == StoryLineKind.dialogue && parsed.speaker != null
                  ? portraits.sprite
                  : null,
        ),
      );
    }
  }
  return (lines: lines, art: art);
}

class _PortraitState {
  /// One stage for both ways of writing it: `[Character]` puts one person in
  /// the middle, two on the left and right; `[charslot]` changes one place.
  final slots = <String, String>{};
  String? focus;

  /// An `[Image(image=…)]` picture covers the stage until an `[Image]`
  /// without one takes it away: nobody's portrait shows meanwhile, though
  /// the slots keep what the commands put there.
  bool covered = false;

  /// `[CharacterCutin(name=…)]` shows the speaker in a band over the stage
  /// (a call, a voice from elsewhere). It speaks until a CharacterCutin
  /// without a name, or until a stage command gives the turn back to the
  /// stage (the band may stay up while someone there answers).
  String? cutin;

  String? get sprite => covered
      ? null
      : cutin ??
          (focus == null
              ? (slots.length == 1 ? slots.values.single : null)
              : slots[focus]);

  String position(String value) => switch (value.toLowerCase()) {
        'left' => 'l',
        'right' => 'r',
        'middle' => 'm',
        final value => value,
      };

  void update(String line, _ArtState art, int atLine) {
    var rest = line;
    while (rest.startsWith('[')) {
      final end = _commandEnd(rest);
      if (end < 0) return;
      final body = rest.substring(1, end).trim();
      final command = _commandHead.firstMatch(body)?.group(1)?.toLowerCase();
      final attrs = _attributes(body);
      if (command == 'image') {
        final image = _artImage(attrs['image']);
        covered = image != null;
        art.cgImage(image, atLine);
      } else if (command == 'charactercutin') {
        cutin = canonicalSprite(attrs['name'] ?? '');
      } else if (command == 'character') {
        cutin = null;
        slots.clear();
        focus = null;
        final first = canonicalSprite(attrs['name'] ?? '');
        final second = canonicalSprite(attrs['name2'] ?? '');
        // Two names written (even one this app cannot draw): two places.
        bool written(String attr) => (attrs[attr]?.trim() ?? '').isNotEmpty;
        final places = written('name') && written('name2')
            ? {'1': 'l', '2': 'r'}
            : {'1': 'm', '2': 'm'};
        if (first != null) slots[places['1']!] = first;
        if (second != null) slots[places['2']!] = second;
        if (slots.isNotEmpty) {
          final f = attrs['focus'];
          focus = f == null
              ? (slots.length == 1 ? slots.keys.single : null)
              : (f == '1' || f == '2' ? places[f] : 'none');
        }
      } else if (command == 'charslot') {
        cutin = null;
        if (attrs.isEmpty) {
          slots.clear();
          focus = null;
        } else {
          final slot = position(attrs['slot'] ?? 'm');
          final name = canonicalSprite(attrs['name'] ?? '');
          final hasName = name != null || attrs['name'] == '';
          if (hasName) {
            if (name == null) {
              slots.remove(slot);
            } else {
              slots[slot] = name;
            }
          } else if (!attrs.containsKey('focus')) {
            slots.remove(slot);
          }
          final f = attrs['focus'];
          if (f != null) {
            focus = switch (position(f)) {
              'n' || 'none' => 'none',
              'a' || 'all' => 'all',
              'l' => 'l',
              'm' => 'm',
              'r' => 'r',
              _ => 'none',
            };
          } else if (name != null && slots.length == 1) {
            focus = slots.keys.single;
          }
        }
      }
      art.command(command, attrs, atLine);
      rest = rest.substring(end + 1).trim();
    }
  }
}

String? _artImage(String? value) {
  final result = value?.trim().toLowerCase() ?? '';
  return result.isEmpty ? null : result;
}

/// What the scene shows, so that a command that changes nothing (the camera
/// moving over the same background, the same picture again) is not an
/// event.
class _ArtState {
  _ArtState(this.events);
  final List<StoryArtEvent> events;
  String? background, layout, cg;

  /// Close-ups on screen: several can be up at once
  /// (`cgitem_x_1`, `cgitem_x_2`…) and go one by one.
  final items =
      <String, ({double x, double y, double scale, double alpha, int layer})>{};
  final visible =
      <String, ({double x, double y, double scale, double alpha, int layer})>{};

  void flush(int atLine) {
    final next = Map.of(items)..removeWhere((_, value) => value.alpha <= .01);
    for (final image in visible.keys) {
      if (!next.containsKey(image)) {
        events.add(StoryArtEvent(atLine, StoryArtKind.itemOff, image: image));
      }
    }
    for (final entry in next.entries) {
      if (visible[entry.key] == entry.value) continue;
      final v = entry.value;
      events.add(
        StoryArtEvent(
          atLine,
          StoryArtKind.item,
          image: entry.key,
          x: v.x,
          y: v.y,
          scale: v.scale,
          alpha: v.alpha,
          layer: v.layer,
        ),
      );
    }
    visible
      ..clear()
      ..addAll(next);
  }

  void cgImage(String? image, int atLine) {
    if (image == cg) return;
    cg = image;
    events.add(
      StoryArtEvent(
        atLine,
        image == null ? StoryArtKind.cgOff : StoryArtKind.cg,
        image: image,
      ),
    );
  }

  void command(String? command, Map<String, String> attrs, int atLine) {
    if (command == 'background' ||
        command == 'largebg' ||
        command == 'verticalbg' ||
        command == 'gridbg') {
      final composite = command != 'background';
      // A few composites of pictures name them `cggroup`.
      final value =
          composite ? attrs['imagegroup'] ?? attrs['cggroup'] : attrs['image'];
      final image = composite
          ? _artImage(value)?.split('/').map((part) => part.trim()).join('/')
          : _artImage(value);
      final nextLayout = image == null
          ? null
          : switch (command) {
              'largebg' => 'row',
              'verticalbg' => 'column',
              'gridbg' => 'grid2',
              _ => null,
            };
      // A file starts with no background: clearing it then is no event.
      if (image != background || nextLayout != layout) {
        events.add(
          StoryArtEvent(
            atLine,
            StoryArtKind.background,
            image: image,
            layout: nextLayout,
          ),
        );
        background = image;
        layout = nextLayout;
      }
    } else if (command == 'cgitem') {
      final image = _artImage(attrs['image']);
      if (image != null) {
        final old =
            items[image] ?? (x: 0.0, y: 0.0, scale: 1.0, alpha: 1.0, layer: 0);
        final position = (attrs['pto'] ?? attrs['pfrom'])?.split(',');
        double number(String to, String from, double fallback) =>
            double.tryParse(attrs[to] ?? attrs[from] ?? '') ?? fallback;
        items[image] = (
          x: position == null
              ? old.x
              : double.tryParse(position.first.trim()) ?? old.x,
          y: position == null || position.length < 2
              ? old.y
              : double.tryParse(position[1].trim()) ?? old.y,
          scale: number('sto', 'sfrom', old.scale),
          alpha: number('ato', 'afrom', old.alpha),
          layer: int.tryParse(attrs['layer'] ?? '') ?? old.layer,
        );
      }
    } else if (command == 'hidecgitem') {
      final image = _artImage(attrs['image']);
      if (image == null) {
        items.clear();
      } else {
        items.remove(image);
      }
    }
  }
}

StoryScriptLine? _parseCommandLine(String line) {
  final end = _commandEnd(line);
  if (end < 0) return null;
  final body = line.substring(1, end).trim();
  // Commands in a row ([A(…)] [B(…)]text): the text belongs to the last.
  final rest = line.substring(end + 1).trim();
  if (rest.startsWith('[')) return _parseCommandLine(rest);
  final trailing = cleanStoryText(rest);
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
