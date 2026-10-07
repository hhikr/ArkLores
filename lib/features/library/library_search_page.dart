import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/library/library_provider.dart';
import '../../core/userdata/library_ref.dart';
import '../../shared/l10n/l10n.dart';
import '../../shared/providers/theme_provider.dart';
import '../../shared/theme/app_theme.dart';
import 'library_pages.dart';
import 'library_widgets.dart';

// ─── Search ───────────────────────────────────────────────────────

/// Search over story-set names, entry names and codes.
class LibrarySearchPage extends ConsumerStatefulWidget {
  const LibrarySearchPage({super.key});

  @override
  ConsumerState<LibrarySearchPage> createState() => _LibrarySearchPageState();
}

class _LibrarySearchPageState extends ConsumerState<LibrarySearchPage> {
  String _query = '';
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider);
    final result = _query.trim().isEmpty
        ? null
        : ref.watch(librarySearchProvider(_query.trim()));
    final progress = ref.watch(readingProgressProvider).valueOrNull ?? const {};
    return LibraryScaffold(
      title: context.t.librarySearchTitle,
      body: Column(
        children: [
          FilterField(
            autofocus: true,
            hint: context.t.librarySearchHint,
            onChanged: (v) {
              _debounce?.cancel();
              _debounce = Timer(
                const Duration(milliseconds: 300),
                () => setState(() => _query = v),
              );
            },
          ),
          Expanded(
            child: result == null
                ? const SizedBox.shrink()
                : result.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (_, __) => LibraryMessage(
                      icon: Icons.search_off_rounded,
                      title: context.t.libraryNoResults,
                    ),
                    data: (r) {
                      if (r.collections.isEmpty && r.entries.isEmpty) {
                        return LibraryMessage(
                          icon: Icons.search_off_rounded,
                          title: context.t.libraryNoResults,
                        );
                      }
                      return ListView(
                        padding: const EdgeInsets.only(bottom: 24),
                        children: [
                          if (r.collections.isNotEmpty) ...[
                            _heading(
                              theme,
                              context.t.librarySearchCollections,
                            ),
                            for (final c in r.collections) ...[
                              LibraryRow(
                                key: ValueKey('hit-collection-${c.id}'),
                                title: c.name,
                                subtitle: shelfLabel(context, c.kind),
                                subtitleLines: 1,
                                trailing: Icon(
                                  Icons.chevron_right_rounded,
                                  color: theme.textMuted,
                                ),
                                onTap: () => openCollection(context, c.id),
                              ),
                              rowDivider(theme),
                            ],
                          ],
                          if (r.entries.isNotEmpty) ...[
                            _heading(theme, context.t.librarySearchEntries),
                            for (final e in r.entries) ...[
                              e.isStory
                                  ? StoryRow(
                                      story: e,
                                      read: progress[LibraryRef.story(
                                        e.rawId ?? '',
                                      ).toString()],
                                    )
                                  : EntryRow(
                                      entry: e,
                                      onTap: () => openEntry(context, e),
                                    ),
                              rowDivider(theme),
                            ],
                          ],
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _heading(AppThemeTokens theme, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
        child: Text(
          text,
          style: theme.bodyFont.copyWith(
            color: theme.textMuted,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
          ),
        ),
      );
}
