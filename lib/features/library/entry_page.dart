import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/gamedata/build/story_naming.dart' show endingStoryKind;
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
import '../../shared/widgets/ef_widgets.dart';
import '../../shared/widgets/industrial_ui.dart';
import '../../shared/widgets/page_frame.dart';
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
            ? const LoadingView()
            : LibraryMessage(
                icon: Icons.folder_off_sharp,
                title: context.t.libraryEmpty,
              ),
      );
    }
    final texts = ref.watch(entryTextsProvider(e));
    final bindings = ref.watch(entryBindingsProvider(e.id));
    final blocks = texts.valueOrNull ?? const <EntryTextBlock>[];
    final parts = ref.watch(entryPartsProvider(e.id)).valueOrNull ??
        const <LibraryEntry>[];
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
        : [
            for (final s in parts)
              if (s.name != e.name) s,
          ];
    // A part that is not a story (an investigation's documents and report)
    // opens its own page, not the reader.
    Widget storyRow(LibraryEntry s) => Column(
          key: ValueKey('part-story-${s.id}'),
          children: [
            if (s.type == 'story')
              StoryRow(
                story: s,
                showGroup: false,
                read: progress[LibraryRef.story(s.rawId ?? '').toString()],
              )
            else
              EntryRow(entry: s, onTap: () => openEntry(context, s)),
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
      // One selection over the page: a profile's rows are separate items of
      // a lazy list.
      body: SelectionArea(
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: pagePadding(
                context,
                const EdgeInsets.fromLTRB(16, 12, 16, 32),
              ),
              sliver: SliverMainAxisGroup(
                slivers: [
                  SliverList.list(
                    children: [
                      _header(context, theme, e),
                      const SizedBox(height: 16),
                      if (blocks.isEmpty && !texts.isLoading)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            context.t.libraryNoText,
                            style: theme.text(15, color: theme.textSecondary),
                          ),
                        ),
                    ],
                  ),
                  for (final b in blocks)
                    textSliver(theme, e, b, ref.watch(nicknameProvider)),
                  SliverList.list(
                    children: [
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
                          _AttachedDialogue(
                            key: ValueKey('attached-${s.id}'),
                            story: s,
                          ),
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
                                labelStyle: theme.text(14),
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
                          // Stories are unlocked; documents (an
                          // investigation's) are what it holds.
                          title: unlocked.every((s) => s.type == 'story')
                              ? context.t.libraryParts
                              : bindingName(
                                  'part_of',
                                  outgoing: false,
                                  ownerType: e.type,
                                ),
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
                            if (b.relation != 'part_of' &&
                                !protagonists.contains(b))
                              b,
                        ],
                        e.type,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context, AppThemeTokens theme, LibraryEntry e) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The collection the entry belongs to opens its page.
          if (e.collectionName != null)
            Semantics(
              link: e.collectionId != null,
              child: PressRow(
                key: const ValueKey('entry-collection'),
                onTap: e.collectionId == null
                    ? null
                    : () => openCollection(context, e.collectionId!),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 40),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          e.collectionName!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.ui(
                            14,
                            weight: 700,
                            color: theme.textSecondary,
                          ),
                        ),
                      ),
                      if (e.collectionId != null)
                        Icon(
                          Icons.chevron_right_sharp,
                          size: 20,
                          color: theme.textSecondary,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          const SizedBox(height: 2),
          Text(e.name.isEmpty ? e.id : e.name, style: theme.heading(24)),
          const SizedBox(height: 10),
          const TriStrip(),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              AccentPill(entryTypeName(e.type)),
              FactsRow([
                if (codeCaption(e) != null) codeCaption(e)!,
                if (e.isChallengeStage) challengeStageLabel,
                if (groupLabel(e.type, e.group) != null)
                  groupLabel(e.type, e.group)!,
              ]),
            ],
          ),
        ],
      );

  /// Whether [text] (cleaned) of [e] is a profile document (`## ` parts).
  static bool _isProfile(LibraryEntry e, String text) =>
      markdownEntryTypes.contains(e.type) &&
      !eventEntryTypes.contains(e.type) &&
      text.contains('## ');

  /// [textBlock] as a sliver of a page: a profile document as the rows of a
  /// lazy list ([ProfileSliver]: a long file is laid out only as far as it
  /// is on screen), any other text as one box. [padding] is the room left
  /// and right.
  static Widget textSliver(
    AppThemeTokens theme,
    LibraryEntry e,
    EntryTextBlock b,
    String nickname, {
    EdgeInsets padding = EdgeInsets.zero,
  }) {
    final text = cleanRichText(withPlaceholders(b.content, nickname)).trim();
    if (_isProfile(e, text)) {
      return ProfileSliver(
        text,
        key: ValueKey('profile-${e.id}-${b.title}'),
        padding: padding.copyWith(bottom: 14),
      );
    }
    // Plain text and voice lines: the panel of [textBlock] around a lazy
    // list of its paragraphs (lines), so a long text is laid out only as far
    // as it is on screen.
    final heading = _heading(e, b);
    if (text.isNotEmpty &&
        !eventEntryTypes.contains(e.type) &&
        !markdownEntryTypes.contains(e.type)) {
      final voices =
          ProfileText.isVoice(heading) ? VoiceLines.parse(text) : null;
      final paragraphs = voices == null
          ? readingParagraphs(text, fields: isFieldList(text))
          : const <ReadingParagraph>[];
      final rows = voices?.length ?? paragraphs.length;
      final head = heading.isEmpty ? 0 : 1;
      return SliverPadding(
        padding: padding.copyWith(bottom: 14),
        sliver: DecoratedSliver(
          decoration: BoxDecoration(
            color: theme.cardSurface,
            border: Border.all(color: theme.divider),
          ),
          sliver: SliverMainAxisGroup(
            slivers: [
              // The panel's ink tab, as on every panel.
              SliverToBoxAdapter(
                child: Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: 40,
                    height: 4,
                    child: ColoredBox(color: theme.textPrimary),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, i) {
                      if (i < head) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _headingRow(theme, heading),
                        );
                      }
                      final r = i - head;
                      return voices != null
                          ? VoiceLine(
                              voices[r],
                              key: ValueKey('voice-$r'),
                              first: r == 0,
                            )
                          : ReadingParagraphView(paragraphs[r], theme: theme);
                    },
                    childCount: head + rows,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return SliverPadding(
      padding: padding,
      sliver: SliverToBoxAdapter(child: textBlock(theme, e, b, nickname)),
    );
  }

  /// The heading of a block: its section (the record's own part name),
  /// else its title, when that is neither the entry's name again nor the
  /// name of its kind (`敌人`, `集成战略收藏品`).
  static String _heading(LibraryEntry e, EntryTextBlock b) {
    final kind = entryTypeName(e.type);
    return [b.section, b.title].map((t) => t?.trim() ?? '').firstWhere(
          (t) =>
              t.isNotEmpty &&
              t != e.name &&
              !t.endsWith(e.name) &&
              !t.contains(kind) &&
              !kind.contains(t),
          orElse: () => '',
        );
  }

  static Widget _headingRow(AppThemeTokens theme, String heading) => Row(
        children: [
          Container(width: 4, height: 18, color: theme.trace),
          const SizedBox(width: 8),
          Expanded(child: Text(heading, style: theme.heading(16))),
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
    if (_isProfile(e, text)) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: ProfileText(text),
      );
    }
    final heading = _heading(e, b);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: ThemeAwareCard(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (heading.isNotEmpty) ...[
              _headingRow(theme, heading),
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
      final key =
          '${bindingName(b.relation, outgoing: b.outgoing, ownerType: ownerType)}'
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
        GroupHeading(
          title:
              '${g.key.split('\u0000').first} / ${g.key.split('\u0000').last}',
          count: g.value.length,
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final b in g.value.take(40))
              ActionChip(
                key: ValueKey('binding-${b.entry.id}'),
                label: Text(entryHeadline(b.entry)),
                labelStyle: theme.text(14),
                onPressed: () => openEntry(context, b.entry),
              ),
            if (g.value.length > 40)
              Text(
                '+${g.value.length - 40}',
                style: theme.field(),
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
    final lines =
        ref.watch(storyFullLinesProvider(story.rawId ?? '')).valueOrNull ??
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
                  style: theme.ui(13, weight: 700, color: theme.textSecondary),
                ),
              Text(
                withPlaceholders(l.content, nickname),
                style: readingStyle(theme, size: 15.5),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
