import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/gamedata/game.dart';
import '../../core/gamedata/gamedata_installer.dart';
import '../../core/gamedata/gamedata_provider.dart';
import '../../shared/l10n/l10n.dart';
import '../../shared/providers/theme_provider.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/floating_bar.dart';
import '../../shared/widgets/theme_aware_card.dart';
import 'game_asset_card.dart';
import 'kb_common.dart';
import 'source_build_card.dart';
import 'story_vector_card.dart';

/// Knowledge base management page for the structured Chinese GameData DB.
class KnowledgeBasePage extends ConsumerStatefulWidget {
  const KnowledgeBasePage({super.key});

  @override
  ConsumerState<KnowledgeBasePage> createState() => _KnowledgeBasePageState();
}

class _KnowledgeBasePageState extends ConsumerState<KnowledgeBasePage> {

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider);
    final gameDataStatusAsync = ref.watch(gameDataInstallStatusProvider);

    return FloatingScaffold(
      title: context.t.kbTitle,
      scrollUnder: true,
      body: ListView(
        padding: floatingPadding(context, const EdgeInsets.all(16)),
        children: [
          Center(
            child: Icon(
              Icons.storage_sharp,
              size: 48,
              color: theme.accentPrimary.withValues(alpha: 0.4),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            context.t.kbStructuredTitle,
            style: theme.titleFont.copyWith(fontSize: 18),
          ),
          const SizedBox(height: 12),
          ThemeAwareCard(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_sharp,
                    color: theme.accentPrimary, size: 22,),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    context.t.kbScopeDescription,
                    style: theme.bodyFont.copyWith(
                      color: theme.textSecondary,
                      fontSize: 13,
                      height: 1.45,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          GameAssetCard(
            game: Game.arknights,
            title: context.t.kbStructuredTitle,
          ),
          const SizedBox(height: 16),
          gameDataStatusAsync.when(
            data: (status) => status.installed
                ? _buildManifestGrid(context, status, theme)
                : const SizedBox.shrink(),
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),
          const SizedBox(height: 16),
          const SourceBuildCard(),
          const SizedBox(height: 16),
          const StoryVectorCard(),
          const SizedBox(height: 32),
          Text(
            context.t.kbEndfieldTitle,
            style: theme.titleFont.copyWith(fontSize: 18),
          ),
          const SizedBox(height: 8),
          Text(
            context.t.kbEndfieldDescription,
            style: theme.bodyFont.copyWith(
              color: theme.textSecondary,
              fontSize: 13,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 12),
          GameAssetCard(
            game: Game.endfield,
            title: context.t.kbEndfieldTitle,
          ),
        ],
      ),
    );
  }




  Widget _buildManifestGrid(
    BuildContext context,
    GameDataInstallStatus status,
    AppThemeTokens theme,
  ) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _statTile(context, context.t.kbStatEntities, status.entityCount ?? '-',
            Icons.account_tree_sharp, theme,),
        _statTile(context, context.t.kbStatRecords, status.recordCount ?? '-',
            Icons.dataset_sharp, theme,),
        _statTile(context, context.t.kbStatChunks, status.chunkCount ?? '-',
            Icons.article_sharp, theme,),
        _statTile(
          context,
          context.t.kbStatSourceCommit,
          shortCommit(status.sourceCommit),
          Icons.commit_sharp,
          theme,
        ),
      ],
    );
  }

  Widget _statTile(BuildContext context, String label, String value,
      IconData icon, AppThemeTokens theme,) {
    return SizedBox(
      width: (MediaQuery.of(context).size.width - 56) / 2,
      child: ThemeAwareCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: theme.accentPrimary, size: 20),
            const SizedBox(height: 8),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.titleFont.copyWith(fontSize: 24, height: 1.1),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: theme.bodyFont.copyWith(
                color: theme.textSecondary,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
