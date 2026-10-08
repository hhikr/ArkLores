import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/library/library_provider.dart';
import '../../core/library/library_queries.dart';
import '../../core/llm/llm_provider.dart' show embeddingClientProvider;
import '../../core/userdata/library_ref.dart';
import '../../shared/l10n/l10n.dart';
import '../../shared/providers/theme_provider.dart';
import '../../shared/theme/app_theme.dart';
import 'library_pages.dart';
import 'library_widgets.dart';

// ─── Search ───────────────────────────────────────────────────────

/// The search button of a library page: searches what the page shows
/// ([scope], named [label]), or the whole library from the top page.
class LibrarySearchButton extends StatelessWidget {
  const LibrarySearchButton({
    super.key,
    this.scope = everywhere,
    this.label,
  });

  final LibraryScope scope;
  final String? label;

  @override
  Widget build(BuildContext context) => IconButton(
        key: const ValueKey('library-search'),
        tooltip: context.t.librarySearchHint,
        icon: const Icon(Icons.search_sharp),
        onPressed: () => openSearch(context, scope: scope, label: label),
      );
}

/// Under a filter that found nothing: the search for the same words in the
/// same place, which also tries close names and the texts.
class SearchFurtherButton extends StatelessWidget {
  const SearchFurtherButton({
    super.key,
    required this.query,
    this.scope = everywhere,
    this.label,
  });

  final String query;
  final LibraryScope scope;
  final String? label;

  @override
  Widget build(BuildContext context) => TextButton.icon(
        key: const ValueKey('search-further'),
        onPressed: () =>
            openSearch(context, scope: scope, label: label, query: query.trim()),
        icon: const Icon(Icons.manage_search_sharp, size: 18),
        label: Text(context.t.librarySearchFurther(query.trim())),
      );
}

/// Search over names and codes; when no name has the query, close names and
/// the texts that contain it; on request, stories close in meaning (the
/// story vectors, through the embedding service).
class LibrarySearchPage extends ConsumerStatefulWidget {
  const LibrarySearchPage({
    super.key,
    this.scope = everywhere,
    this.scopeLabel,
    this.initialQuery = '',
  });

  final LibraryScope scope;

  /// The name of the page [scope] stands for (shown as a removable chip).
  final String? scopeLabel;
  final String initialQuery;

  @override
  ConsumerState<LibrarySearchPage> createState() => _LibrarySearchPageState();
}

