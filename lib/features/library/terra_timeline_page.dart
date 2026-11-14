import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/gamedata/terra_timeline.dart';
import '../../core/library/library_provider.dart';
import '../../shared/l10n/l10n.dart';
import '../../shared/providers/theme_provider.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/ef_widgets.dart';
import '../../shared/widgets/search_marks.dart';
import 'library_widgets.dart';
import 'reading_text.dart' show readingStyle;

/// The group an event is listed under: its year heading, else its
/// century, else its era.
String timelineGroupOf(TimelineEvent e) => e.heading ?? e.period ?? e.era;

/// 2026-11-14: PRTS Wiki's Terra timeline (the first row of the Arknights
/// library): its events by period, a filter, the periods as blocks on top
/// that pick one in place. A source the knowledge base has opens in the
/// reader. [focusEventId] (a cited event) opens on its period with the
/// event marked and in sight.
class TerraTimelinePage extends ConsumerStatefulWidget {
  const TerraTimelinePage({super.key, this.focusEventId});

  final String? focusEventId;

  @override
  ConsumerState<TerraTimelinePage> createState() => _TerraTimelinePageState();
}

class _TerraTimelinePageState extends ConsumerState<TerraTimelinePage> {
  String? _group;
  String _query = '';
  Timer? _debounce;
  bool _focusApplied = false;
  final _focusKey = GlobalKey();

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  bool _matches(TimelineEvent e, List<String> words) => words.every(
        (w) =>
            e.content.contains(w) ||
            e.where.contains(w) ||
            e.sources.any((s) => s.label.contains(w)),
      );

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider);
    final title = context.t.terraTimelineTitle;
    final timeline = ref.watch(terraTimelineProvider);
    return LibraryScaffold(
      title: title,
      body: timeline.when(
        loading: () => const LoadingView(),
        error: (_, __) => LibraryMessage(
          icon: Icons.folder_off_sharp,
          title: context.t.libraryEmpty,
        ),
        data: (data) {
          if (data == null || data.isEmpty) {
            return LibraryMessage(
              icon: Icons.folder_off_sharp,
              title: context.t.libraryEmpty,
            );
          }
          if (!_focusApplied) {
            _focusApplied = true;
            final focus = widget.focusEventId == null
                ? null
                : data.byId(widget.focusEventId!);
            if (focus != null) {
              _group = timelineGroupOf(focus);
              WidgetsBinding.instance.addPostFrameCallback((_) {
                final target = _focusKey.currentContext;
                if (target != null && target.mounted) {
                  Scrollable.ensureVisible(target, alignment: 0.2);
                }
              });
            }
          }
          final groups = <String, int>{};
          for (final e in data.events) {
            groups.update(timelineGroupOf(e), (n) => n + 1, ifAbsent: () => 1);
          }
          final words = searchWords(_query);
          final shown = [
            for (final e in data.events)
              if ((_group == null || timelineGroupOf(e) == _group) &&
                  _matches(e, words))
                e,
          ];
          // The whole list carries the period headings.
          final items = <Object>[];
          String? last;
          for (final e in shown) {
            final g = timelineGroupOf(e);
            if (g != last) {
              items.add(g);
              last = g;
            }
            items.add(e);
          }
          Widget item(Object it) => it is String
              ? GroupHeading(
                  key: ValueKey('timeline-group-$it'),
                  title: it,
                  count: groups[it],
                )
              : _EventTile(
                  key: (it as TimelineEvent).id == widget.focusEventId
                      ? _focusKey
                      : ValueKey(it.id),
                  event: it,
                  marked: it.id == widget.focusEventId,
                  words: words,
                );
          final padding = EdgeInsets.fromLTRB(
            16,
            0,
            16,
            24 + MediaQuery.paddingOf(context).bottom,
          );
          return Column(
            children: [
              FilterField(
                hint: context.t.terraTimelineFilterHint,
                onChanged: (v) {
                  _debounce?.cancel();
                  _debounce = Timer(
                    const Duration(milliseconds: 250),
                    () => setState(() => _query = v),
                  );
                },
              ),
              _chips(context, groups, data.events.length),
              Expanded(
                child: items.isEmpty
                    ? LibraryMessage(
                        icon: Icons.search_off_sharp,
                        title: context.t.libraryNoResults,
                      )
                    // One period is short enough to build whole, so a
                    // cited event can be scrolled to.
                    : _group != null
                        ? ListView(
                            padding: padding,
                            children: [
                              _note(context, theme),
                              for (final it in items) item(it),
                            ],
                          )
                        : ListView.builder(
                            padding: padding,
                            itemCount: items.length + 1,
                            itemBuilder: (context, i) => i == 0
                                ? _note(context, theme)
                                : item(items[i - 1]),
                          ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _note(BuildContext context, AppThemeTokens theme) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        child: Text(
          context.t.terraTimelineNote,
          style: theme.text(13, color: theme.textSecondary, height: 1.5),
        ),
      );

  /// The periods as blocks that wrap onto more lines: one picks a period
  /// in place, "all" shows every one.
  Widget _chips(BuildContext context, Map<String, int> groups, int total) {
    Widget chip(String? group, String label, int count) => FilterBlock(
          key: ValueKey('timeline-chip-${group ?? 'all'}'),
          label: label,
          count: count,
          selected: _group == group,
          onTap: () => setState(() => _group = group),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: Wrap(
        spacing: 8,
        children: [
          chip(null, context.t.libraryAllEntries, total),
          for (final g in groups.entries) chip(g.key, g.key, g.value),
        ],
      ),
    );
  }
}

/// One event: when, what happened, what it is drawn from (a story the
/// knowledge base has is a button into the reader).
class _EventTile extends ConsumerWidget {
  const _EventTile({
    super.key,
    required this.event,
    required this.marked,
    required this.words,
  });

  final TimelineEvent event;
  final bool marked;
  final List<String> words;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    final label = event.timeLabel;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          // A cited event is marked with the trace line on its left.
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: marked ? theme.trace : Colors.transparent,
                width: 3,
              ),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
          child: SearchMarks(
            words: words,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if ((label != null && label != event.heading) ||
                    event.parallel)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        if (label != null && label != event.heading)
                          IndexTag(label, quiet: true),
                        if (event.parallel)
                          AccentPill(
                            context.t.terraTimelineParallel,
                            muted: true,
                          ),
                      ],
                    ),
                  ),
                MarkedText(event.content, style: readingStyle(theme, size: 15)),
                if (event.sources.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  for (final s in event.sources)
                    if (s.storyId != null)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: AppButton(
                          s.label,
                          small: true,
                          kind: ButtonKind.quiet,
                          icon: Icons.chevron_right_sharp,
                          onPressed: () => openStory(context, s.storyId!),
                        ),
                      )
                    else
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: MarkedText(
                          s.label,
                          style: theme.text(
                            13,
                            color: theme.textSecondary,
                            height: 1.5,
                          ),
                        ),
                      ),
                ],
              ],
            ),
          ),
        ),
        rowDivider(theme),
      ],
    );
  }
}
