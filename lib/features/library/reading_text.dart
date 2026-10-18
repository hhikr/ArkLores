/// Long text as it is read in the library: in the reading font of the story
/// reader, one paragraph per line of the source with room between them,
/// `【标签】` fields set off from their values, and the parts of a profile
/// (its `##` headings) as sections that fold.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/gamedata/build/text_harvest.dart' show cleanRichText;
import '../../core/library/placeholders.dart';
import '../../shared/providers/settings_provider.dart';
import '../../shared/providers/theme_provider.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/floating_bar.dart' show selectionDuration;
import '../../shared/widgets/press_feedback.dart';
import '../ai/story_reader_page.dart' show readingFontFamily;

/// The style of long text: the reader's font, a generous line height.
TextStyle readingStyle(
  AppThemeTokens theme, {
  double size = 15.5,
  Color? color,
}) =>
    theme.bodyFont.copyWith(
      fontFamily: readingFontFamily,
      color: color ?? theme.textPrimary,
      fontSize: size,
      height: 1.85,
      letterSpacing: 0.2,
    );

/// A `【标签】值` line, or a `标签：值` line of a field list.
final RegExp _bracketField = RegExp(r'^【([^】]{1,16})】\s*(.*)$');
final RegExp _colonField = RegExp(r'^([^：:\s]{1,10})[：:]\s*(.+)$');

/// Whether [text] opens with a list of facts: every line of its first block
/// (up to a blank line) a short `标签：值` field, such as an Endfield
/// operator's faction, race, expertise and hobbies (what follows them, their
/// descriptions, reads as text).
bool isFieldList(String text) {
  final lines = [
    for (final l in text.trim().split(RegExp(r'\n\s*\n')).first.split('\n'))
      if (l.trim().isNotEmpty) l.trim(),
  ];
  return lines.isNotEmpty &&
      lines.length <= 16 &&
      lines.every(_colonField.hasMatch);
}

/// One paragraph of [ReadingText]: plain [text] (no [label]), a field
/// ([label] and its value as [text]), or a label alone that heads what
/// follows (empty [text]); [gap] is the room above it.
typedef ReadingParagraph = ({String? label, String text, double gap});

/// The paragraphs of [clean] (already cleaned text): every line its own
/// paragraph, a blank line a wider gap, `【标签】` lines as fields, and with
/// [fields] the `标签：值` lines of the first block as fields too.
List<ReadingParagraph> readingParagraphs(String clean, {bool fields = false}) {
  final out = <ReadingParagraph>[];
  var gap = 0.0;
  var firstBlock = true;
  for (final raw in clean.split('\n')) {
    final line = raw.trim();
    if (line.isEmpty) {
      if (out.isNotEmpty) {
        gap = 18;
        firstBlock = false;
      }
      continue;
    }
    final bracket = _bracketField.firstMatch(line);
    final colon = fields && firstBlock ? _colonField.firstMatch(line) : null;
    final field = bracket ?? colon;
    if (field != null && field.group(2)!.trim().isEmpty) {
      out.add((label: field.group(1)!, text: '', gap: out.isEmpty ? 0 : 14));
      gap = 4;
    } else if (field != null) {
      out.add(
        (
          label: field.group(1)!,
          text: field.group(2)!.trim(),
          gap: out.isEmpty ? 0 : gap,
        ),
      );
      gap = 6;
    } else {
      out.add((label: null, text: line, gap: out.isEmpty ? 0 : gap));
      gap = 8;
    }
  }
  return out;
}

/// One [ReadingParagraph] with the room above it.
class ReadingParagraphView extends StatelessWidget {
  const ReadingParagraphView(
    this.paragraph, {
    super.key,
    required this.theme,
    this.size = 15.5,
  });

  final ReadingParagraph paragraph;
  final AppThemeTokens theme;
  final double size;

  @override
  Widget build(BuildContext context) {
    final p = paragraph;
    final Widget child;
    if (p.label == null) {
      child = Text(p.text, style: readingStyle(theme, size: size));
    } else if (p.text.isEmpty) {
      child = Text(
        p.label!,
        style: theme.bodyFont.copyWith(
          color: theme.accentText,
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
        ),
      );
    } else {
      child = Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 76),
            child: Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Text(
                p.label!,
                style: theme.bodyFont.copyWith(
                  color: theme.textSecondary,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.4,
                ),
              ),
            ),
          ),
          Expanded(child: Text(p.text, style: readingStyle(theme, size: size))),
        ],
      );
    }
    return p.gap == 0
        ? child
        : Padding(padding: EdgeInsets.only(top: p.gap), child: child);
  }
}

