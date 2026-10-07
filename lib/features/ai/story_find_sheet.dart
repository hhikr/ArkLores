import 'package:flutter/material.dart';

import '../../core/gamedata/story_coverage_models.dart' show StoryLineEntry;
import '../../core/library/library_queries.dart' show snippetAround;
import '../../core/library/placeholders.dart';
import '../../shared/l10n/l10n.dart';
import '../../shared/theme/app_theme.dart';

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
          words.every((w) =>
              line.content.toLowerCase().contains(w) ||
              (line.speaker ?? '').toLowerCase().contains(w),))
        i,
  ];
}

/// Find in the story being read: a sheet with a search box and the matching
/// lines. Returns the lineIndex of the line picked, or null.
Future<int?> showStoryFind(
  BuildContext context, {
  required List<StoryLineEntry> lines,
  required AppThemeTokens theme,
  String nickname = '',
}) =>
    showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      backgroundColor: theme.bgSecondary,
      builder: (_) => _StoryFind(lines: lines, theme: theme, nickname: nickname),
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
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.6,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
              child: TextField(
                key: const ValueKey('story-find-field'),
                autofocus: true,
                onChanged: (v) => setState(() => _query = v),
                textInputAction: TextInputAction.search,
                style: theme.bodyFont.copyWith(fontSize: 14),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: context.t.storyReaderFindHint,
                  prefixIcon: Icon(Icons.search_rounded, color: theme.textMuted),
                  suffixText: _query.trim().isEmpty
                      ? null
                      : context.t.librarySearchMatchCount(found.length),
                ),
              ),
            ),
            Expanded(
              child: _query.trim().isNotEmpty && found.isEmpty
                  ? Center(
                      child: Text(
                        context.t.libraryNoResults,
                        style: theme.bodyFont
                            .copyWith(color: theme.textSecondary),
                      ),
                    )
                  : ListView.builder(
                      itemCount: found.length,
                      itemBuilder: (context, i) {
                        final at = found[i];
                        final line = widget.lines[at];
                        final speaker = (line.speaker ?? '').trim();
                        final text = withPlaceholders(
                          snippetAround(line.content, words, width: 80),
                          widget.nickname,
                        );
                        return ListTile(
                          key: ValueKey('story-find-$at'),
                          dense: true,
                          leading: Text(
                            '${(line.shownIndex ?? line.lineIndex) + 1}',
                            style: theme.bodyFont.copyWith(
                              color: theme.textMuted,
                              fontSize: 12,
                            ),
                          ),
                          title: Text(
                            speaker.isEmpty ? text : '$speaker：$text',
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: theme.bodyFont.copyWith(fontSize: 13.5),
                          ),
                          onTap: () => Navigator.of(context).pop(line.lineIndex),
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
