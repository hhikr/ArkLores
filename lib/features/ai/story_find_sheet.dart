import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/gamedata/story_coverage_models.dart'
    show StoryLineEntry, unsearchedLineKinds;
import '../../core/library/library_queries.dart' show snippetAround;
import '../../core/library/placeholders.dart';
import '../../shared/l10n/l10n.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/ef_widgets.dart';

/// Positions in [lines] whose text or speaker has every word of [query]
/// (ignoring case), in reading order.
List<int> findStoryLines(List<StoryLineEntry> lines, String query) {
  final words = [
    for (final w in query.trim().toLowerCase().split(RegExp(r'\s+')))
      if (w.isNotEmpty) w,
  ];
  if (words.isEmpty) return const [];
  return [
    for (final (i, line) in lines.indexed)
      if (line.kind != 'divider' &&
          line.kind != 'section' &&
          !unsearchedLineKinds.contains(line.kind) &&
          words.every(
            (w) =>
                line.content.toLowerCase().contains(w) ||
                (line.speaker ?? '').toLowerCase().contains(w),
          ))
        i,
  ];
}

/// Find in the story being read: a sheet with a search box and the matching
/// lines (their line numbers in front). Returns the lineIndex of the line
/// picked, or null.
Future<int?> showStoryFind(
  BuildContext context, {
  required List<StoryLineEntry> lines,
  required AppThemeTokens theme,
  String nickname = '',
}) =>
    showAppSheet<int>(
      context,
      (_) => PlainSheet(
        child: _StoryFind(lines: lines, theme: theme, nickname: nickname),
      ),
    );

class _StoryFind extends StatefulWidget {
  const _StoryFind({
    required this.lines,
    required this.theme,
    required this.nickname,
  });

  final List<StoryLineEntry> lines;
  final AppThemeTokens theme;
  final String nickname;

  @override
  State<_StoryFind> createState() => _StoryFindState();
}

class _StoryFindState extends State<_StoryFind> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final found = findStoryLines(widget.lines, _query);
    final words = _query.trim().split(RegExp(r'\s+'));
    // As tall as what it holds: the box and a line saying what will come,
    // then the lines found, up to about half of what the keyboard leaves.
    final media = MediaQuery.of(context);
    final room =
        media.size.height - media.viewInsets.bottom - media.padding.top;
    final blank = _query.trim().isEmpty;
    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: math.max(160, room * 0.6)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                key: const ValueKey('story-find-field'),
                autofocus: true,
                onChanged: (v) => setState(() => _query = v),
                textInputAction: TextInputAction.search,
                style: theme.text(15),
                decoration: InputDecoration(
                  hintText: context.t.storyReaderFindHint,
                  prefixIcon:
                      Icon(Icons.search_sharp, color: theme.textSecondary),
                  suffixText: _query.trim().isEmpty
                      ? null
                      : context.t.librarySearchMatchCount(found.length),
                  suffixStyle: theme.field(),
                ),
              ),
            ),
            if (blank || found.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                child: SizedBox(
                  width: double.infinity,
                  child: Text(
                    blank
                        ? context.t.storyReaderFindEmpty
                        : context.t.libraryNoResults,
                    style: theme.text(14, color: theme.textSecondary),
                  ),
                ),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  itemCount: found.length,
                  separatorBuilder: (_, __) =>
                      Divider(height: 1, color: theme.divider),
                  itemBuilder: (context, i) {
                    final at = found[i];
                    final line = widget.lines[at];
                    final speaker = (line.speaker ?? '').trim();
                    final text = withPlaceholders(
                      snippetAround(line.content, words, width: 80),
                      widget.nickname,
                    );
                    return PressRow(
                      key: ValueKey('story-find-$at'),
                      onTap: () => Navigator.of(context).pop(line.lineIndex),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 48),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(8, 10, 4, 10),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                width: 44,
                                child: Text(
                                  '${(line.shownIndex ?? line.lineIndex) + 1}',
                                  style: theme.field(
                                    color: theme.textMuted,
                                    size: 13,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  speaker.isEmpty ? text : '$speaker：$text',
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.text(14.5, height: 1.5),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