/// [text] as paragraphs ([readingParagraphs]), selectable as one text.
class ReadingText extends ConsumerWidget {
  const ReadingText(
    this.text, {
    super.key,
    this.fields = false,
    this.size = 15.5,
  });

  final String text;
  final bool fields;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    final clean =
        cleanRichText(withPlaceholders(text, ref.watch(nicknameProvider)));
    return SelectionArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final p in readingParagraphs(clean, fields: fields))
            ReadingParagraphView(p, theme: theme, size: size),
        ],
      ),
    );
  }
}

/// The head of a part that folds: an accent mark, the title, a short note
/// (a count) and a chevron; tapping it calls [onTap].
class FoldHead extends ConsumerWidget {
  const FoldHead({
    super.key,
    required this.title,
    required this.open,
    required this.onTap,
    this.trailing,
    this.plain = false,
  });

  final String title;
  final bool open;
  final VoidCallback onTap;
  final String? trailing;
  final bool plain;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    return PressFeedback(
      child: InkWell(
        key: ValueKey('fold-$title'),
        onTap: withHaptic(onTap),
        child: Padding(
          padding:
              EdgeInsets.symmetric(horizontal: plain ? 0 : 14, vertical: 12),
          child: Row(
            children: [
              AnimatedContainer(
                duration: selectionDuration,
                curve: Curves.easeOutExpo,
                width: 3,
                height: 16,
                color: open ? theme.accentPrimary : theme.textMuted,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: theme.titleFont.copyWith(fontSize: 15, height: 1.3),
                ),
              ),
              if (trailing != null)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Text(
                    trailing!,
                    style: theme.bodyFont.copyWith(
                      color: theme.textMuted,
                      fontSize: 12,
                    ),
                  ),
                ),
              AnimatedRotation(
                turns: open ? 0 : -0.25,
                duration: selectionDuration,
                curve: Curves.easeOutCubic,
                child: Icon(
                  Icons.expand_more_sharp,
                  color: open ? theme.accentText : theme.textMuted,
                  size: 22,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A part of a page under a heading that folds: a square plate with an
/// accent mark, the title and what it holds; tapping the head folds or
/// unfolds the body in a short, straight motion.
class FoldSection extends ConsumerStatefulWidget {
  const FoldSection({
    super.key,
    required this.title,
    required this.child,
    this.initiallyOpen = true,
    this.trailing,
    this.plain = false,
    this.onToggle,
  });

  final String title;
  final Widget child;
  final bool initiallyOpen;

  /// Called with the new state just before the part opens or folds.
  final ValueChanged<bool>? onToggle;

  /// A short note after the title (a count).
  final String? trailing;

  /// Without the card around it (inside another card).
  final bool plain;

  @override
  ConsumerState<FoldSection> createState() => _FoldSectionState();
}

class _FoldSectionState extends ConsumerState<FoldSection> {
  late bool _open = widget.initiallyOpen;

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider);
    final head = FoldHead(
      title: widget.title,
      open: _open,
      trailing: widget.trailing,
      plain: widget.plain,
      onTap: () {
        widget.onToggle?.call(!_open);
        setState(() => _open = !_open);
      },
    );
    final body = AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: _open
          ? Padding(
              padding: EdgeInsets.fromLTRB(
                widget.plain ? 0 : 14,
                0,
                widget.plain ? 0 : 14,
                14,
              ),
              child: widget.child,
            )
          : const SizedBox(width: double.infinity),
    );
    final column = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [head, body],
    );
    if (widget.plain) return column;
    return Container(
      decoration: BoxDecoration(
        color: theme.cardSurface,
        border: Border.all(color: theme.cardBorder),
      ),
      child: column,
    );
  }
}

/// The parts of a profile document (`## ` headings): (heading or null,
/// body), in order.
List<({String? title, String body})> profileSections(String text) {
  final out = <({String? title, List<String> lines})>[];
  for (final line in text.split('\n')) {
    if (line.startsWith('## ')) {
      out.add((title: line.substring(3).trim(), lines: <String>[]));
    } else {
      if (out.isEmpty) out.add((title: null, lines: <String>[]));
      out.last.lines.add(line);
    }
  }
  return [
    for (final s in out)
      if (s.lines.join('\n').trim().isNotEmpty)
        (title: s.title, body: s.lines.join('\n').trim()),
  ];
}

/// A profile document (`## ` headings) in a small place (a quoted record):
/// each part a [FoldSection], open or folded as Settings say
/// ([profileSectionsOpenProvider]); the voice lines as [VoiceLines]; a list
/// of facts as fields. A page shows a whole file with [ProfileSliver].
class ProfileText extends ConsumerWidget {
  const ProfileText(this.text, {super.key});

  final String text;

  /// The parts of [text]: (heading or null, body), in order.
  static List<({String? title, String body})> sections(String text) =>
      profileSections(text);

  /// Whether a part holds voice lines (`标题：台词` per line) by its heading.
  static bool isVoice(String? title) => title != null && title.contains('语音');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final open = ref.watch(profileSectionsOpenProvider);
    final parts = sections(text);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, s) in parts.indexed) ...[
          if (i > 0) const SizedBox(height: 10),
          if (s.title == null)
            ReadingText(s.body, fields: isFieldList(s.body))
          else
            FoldSection(
              key: ValueKey('profile-section-${s.title}-$i'),
              title: s.title!,
              initiallyOpen: open,
              trailing: isVoice(s.title)
                  ? '${VoiceLines.parse(s.body).length}'
                  : null,
              child: isVoice(s.title)
                  ? VoiceLines(s.body)
                  : ReadingText(s.body, fields: isFieldList(s.body)),
            ),
        ],
      ],
    );
  }
}

