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

/// [text] as paragraphs: every line its own paragraph, a blank line a wider
/// gap, `【标签】` lines as fields (a label alone heads what follows), and with
/// [fields] every `标签：值` line as a field too. Selectable as one text.
class ReadingText extends ConsumerWidget {
  const ReadingText(this.text, {super.key, this.fields = false, this.size = 15.5});

  final String text;
  final bool fields;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    final clean = cleanRichText(withPlaceholders(text, ref.watch(nicknameProvider)));
    final children = <Widget>[];
    var gap = 0.0;
    void add(Widget w) {
      if (children.isNotEmpty) children.add(SizedBox(height: gap));
      children.add(w);
      gap = 8;
    }

    // With [fields], the `标签：值` lines of the first block are fields.
    var firstBlock = true;
    for (final raw in clean.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty) {
        if (children.isNotEmpty) {
          gap = 18;
          firstBlock = false;
        }
        continue;
      }
      final bracket = _bracketField.firstMatch(line);
      final colon = fields && firstBlock ? _colonField.firstMatch(line) : null;
      final field = bracket ?? colon;
      if (field != null && field.group(2)!.trim().isEmpty) {
        // A label alone: it heads the lines after it.
        if (children.isNotEmpty) gap = 14;
        add(_label(theme, field.group(1)!));
        gap = 4;
      } else if (field != null) {
        add(_field(theme, field.group(1)!, field.group(2)!.trim()));
        gap = 6;
      } else {
        add(Text(line, style: readingStyle(theme, size: size)));
      }
    }
    return SelectionArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }

  Widget _label(AppThemeTokens theme, String label) => Text(
        label,
        style: theme.bodyFont.copyWith(
          color: theme.accentText,
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
        ),
      );

  Widget _field(AppThemeTokens theme, String label, String value) => Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 76),
            child: Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Text(
                label,
                style: theme.bodyFont.copyWith(
                  color: theme.textSecondary,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.4,
                ),
              ),
            ),
          ),
          Expanded(child: Text(value, style: readingStyle(theme, size: size))),
        ],
      );
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
  });

  final String title;
  final Widget child;
  final bool initiallyOpen;

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
    final head = PressFeedback(
      child: InkWell(
        key: ValueKey('fold-${widget.title}'),
        onTap: withHaptic(() => setState(() => _open = !_open)),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: widget.plain ? 0 : 14,
            vertical: 12,
          ),
          child: Row(
            children: [
              AnimatedContainer(
                duration: selectionDuration,
                curve: Curves.easeOutExpo,
                width: 3,
                height: 16,
                color: _open ? theme.accentPrimary : theme.textMuted,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.title,
                  style: theme.titleFont.copyWith(fontSize: 15, height: 1.3),
                ),
              ),
              if (widget.trailing != null)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Text(
                    widget.trailing!,
                    style: theme.bodyFont.copyWith(
                      color: theme.textMuted,
                      fontSize: 12,
                    ),
                  ),
                ),
              AnimatedRotation(
                turns: _open ? 0 : -0.25,
                duration: selectionDuration,
                curve: Curves.easeOutCubic,
                child: Icon(
                  Icons.expand_more_sharp,
                  color: _open ? theme.accentText : theme.textMuted,
                  size: 22,
                ),
              ),
            ],
          ),
        ),
      ),
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

/// A profile document (`## ` headings): each part a [FoldSection], open;
/// the voice lines as [VoiceLines]; a list of facts as fields.
class ProfileText extends StatelessWidget {
  const ProfileText(this.text, {super.key});

  final String text;

  /// The parts of [text]: (heading or null, body), in order.
  static List<({String? title, String body})> sections(String text) {
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

  /// Whether a part holds voice lines (`标题：台词` per line) by its heading.
  static bool isVoice(String? title) => title != null && title.contains('语音');

  @override
  Widget build(BuildContext context) {
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

/// Voice lines (`标题：台词` per line) as a list of quotes: the title over its
/// line, numbered titles of one kind (`信赖对话1` … `5`) under one heading.
class VoiceLines extends ConsumerWidget {
  const VoiceLines(this.text, {super.key});

  final String text;

  static List<({String title, String line})> parse(String text) => [
        for (final raw in text.split('\n'))
          if (raw.trim().isNotEmpty)
            if (raw.indexOf('：') case final cut when cut > 0 && cut <= 16)
              (title: raw.substring(0, cut).trim(), line: raw.substring(cut + 1).trim())
            else
              (title: '', line: raw.trim()),
      ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    final nickname = ref.watch(nicknameProvider);
    final lines = parse(text);
    final children = <Widget>[];
    String? kind;
    for (final (i, v) in lines.indexed) {
      final number = RegExp(r'^(.*?)(\d+)$').firstMatch(v.title);
      final base = number?.group(1) ?? v.title;
      final numbered = number != null &&
          base.isNotEmpty &&
          [lines.elementAtOrNull(i - 1), lines.elementAtOrNull(i + 1)].any(
            (o) => o != null && o.title != v.title && o.title.startsWith(base) &&
                RegExp(r'^\d+$').hasMatch(o.title.substring(base.length)),
          );
      if (numbered && base != kind) {
        children.add(
          Padding(
            padding: EdgeInsets.only(top: children.isEmpty ? 0 : 14, bottom: 2),
            child: Text(
              base,
              style: theme.titleFont.copyWith(
                color: theme.accentText,
                fontSize: 13.5,
                letterSpacing: 0.4,
              ),
            ),
          ),
        );
      }
      kind = numbered ? base : null;
      children.add(
        Container(
          key: ValueKey('voice-$i'),
          margin: EdgeInsets.only(
            top: children.isEmpty ? 0 : 8,
            left: numbered ? 8 : 0,
          ),
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
          decoration: BoxDecoration(
            color: theme.bgPrimary.withValues(alpha: 0.55),
            border: Border(
              left: BorderSide(
                color: numbered
                    ? theme.accentPrimary.withValues(alpha: 0.6)
                    : theme.cardBorder,
                width: 2,
              ),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (v.title.isNotEmpty)
                Text(
                  numbered ? number.group(2)! : v.title,
                  style: theme.bodyFont.copyWith(
                    color: theme.textSecondary,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                  ),
                ),
              const SizedBox(height: 2),
              Text(
                cleanRichText(withPlaceholders(v.line, nickname)),
                style: readingStyle(theme, size: 15),
              ),
            ],
          ),
        ),
      );
    }
    return SelectionArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
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
