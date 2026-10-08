import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/gamedata/build/story_naming.dart'
    show endingStoryKind;
import '../../core/gamedata/build/text_harvest.dart' show cleanRichText;
import '../../core/gamedata/story_coverage_models.dart' show StoryLineEntry;
import '../../core/library/library_labels.dart';
import '../../core/library/library_provider.dart';
import '../../core/library/library_queries.dart';
import '../../core/library/placeholders.dart';
import '../../core/userdata/library_ref.dart';
import '../../shared/l10n/l10n.dart';
import '../../shared/providers/settings_provider.dart';
import '../../shared/providers/theme_provider.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/floating_bar.dart';
import '../../shared/widgets/industrial_ui.dart';
import '../../shared/widgets/theme_aware_card.dart';
import '../ai/story_labels_provider.dart' show storyFullLinesProvider;
import 'library_pages.dart';
import 'library_widgets.dart';

/// One non-story entry: its text and what it is bound to.
class EntryPage extends ConsumerWidget {
  const EntryPage({super.key, required this.entryId});

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
                icon: Icons.folder_off_sharp,
                title: context.t.libraryEmpty,
              ),
      );
    }
    final texts = ref.watch(entryTextsProvider(e));
    final bindings = ref.watch(entryBindingsProvider(e.id));
    final blocks = texts.valueOrNull ?? const <EntryTextBlock>[];
    final parts =
        ref.watch(entryPartsProvider(e.id)).valueOrNull ?? const <LibraryEntry>[];
    final progress = ref.watch(readingProgressProvider).valueOrNull ?? const {};
    final attached = ref.watch(attachedStoriesProvider(e.id)).valueOrNull ??
        const <LibraryEntry>[];
    final all = bindings.valueOrNull ?? const <EntryBinding>[];
    // A month squad's protagonist comes before its stories; the story that
    // has the entry's own name (an ending's) comes right after its sentence,
    // the others are what it unlocks.
    final protagonists = [
      for (final b in all)
        if (e.type == 'roguelike_squad' &&
            b.relation == 'features' &&
            b.outgoing)
          b,
    ];
    // An act of a sandbox's plot holds all its stories in order; an ending
    // or a squad has its own story and what it unlocks.
    final own = e.type == 'sandbox_act'
        ? parts
        : [
            for (final s in parts)
              if (s.name == e.name || s.group == endingStoryKind) s,
          ];
    final unlocked = e.type == 'sandbox_act'
        ? const <LibraryEntry>[]
        : [for (final s in parts) if (s.name != e.name) s];
    Widget storyRow(LibraryEntry s) => Column(
          key: ValueKey('part-story-${s.id}'),
          children: [
            StoryRow(
              story: s,
              showGroup: false,
              read: progress[LibraryRef.story(s.rawId ?? '').toString()],
            ),
            rowDivider(theme),
          ],
        );

    return LibraryScaffold(
      title: e.name.isEmpty ? e.id : e.name,
      scrollUnder: true,
      // An entry's search looks in its collection (the whole library for
      // the codex's free entries).
      actions: [
        LibrarySearchButton(
          scope: e.collectionId == null
              ? everywhere
              : listScope(collectionId: e.collectionId),
          label: e.collectionName,
        ),
      ],
      body: ListView(
        padding: floatingPadding(
          context,
          const EdgeInsets.fromLTRB(16, 12, 16, 32),
        ),
        children: [
          _header(context, theme, e),
          const SizedBox(height: 16),
          if (blocks.isEmpty && !texts.isLoading)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                context.t.libraryNoText,
                style: theme.bodyFont.copyWith(color: theme.textSecondary),
              ),
            ),
          for (final b in blocks) textBlock(theme, e, b, ref.watch(nicknameProvider)),
          for (final s in own) storyRow(s),
          // Dialogue played in the battle of a stage, read here (a stage with
          // a story of its own has it at the end of that story).
          if (attached.isNotEmpty) ...[
            IndustrialSectionHeader(
              theme: theme,
              title: context.t.storyReaderBattleDialogue,
              code: 'battle',
            ),
            for (final s in attached)
              _AttachedDialogue(key: ValueKey('attached-${s.id}'), story: s),
            const SizedBox(height: 8),
          ],
          if (protagonists.isNotEmpty) ...[
            IndustrialSectionHeader(
              theme: theme,
              title: bindingName(
                'features',
                outgoing: true,
                ownerType: e.type,
              ),
              code: 'protagonist',
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final b in protagonists)
                  ActionChip(
                    key: ValueKey('binding-${b.entry.id}'),
                    label: Text(entryHeadline(b.entry)),
                    labelStyle: theme.bodyFont.copyWith(fontSize: 12.5),
                    backgroundColor: theme.cardSurface,
                    side: BorderSide(color: theme.cardBorder),
                    onPressed: () => openEntry(context, b.entry),
                  ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          // What the entry unlocks (an ending's pages, a month squad's three
          // stories), in reading order.
          if (unlocked.isNotEmpty) ...[
            IndustrialSectionHeader(
              theme: theme,
              title: context.t.libraryParts,
              code: 'parts',
            ),
            for (final s in unlocked) storyRow(s),
            const SizedBox(height: 8),
          ],
          ..._bindingSections(
            context,
            theme,
            [
              for (final b in all)
                if (b.relation != 'part_of' && !protagonists.contains(b)) b,
            ],
            e.type,
          ),
        ],
      ),
    );
  }

  Widget _header(BuildContext context, AppThemeTokens theme, LibraryEntry e) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The collection the entry belongs to opens its page.
          if (e.collectionName != null)
            InkWell(
              key: const ValueKey('entry-collection'),
              onTap: e.collectionId == null
                  ? null
                  : () => openCollection(context, e.collectionId!),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: e.collectionName!),
                      if (e.collectionId != null)
                        const WidgetSpan(
                          alignment: PlaceholderAlignment.middle,
                          child: Icon(Icons.chevron_right_sharp, size: 16),
                        ),
                    ],
                  ),
                  style: theme.bodyFont.copyWith(
                    color: theme.accentText,
                    fontSize: 12,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),
          const SizedBox(height: 2),
          Text(
            e.name.isEmpty ? e.id : e.name,
            style: theme.titleFont.copyWith(fontSize: 22, height: 1.25),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              AccentPill(entryTypeName(e.type)),
              if (codeCaption(e) != null)
                AccentPill(codeCaption(e)!, muted: true),
              if (groupLabel(e.type, e.group) != null)
                AccentPill(groupLabel(e.type, e.group)!, muted: true),
            ],
          ),
        ],
      );

  static Widget textBlock(
    AppThemeTokens theme,
    LibraryEntry e,
    EntryTextBlock b,
    String nickname,
  ) {
    final text = cleanRichText(withPlaceholders(b.content, nickname)).trim();
    if (text.isEmpty) return const SizedBox.shrink();
    // A profile document: its parts fold, each open.
    if (markdownEntryTypes.contains(e.type) &&
        !eventEntryTypes.contains(e.type) &&
        text.contains('## ')) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: ProfileText(text),
      );
    }
    // The heading of a block: its section (the record's own part name),
    // else its title, when that is neither the entry's name again nor the
    // name of its kind (`敌人`, `集成战略收藏品`).
    final kind = entryTypeName(e.type);
    final heading = [b.section, b.title]
        .map((t) => t?.trim() ?? '')
        .firstWhere(
          (t) =>
              t.isNotEmpty &&
              t != e.name &&
              !t.endsWith(e.name) &&
              !t.contains(kind) &&
              !kind.contains(t),
          orElse: () => '',
        );
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: ThemeAwareCard(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (heading.isNotEmpty) ...[
              Row(
                children: [
                  Container(width: 3, height: 14, color: theme.accentPrimary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      heading,
                      style: theme.titleFont.copyWith(fontSize: 14, height: 1.3),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
            ],
            if (eventEntryTypes.contains(e.type))
              EventText(text)
            else if (markdownEntryTypes.contains(e.type))
              MarkdownText(text)
            else if (ProfileText.isVoice(heading))
              VoiceLines(text)
            else
              ReadingText(text, fields: isFieldList(text)),
          ],
        ),
      ),
    );
  }

  /// Bindings grouped by what they say and what they point at; each group
  /// is a heading and a wrap of chips that open the bound entry.
  List<Widget> _bindingSections(
    BuildContext context,
    AppThemeTokens theme,
    List<EntryBinding> bindings,
    String ownerType,
  ) {
    if (bindings.isEmpty) return const [];
    final groups = <String, List<EntryBinding>>{};
    for (final b in bindings) {
      final key = '${bindingName(b.relation, outgoing: b.outgoing, ownerType: ownerType)}'
          '\u0000${entryTypeName(b.entry.type)}';
      (groups[key] ??= []).add(b);
    }
    return [
      Padding(
        padding: const EdgeInsets.only(top: 6),
        child: IndustrialSectionHeader(
          theme: theme,
          title: context.t.libraryRelated,
          code: 'bindings',
        ),
      ),
      for (final g in groups.entries) ...[
        Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 8),
          child: Text(
            '${g.key.split('\u0000').first} · ${g.key.split('\u0000').last}'
            '  ${g.value.length}',
            style: theme.bodyFont.copyWith(
              color: theme.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final b in g.value.take(40))
              ActionChip(
                key: ValueKey('binding-${b.entry.id}'),
                label: Text(entryHeadline(b.entry)),
                labelStyle: theme.bodyFont.copyWith(fontSize: 12.5),
                backgroundColor: theme.cardSurface,
                side: BorderSide(color: theme.cardBorder),
                onPressed: () => openEntry(context, b.entry),
              ),
            if (g.value.length > 40)
              Text(
                '+${g.value.length - 40}',
                style: theme.bodyFont.copyWith(color: theme.textMuted),
              ),
          ],
        ),
      ],
    ];
  }
}

/// The lines of one attached story (in-battle dialogue), shown in the page of
/// its stage.
class _AttachedDialogue extends ConsumerWidget {
  const _AttachedDialogue({super.key, required this.story});

  final LibraryEntry story;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    final nickname = ref.watch(nicknameProvider);
    final lines = ref.watch(storyFullLinesProvider(story.rawId ?? '')).valueOrNull ??
        const <StoryLineEntry>[];
    final shown = [
      for (final l in lines)
        if (l.kind != 'title' && l.content.trim().isNotEmpty) l,
    ];
    if (shown.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: ThemeAwareCard(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (i, l) in shown.indexed) ...[
              if (i > 0) const SizedBox(height: 10),
              if ((l.speaker ?? '').trim().isNotEmpty)
                Text(
                  l.speaker!.trim(),
                  style: theme.bodyFont.copyWith(
                    color: theme.accentText,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              Text(
                withPlaceholders(l.content, nickname),
                style: readingStyle(theme, size: 15),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
