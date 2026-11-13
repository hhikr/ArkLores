import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/library/library_labels.dart' show entryName;
import '../../core/library/library_provider.dart';
import '../../core/library/library_queries.dart';
import '../../core/userdata/library_ref.dart';
import '../../shared/providers/theme_provider.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/ef_widgets.dart';

const double _rowHeight = 56;

/// The reader's contents: every story of the collection, the list opened at
/// the story being read, which [onOpen] does not get (it just closes).
Future<void> showStoryContents(
  BuildContext context, {
  required String storyId,
  required String collectionId,
  required String title,
  required ValueChanged<String> onOpen,
}) =>
    showAppSheet<void>(
      context,
      (sheet) => _StoryContents(
        storyId: storyId,
        collectionId: collectionId,
        title: title,
        onOpen: (id) {
          Navigator.of(sheet).pop();
          if (id != storyId) onOpen(id);
        },
      ),
    );

class _StoryContents extends ConsumerStatefulWidget {
  const _StoryContents({
    required this.storyId,
    required this.collectionId,
    required this.title,
    required this.onOpen,
  });
  final String storyId, collectionId, title;
  final ValueChanged<String> onOpen;

  @override
  ConsumerState<_StoryContents> createState() => _StoryContentsState();
}

class _StoryContentsState extends ConsumerState<_StoryContents> {
  /// Made when the stories are known.
  ScrollController? _scroll;

  @override
  void dispose() {
    _scroll?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final storyId = widget.storyId;
    final onOpen = widget.onOpen;
    final stories = [
      for (final s
          in ref.watch(collectionStoriesProvider(widget.collectionId)).valueOrNull ??
              const <LibraryEntry>[])
        if (s.rawId != null) s,
    ];
    final progress = ref.watch(readingProgressProvider).valueOrNull ?? const {};
    final total = stories.length * _rowHeight;
    final height = math.min(total, MediaQuery.sizeOf(context).height * 0.6);
    final at = stories.indexWhere((s) => s.rawId == storyId);
    if (stories.isNotEmpty) {
      // The story being read in the middle, as far as the list allows.
      _scroll ??= ScrollController(
        initialScrollOffset: at < 0
            ? 0
            : (at * _rowHeight - (height - _rowHeight) / 2)
                .clamp(0.0, total - height),
      );
    }
    return SheetFrame(
      title: widget.title,
      children: [
        SizedBox(
          height: height,
          child: stories.isEmpty
              ? null
              : ListView.builder(
                  key: const ValueKey('story-contents'),
                  controller: _scroll,
                  itemExtent: _rowHeight,
                  itemCount: stories.length,
                  itemBuilder: (context, i) => _ContentsRow(
                    story: stories[i],
                    current: i == at,
                    finished: progress[
                                LibraryRef.story(stories[i].rawId!).toString()]
                            ?.hasCompleted ??
                        false,
                    onTap: () => onOpen(stories[i].rawId!),
                  ),
                ),
        ),
      ],
    );
  }
}

class _ContentsRow extends ConsumerWidget {
  const _ContentsRow({
    required this.story,
    required this.current,
    required this.finished,
    required this.onTap,
  });
  final LibraryEntry story;
  final bool current, finished;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    final code = story.code;
    final group = story.group;
    return Semantics(
      button: true,
      selected: current,
      child: PressRow(
        key: ValueKey('story-contents-${story.rawId}'),
        marked: current,
        onTap: onTap,
        child: Container(
          height: _rowHeight,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: theme.divider)),
          ),
          child: Row(
            children: [
              if (code != null && code.isNotEmpty) ...[
                IndexTag(code, current: current),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  [
                    entryName(story),
                    if (group != null && !entryName(story).contains(group))
                      '/ $group',
                  ].where((s) => s.isNotEmpty).join(' '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.heading(
                    15,
                    color: current ? theme.textPrimary : theme.textSecondary,
                  ),
                ),
              ),
              if (finished)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Icon(
                    Icons.check_sharp,
                    size: 18,
                    color: theme.textSecondary,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