class _LibrarySearchPageState extends ConsumerState<LibrarySearchPage> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialQuery);
  late String _query = widget.initialQuery;
  late LibraryScope _scope = widget.scope;
  Timer? _debounce;

  /// The texts were asked for although names matched.
  bool _text = false;

  /// The semantic search was asked for (for this query).
  bool _semantic = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _setQuery(String value) {
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 300),
      () => setState(() {
        _query = value;
        _text = false;
        _semantic = false;
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider);
    final q = _query.trim();
    final result = q.isEmpty
        ? null
        : ref.watch(
            librarySearchProvider((query: q, scope: _scope, text: _text)),
          );
    final label = widget.scopeLabel;
    return LibraryScaffold(
      title: context.t.librarySearchTitle,
      body: Column(
        children: [
          FilterField(
            controller: _controller,
            autofocus: true,
            hint: context.t.librarySearchHint,
            onChanged: _setQuery,
          ),
          if (_scope != everywhere && label != null)
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                child: InputChip(
                  key: const ValueKey('search-scope'),
                  label: Text(
                    context.t.librarySearchIn(label),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.bodyFont.copyWith(fontSize: 12.5),
                  ),
                  backgroundColor: theme.cardSurface,
                  side: BorderSide(color: theme.cardBorder),
                  visualDensity: VisualDensity.compact,
                  deleteIcon: const Icon(Icons.close_sharp, size: 16),
                  deleteButtonTooltipMessage: context.t.librarySearchEverywhere,
                  onDeleted: () => setState(() => _scope = everywhere),
                ),
              ),
            ),
          Expanded(
            child: result == null
                ? const SizedBox.shrink()
                : result.when(
                    skipLoadingOnReload: true,
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (_, __) => LibraryMessage(
                      icon: Icons.search_off_sharp,
                      title: context.t.libraryNoResults,
                    ),
                    data: (r) => _results(theme, q, r),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _results(AppThemeTokens theme, String q, LibrarySearchResult r) {
    final semanticReady = ref.watch(embeddingClientProvider) != null;
    final semantic = _semantic
        ? ref.watch(librarySemanticProvider((query: q, scope: _scope)))
        : null;
    if (r.isEmpty && semantic == null && !semanticReady) {
      return LibraryMessage(
        icon: Icons.search_off_sharp,
        title: context.t.libraryNoResults,
        description: context.t.librarySearchSemanticNeedsService,
      );
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        if (!r.hasNameHits && !r.isEmpty)
          _note(theme, context.t.librarySearchNoNameMatch(q)),
        ..._collections(theme, context.t.librarySearchCollections, r.collections),
        ..._entries(theme, context.t.librarySearchEntries, r.entries),
        ..._collections(theme, context.t.librarySearchSimilar, r.similarCollections),
        ..._entries(
          theme,
          r.similarCollections.isEmpty ? context.t.librarySearchSimilar : null,
          r.similar,
        ),
        if (r.mentions.isNotEmpty) ...[
          _heading(theme, context.t.librarySearchMentions),
          for (final hit in r.mentions) ...[
            _textHitRow(theme, hit, count: true),
            rowDivider(theme),
          ],
        ] else if (r.searchedText && r.hasNameHits)
          _note(theme, context.t.librarySearchNoMentions),
        if (!r.searchedText)
          _action(
            key: 'search-text',
            icon: Icons.text_snippet_outlined,
            label: context.t.librarySearchInText(q),
            onTap: () => setState(() => _text = true),
          ),
        if (semantic == null && semanticReady)
          _action(
            key: 'search-semantic',
            icon: Icons.auto_awesome_outlined,
            label: context.t.librarySearchSemantic,
            onTap: () => setState(() => _semantic = true),
          ),
        if (semantic != null) ..._semanticSection(theme, semantic),
        if (r.isEmpty && semantic == null)
          _note(theme, context.t.libraryNoResults),
      ],
    );
  }

  List<Widget> _semanticSection(
    AppThemeTokens theme,
    AsyncValue<List<LibraryTextHit>> semantic,
  ) =>
      [
        _heading(theme, context.t.librarySearchSemanticTitle),
        ...semantic.when(
          loading: () => [
            const Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: CircularProgressIndicator()),
            ),
          ],
          error: (e, _) => [
            _note(
              theme,
              switch (e) {
                SemanticSearchUnavailable(problem: final p) => switch (p) {
                    SemanticSearchProblem.noService =>
                      context.t.librarySearchSemanticNeedsService,
                    SemanticSearchProblem.noVectors =>
                      context.t.librarySearchSemanticNoVectors,
                    SemanticSearchProblem.otherModel =>
                      context.t.librarySearchSemanticOtherModel,
                  },
                _ => context.t.librarySearchSemanticFailed,
              },
            ),
          ],
          data: (hits) => hits.isEmpty
              ? [_note(theme, context.t.libraryNoResults)]
              : [
                  for (final hit in hits) ...[
                    _textHitRow(theme, hit),
                    rowDivider(theme),
                  ],
                ],
        ),
      ];

  List<Widget> _collections(
    AppThemeTokens theme,
    String heading,
    List<LibraryCollection> list,
  ) =>
      list.isEmpty
          ? const []
          : [
              _heading(theme, heading),
              for (final c in list) ...[
                LibraryRow(
                  key: ValueKey('hit-collection-${c.id}'),
                  title: c.name,
                  subtitle: shelfLabel(context, c.kind),
                  subtitleLines: 1,
                  trailing: Icon(
                    Icons.chevron_right_sharp,
                    color: theme.textMuted,
                  ),
                  onTap: () => openCollectionOf(context, c),
                ),
                rowDivider(theme),
              ],
            ];

  List<Widget> _entries(
    AppThemeTokens theme,
    String? heading,
    List<LibraryEntry> list,
  ) {
    if (list.isEmpty) return const [];
    final progress = ref.watch(readingProgressProvider).valueOrNull ?? const {};
    return [
      if (heading != null) _heading(theme, heading),
      for (final e in list) ...[
        e.isStory
            ? StoryRow(
                story: e,
                read: progress[LibraryRef.story(e.rawId ?? '').toString()],
              )
            : EntryRow(entry: e, onTap: () => openEntry(context, e)),
        rowDivider(theme),
      ],
    ];
  }

  /// An entry whose text matched: its name and place, the passage; a story
  /// opens at the passage.
  Widget _textHitRow(
    AppThemeTokens theme,
    LibraryTextHit hit, {
    bool count = false,
  }) {
    final e = hit.entry;
    final place = [
      if (e.collectionName != null) e.collectionName!,
      if (e.code != null) e.code!,
      if (count && hit.count > 1) context.t.librarySearchMatchCount(hit.count),
    ].join(' · ');
    final story = e.rawId;
    return LibraryRow(
      key: ValueKey('hit-text-${e.id}'),
      title: e.name.isEmpty ? e.id : e.name,
      subtitle: [if (place.isNotEmpty) place, hit.snippet].join('\n'),
      subtitleLines: 3,
      trailing: Icon(Icons.chevron_right_sharp, color: theme.textMuted),
      onTap: () => e.isStory && story != null && hit.line != null
          ? openStoryAt(
              context,
              story,
              hit.line!,
              hit.lineEnd ?? hit.line!,
            )
          : openEntry(context, e),
    );
  }

  Widget _action({
    required String key,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    final theme = ref.watch(themeProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      child: Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          key: ValueKey(key),
          onPressed: onTap,
          icon: Icon(icon, size: 18, color: theme.accentText),
          label: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.bodyFont.copyWith(
              color: theme.accentText,
              fontSize: 13.5,
            ),
          ),
        ),
      ),
    );
  }

  Widget _note(AppThemeTokens theme, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Text(
          text,
          style: theme.bodyFont.copyWith(
            color: theme.textSecondary,
            fontSize: 12.5,
            height: 1.5,
          ),
        ),
      );

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
