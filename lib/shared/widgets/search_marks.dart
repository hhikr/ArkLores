import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/theme_provider.dart';
import '../theme/app_theme.dart';

/// The words of a search box: what it holds split at spaces, without empty
/// ones.
List<String> searchWords(String query) => [
      for (final w in query.trim().split(RegExp(r'\s+')))
        if (w.isNotEmpty) w,
    ];

/// The look of a searched word inside a result: the accent fill under it
/// (what to look at), the text on it in [AppThemeTokens.onAccent].
TextStyle searchMarkStyle(AppThemeTokens theme) => TextStyle(
      backgroundColor: theme.accentPrimary,
      color: theme.onAccent,
    );

/// [text] cut into spans, the parts that are one of [words] (ignoring case)
/// in [mark]; overlapping words are marked as one run.
List<InlineSpan> searchSpans(String text, List<String> words, TextStyle mark) {
  if (words.isEmpty || text.isEmpty) return [TextSpan(text: text)];
  final lower = text.toLowerCase();
  final marked = List<bool>.filled(text.length, false);
  var any = false;
  for (final w in words) {
    final needle = w.toLowerCase();
    if (needle.isEmpty) continue;
    for (var at = lower.indexOf(needle);
        at >= 0;
        at = lower.indexOf(needle, at + 1)) {
      for (var i = at; i < at + needle.length && i < text.length; i++) {
        marked[i] = true;
      }
      any = true;
    }
  }
  if (!any) return [TextSpan(text: text)];
  final spans = <InlineSpan>[];
  var start = 0;
  for (var i = 1; i <= text.length; i++) {
    if (i == text.length || marked[i] != marked[start]) {
      final part = text.substring(start, i);
      spans.add(TextSpan(text: part, style: marked[start] ? mark : null));
      start = i;
    }
  }
  return spans;
}

/// The words being searched for, for the results under it: a [MarkedText]
/// below marks them.
class SearchMarks extends InheritedWidget {
  const SearchMarks({super.key, required this.words, required super.child});

  final List<String> words;

  static List<String> of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SearchMarks>()?.words ??
      const [];

  @override
  bool updateShouldNotify(SearchMarks old) =>
      old.words.length != words.length ||
      [for (var i = 0; i < words.length; i++) old.words[i] != words[i]]
          .contains(true);
}

/// A text that marks the words of the [SearchMarks] above it; a plain text
/// where there is none.
class MarkedText extends ConsumerWidget {
  const MarkedText(
    this.text, {
    super.key,
    this.style,
    this.maxLines,
    this.overflow,
  });

  final String text;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final words = SearchMarks.of(context);
    if (words.isEmpty) {
      return Text(text, style: style, maxLines: maxLines, overflow: overflow);
    }
    final theme = ref.watch(themeProvider);
    return Text.rich(
      TextSpan(children: searchSpans(text, words, searchMarkStyle(theme))),
      style: style,
      maxLines: maxLines,
      overflow: overflow,
    );
  }
}