/// A profile document (`## ` headings) as rows of a lazy list: only the
/// rows on screen are built and laid out, so a long file (an operator's
/// archives and its voice sets, thousands of lines) opens as fast as a
/// short one. Each paragraph and each voice line is a row; a part's head
/// folds it ([profileSectionsOpenProvider] says how they start); the rows of
/// a part draw its card between them. Put it in a [CustomScrollView] (in a
/// [SelectionArea] for the text to be selectable).
class ProfileSliver extends ConsumerStatefulWidget {
  const ProfileSliver(this.text, {super.key, this.padding = EdgeInsets.zero});

  /// The document, cleaned ([cleanRichText], placeholders filled).
  final String text;

  /// Room left and right of the rows.
  final EdgeInsets padding;

  @override
  ConsumerState<ProfileSliver> createState() => _ProfileSliverState();
}

/// A part of a [ProfileSliver]: its heading (null: no card, no fold) and its
/// rows, paragraphs or voice lines.
typedef _ProfilePart = ({
  String? title,
  List<ReadingParagraph> paragraphs,
  List<({String title, String line})> voices,
});

class _ProfileSliverState extends ConsumerState<ProfileSliver> {
  /// The parts whose state is not the setting's (tapped).
  final Set<int> _toggled = {};
  late List<_ProfilePart> _parts = _parse(widget.text);

  static List<_ProfilePart> _parse(String text) => [
        for (final s in profileSections(text))
          (
            title: s.title,
            paragraphs: ProfileText.isVoice(s.title)
                ? const []
                : readingParagraphs(s.body, fields: isFieldList(s.body)),
            voices: ProfileText.isVoice(s.title)
                ? VoiceLines.parse(s.body)
                : const [],
          ),
      ];

