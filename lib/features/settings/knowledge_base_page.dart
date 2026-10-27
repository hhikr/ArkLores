import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/gamedata/game.dart';
import '../../core/gamedata/gamedata_channel.dart';
import '../../shared/l10n/l10n.dart';
import '../../shared/providers/theme_provider.dart';
import '../../shared/widgets/page_frame.dart';
import '../library/library_pages.dart' show gameLabel;
import '../materials/materials_page.dart' show SwitchedPages;
import 'game_asset_card.dart';
import 'kb_common.dart';
import 'source_build_card.dart';
import 'story_art_pack_card.dart';
import 'story_vector_card.dart';

/// The knowledge bases: one page per game, chosen in the top bar (as in the
/// library; not swiped between). Each page has the same parts in the same
/// order — the game's official knowledge base, its vectors, and how it is
/// kept up to date (Arknights: from the game data on the device; Endfield:
/// with the app's releases).
class KnowledgeBasePage extends ConsumerStatefulWidget {
  const KnowledgeBasePage({super.key});

  @override
  ConsumerState<KnowledgeBasePage> createState() => _KnowledgeBasePageState();
}

class _KnowledgeBasePageState extends ConsumerState<KnowledgeBasePage> {
  /// Index into [Game.values].
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    // A knowledge base uploaded since the app started (or since it last
    // looked) is found when the page opens.
    Future.microtask(() {
      if (mounted) ref.invalidate(gameDataChannelProvider);
    });
  }

  @override
  Widget build(BuildContext context) {
    return PageScaffold(
      title: context.t.kbTitle,
      scrollUnder: true,
      actions: [
        for (final (i, game) in Game.values.indexed)
          TopTab(
            key: ValueKey('kb-tab-${game.key}'),
            label: gameLabel(context, game),
            selected: _tab == i,
            onTap: () => setState(() => _tab = i),
          ),
      ],
      body: SwitchedPages(
        index: _tab,
        children: [
          for (final game in Game.values) _GamePage(game: game),
        ],
      ),
    );
  }
}

class _GamePage extends ConsumerWidget {
  const _GamePage({required this.game});

  final Game game;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    return ListView(
      key: ValueKey('kb-game-${game.key}'),
      padding: pagePadding(context, const EdgeInsets.fromLTRB(16, 16, 16, 32)),
      children: [
        GameAssetCard(
          game: game,
          title: game == Game.endfield
              ? context.t.kbEndfieldTitle
              : context.t.kbArknightsTitle,
        ),
        const SizedBox(height: 16),
        StoryVectorCard(game: game),
        const SizedBox(height: 12),
        StoryArtPackCard(game: game),
        const SizedBox(height: 16),
        if (game == Game.arknights)
          const SourceBuildCard()
        else
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: kbNote(
              context.t.kbEndfieldSourceNote,
              theme,
              theme.textSecondary,
            ),
          ),
      ],
    );
  }
}
