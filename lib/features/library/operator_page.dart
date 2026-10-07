import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/library/library_labels.dart';
import '../../core/library/library_provider.dart';
import '../../core/library/library_queries.dart';
import '../../shared/l10n/l10n.dart';
import '../../shared/providers/settings_provider.dart';
import '../../shared/providers/theme_provider.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/industrial_ui.dart';
import '../../shared/widgets/theme_aware_card.dart';
import 'library_pages.dart';
import 'library_widgets.dart';

// ─── One operator ─────────────────────────────────────────────────

/// An operator's page: everything the knowledge base holds about it in one
/// place — record sets (密录), modules, skins, paradox simulation stages and
/// the profile text.
class OperatorPage extends ConsumerWidget {
  const OperatorPage({super.key, required this.entryId});

  final String entryId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    final entry = ref.watch(entryProvider(entryId));
    final e = entry.valueOrNull;
    if (e == null) {
      return LibraryScaffold(
        title: '',
        body: entry.isLoading
            ? const Center(child: CircularProgressIndicator())
            : LibraryMessage(
                icon: Icons.folder_off_rounded,
                title: context.t.libraryEmpty,
              ),
      );
    }
    final records = ref.watch(operatorMemoriesProvider(e.id)).valueOrNull ??
        const <LibraryCollection>[];
    final owned = ref.watch(operatorOwnedProvider(e.id)).valueOrNull ??
        const <LibraryEntry>[];
    final blocks = ref.watch(entryTextsProvider(e)).valueOrNull ??
        const <EntryTextBlock>[];
    final samePerson = ref.watch(samePersonProvider(e.id)).valueOrNull ??
        const <LibraryEntry>[];

    // Owned entries by type, in the order the query returns them.
    final byType = <String, List<LibraryEntry>>{};
    for (final o in owned) {
      (byType[o.type] ??= []).add(o);
    }

    Widget header(String title, String code) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: IndustrialSectionHeader(theme: theme, title: title, code: code),
        );

    return LibraryScaffold(
      title: e.name.isEmpty ? e.id : e.name,
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: _headerCard(context, theme, e, records, byType),
          ),
          // The profile (archive) leads: it is what the page is about.
          if (blocks.isNotEmpty) ...[
            header(context.t.libraryOperatorProfile, 'profile'),
            const SizedBox(height: 4),
            for (final b in blocks)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: EntryPage.textBlock(theme, e, b, ref.watch(nicknameProvider)),
              ),
          ],
          if (samePerson.isNotEmpty) ...[
            header(bindingName('same_person', outgoing: true), 'same_person'),
            for (final o in samePerson) ...[
              LibraryRow(
                key: ValueKey('operator-same-${o.id}'),
                title: o.name.isEmpty ? o.id : o.name,
                subtitle: codeCaption(o),
                subtitleLines: 1,
                trailing: Icon(Icons.chevron_right_rounded, color: theme.textMuted),
                onTap: () => openEntry(context, o),
              ),
              rowDivider(theme),
            ],
          ],
          if (records.isNotEmpty) ...[
            header(context.t.libraryOperatorRecords, 'records'),
            for (final c in records) ...[
              LibraryRow(
                key: ValueKey('operator-record-${c.id}'),
                title: c.name,
                subtitle: context.t.libraryCountStories(c.stories),
                subtitleLines: 1,
                trailing: Icon(Icons.chevron_right_rounded, color: theme.textMuted),
                onTap: () => openCollection(context, c.id),
              ),
              rowDivider(theme),
            ],
          ],
          for (final group in byType.entries) ...[
            header(entryTypeName(group.key), group.key),
            for (final o in group.value) ...[
              LibraryRow(
                key: ValueKey('operator-owned-${o.id}'),
                title: o.name.isEmpty ? o.id : o.name,
                subtitle: _ownedCaption(o),
                subtitleLines: 1,
                trailing: Icon(Icons.chevron_right_rounded, color: theme.textMuted),
                onTap: () => openEntry(context, o),
              ),
              rowDivider(theme),
            ],
          ],
        ],
      ),
    );
  }

  /// The line under a module / skin / paradox simulation: a module's type
  /// mark, a skin's series.
  static String? _ownedCaption(LibraryEntry o) {
    if (o.type == 'module') {
      final code = o.code ?? '';
      return code.isNotEmpty && code.length <= 3 ? '$code 型' : null;
    }
    return groupLabel(o.type, o.group);
  }

  Widget _headerCard(
    BuildContext context,
    AppThemeTokens theme,
    LibraryEntry e,
    List<LibraryCollection> records,
    Map<String, List<LibraryEntry>> byType,
  ) {
    final stories = records.fold<int>(0, (n, c) => n + c.stories);
    return ThemeAwareCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(shelfIcon(operatorShelf), color: theme.accentText, size: 28),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  e.name.isEmpty ? e.id : e.name,
                  style: theme.titleFont.copyWith(fontSize: 18, height: 1.25),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    AccentPill(context.t.shelfMemory),
                    if (codeCaption(e) != null)
                      AccentPill(codeCaption(e)!, muted: true),
                    if (stories > 0)
                      AccentPill(
                        context.t.libraryCountStories(stories),
                        muted: true,
                      ),
                    for (final g in byType.entries)
                      AccentPill(
                        '${entryTypeName(g.key)} ${g.value.length}',
                        muted: true,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