  @override
  void didUpdateWidget(ProfileSliver old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text) {
      _parts = _parse(widget.text);
      _toggled.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider);
    final openByDefault = ref.watch(profileSectionsOpenProvider);
    // The rows in order: (part, row in the part or -1 for the head).
    final rows = <(int, int)>[];
    for (final (i, p) in _parts.indexed) {
      final open = p.title == null || openByDefault != _toggled.contains(i);
      if (p.title != null) rows.add((i, -1));
      if (open) {
        final n = p.voices.isNotEmpty ? p.voices.length : p.paragraphs.length;
        for (var r = 0; r < n; r++) {
          rows.add((i, r));
        }
      }
    }
    return SliverPadding(
      padding: widget.padding,
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, k) {
            final (i, r) = rows[k];
            final last = k == rows.length - 1 || rows[k + 1].$1 != i;
            return _row(theme, openByDefault, i, r, last);
          },
          childCount: rows.length,
          // Each row is a paragraph: cheap to rebuild, nothing to keep.
          addAutomaticKeepAlives: false,
        ),
      ),
    );
  }

  /// Row [r] of part [i] (-1: its head); [last] closes the part's card.
  Widget _row(
    AppThemeTokens theme,
    bool openByDefault,
    int i,
    int r,
    bool last,
  ) {
    final p = _parts[i];
    final first = i == 0 && r <= 0;
    final open = openByDefault != _toggled.contains(i);
    if (p.title == null) {
      final para = p.paragraphs[r];
      return ReadingParagraphView(para, theme: theme);
    }
    final side = BorderSide(color: theme.cardBorder);
    final Widget child;
    if (r < 0) {
      child = FoldHead(
        key: ValueKey('profile-section-${p.title}-$i'),
        title: p.title!,
        open: open,
        trailing: p.voices.isNotEmpty ? '${p.voices.length}' : null,
        onTap: () => setState(() {
          if (!_toggled.remove(i)) _toggled.add(i);
        }),
      );
    } else if (p.voices.isNotEmpty) {
      child = Padding(
        padding: EdgeInsets.fromLTRB(14, 0, 14, last ? 6 : 0),
        child: VoiceLine(p.voices[r], first: r == 0),
      );
    } else {
      child = Padding(
        padding: EdgeInsets.fromLTRB(14, 0, 14, last ? 14 : 0),
        child: ReadingParagraphView(p.paragraphs[r], theme: theme),
      );
    }
    return Padding(
      padding: EdgeInsets.only(top: r < 0 && !first ? 10 : 0),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.cardSurface,
          border: Border(
            left: side,
            right: side,
            top: r < 0 ? side : BorderSide.none,
            bottom: last ? side : BorderSide.none,
          ),
        ),
        child: child,
      ),
    );
  }
}

/// Voice lines (`标题：台词` per line) in the order given (the game's), as a
/// list like the wikis' voice tables: each line's title over it, a hairline
/// between lines.
class VoiceLines extends ConsumerWidget {
  const VoiceLines(this.text, {super.key});

  final String text;

  static List<({String title, String line})> parse(String text) => [
        for (final raw in text.split('\n'))
          if (raw.trim().isNotEmpty)
            if (raw.indexOf('：') case final cut when cut > 0 && cut <= 16)
              (
                title: raw.substring(0, cut).trim(),
                line: raw.substring(cut + 1).trim()
              )
            else
              (title: '', line: raw.trim()),
      ];

  @override
  Widget build(BuildContext context, WidgetRef ref) => SelectionArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (i, v) in parse(text).indexed)
              VoiceLine(v, key: ValueKey('voice-$i'), first: i == 0),
          ],
        ),
      );
}

/// One voice line: its title (`交谈1`) in small accent letters over the
/// line; a hairline above it unless it is the [first].
class VoiceLine extends ConsumerWidget {
  const VoiceLine(this.voice, {super.key, this.first = false});

  final ({String title, String line}) voice;
  final bool first;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    final nickname = ref.watch(nicknameProvider);
    return Container(
      padding: EdgeInsets.only(top: first ? 2 : 11, bottom: 11),
      decoration: first
          ? null
          : BoxDecoration(
              border: Border(
                top: BorderSide(color: theme.cardBorder.withValues(alpha: 0.7)),
              ),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (voice.title.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text(
                voice.title,
                style: theme.bodyFont.copyWith(
                  color: theme.accentText,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                ),
              ),
            ),
          Text(
            cleanRichText(withPlaceholders(voice.line, nickname)),
            style: readingStyle(theme, size: 15),
          ),
        ],
      ),
    );
  }
}

/// The heading of a group in a list (a region, a kind): a small muted line.
class GroupHeading extends ConsumerWidget {
  const GroupHeading({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
      child: Row(
        children: [
          Container(width: 3, height: 12, color: theme.accentPrimary),
          const SizedBox(width: 8),
          Text(
            title,
            style: theme.bodyFont.copyWith(
              color: theme.textSecondary,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }
}
