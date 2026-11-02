import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/l10n/l10n.dart';
import '../../shared/providers/theme_provider.dart';
import '../../shared/widgets/tool_row.dart';

/// The page tools of the wiki: one labelled row per tool (an icon alone does
/// not say what it does). Rendered inside the tray in [WikiBrowserPage]; the
/// parent draws the panel and the toggle.
class WikiToolbar extends ConsumerWidget {
  const WikiToolbar({
    super.key,
    required this.isDarkMode,
    required this.isBookmarked,
    required this.onZoomOut,
    required this.onZoomIn,
    required this.onRefresh,
    required this.onToggleDarkMode,
    required this.onToggleBookmark,
  });

  final bool isDarkMode;
  final bool isBookmarked;

  final VoidCallback onZoomOut;
  final VoidCallback onZoomIn;
  final VoidCallback onRefresh;
  final VoidCallback onToggleDarkMode;
  final VoidCallback onToggleBookmark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ToolRow(
          key: const ValueKey('wiki-tool-zoom-out'),
          icon: Icons.text_decrease_sharp,
          label: context.t.wikiZoomOut,
          theme: theme,
          onTap: onZoomOut,
        ),
        ToolRow(
          key: const ValueKey('wiki-tool-zoom-in'),
          icon: Icons.text_increase_sharp,
          label: context.t.wikiZoomIn,
          theme: theme,
          onTap: onZoomIn,
        ),
        ToolRow(
          key: const ValueKey('wiki-tool-refresh'),
          icon: Icons.refresh_sharp,
          label: context.t.wikiRefresh,
          theme: theme,
          onTap: onRefresh,
        ),
        Divider(color: theme.divider, height: 1),
        ToolRow(
          key: const ValueKey('wiki-tool-dark'),
          icon: Icons.dark_mode_sharp,
          label: context.t.wikiDarkPage,
          theme: theme,
          on: isDarkMode,
          onTap: onToggleDarkMode,
        ),
        ToolRow(
          key: const ValueKey('wiki-tool-bookmark'),
          icon: isBookmarked ? Icons.bookmark_sharp : Icons.bookmark_border_sharp,
          label: isBookmarked
              ? context.t.wikiBookmarkRemove
              : context.t.wikiBookmarkAdd,
          theme: theme,
          on: isBookmarked,
          onTap: onToggleBookmark,
        ),
      ],
    );
  }
}
