import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/gamedata/build/update_report.dart' show entryTypeLabel;
import '../../core/gamedata/gamedata_build_provider.dart';
import '../../core/gamedata/gamedata_provider.dart';
import '../../shared/l10n/l10n.dart';
import '../../shared/providers/settings_provider.dart';
import '../../shared/providers/theme_provider.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/ef_widgets.dart';
import '../../shared/widgets/theme_aware_card.dart';
import 'kb_common.dart';

/// Updating the Arknights knowledge base from the upstream GameData
/// repository (the official asset comes with the app's releases and lags
/// behind the game): check for updates, update, the progress and the
/// report, and — folded — the optional GitHub token.
///
/// 0.14: an update that can only be a complete rebuild over a database with
/// vectors asks first (the new database has none).
class SourceBuildCard extends ConsumerStatefulWidget {
  const SourceBuildCard({super.key});

  @override
  ConsumerState<SourceBuildCard> createState() => _SourceBuildCardState();
}

class _SourceBuildCardState extends ConsumerState<SourceBuildCard> {
  final TextEditingController _tokenController = TextEditingController();
  bool _tokenLoaded = false;
  bool _showToken = false;

  @override
  void dispose() {
    _tokenController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider);
    // Fill the token field once from secure storage (async, outside build).
    ref.listen(githubTokenProvider, (previous, next) {
      final token = next.valueOrNull;
      if (!_tokenLoaded && token != null) {
        _tokenLoaded = true;
        _tokenController.text = token;
      }
    });
    final build = ref.watch(gameDataBuildProvider);
    // The official asset of this build is that very commit and is offered
    // above: it comes before an update run here (it has every vector).
    final asset = ref.watch(gameDataInstallStatusProvider).valueOrNull;
    final officialHasIt = asset != null &&
        asset.updateAvailable &&
        build.latestCommit != null &&
        asset.releaseAssetCommit == build.latestCommit;
    return ThemeAwareCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          KbCardHeader(
            icon: Icons.sync_sharp,
            title: context.t.kbBuildSectionTitle,
            stamp: build.busy
                ? StateStamp(context.t.kbBuildFromSource, kind: StampKind.pending)
                : null,
          ),
          const SizedBox(height: 8),
          kbNote(context.t.kbBuildSectionDesc, theme, theme.textSecondary),
          const SizedBox(height: 10),
          if (build.latestCommit != null)
            FactsRow([
              '${context.t.kbBuildLatestCommit} ${shortCommit(build.latestCommit)}',
              if (build.installedCommit != null)
                '${context.t.kbBuildInstalledCommit} ${shortCommit(build.installedCommit)}',
            ]),
          if (build.phase == GameDataBuildPhase.idle &&
              build.changedFileCount == -1) ...[
            const SizedBox(height: 8),
            kbFlag(context.t.kbBuildTooManyChanges, theme),
          ] else if (build.phase == GameDataBuildPhase.idle &&
              build.noRelevantChanges) ...[
            const SizedBox(height: 8),
            kbNote(context.t.kbBuildNoChanges, theme, theme.accentText),
          ] else if (build.phase == GameDataBuildPhase.idle &&
              build.changeSummary != null &&
              !build.changeSummary!.isEmpty) ...[
            const SizedBox(height: 8),
            kbNote(
              context.t.kbBuildChangeSummary(
                build.changeSummary!.storyFiles,
                build.changeSummary!.tables.length,
                build.changeSummary!.levelFiles,
              ),
              theme,
              theme.accentText,
            ),
          ],
          if (officialHasIt && !build.busy) ...[
            const SizedBox(height: 8),
            kbNote(context.t.kbBuildOfficialHasIt, theme, theme.accentText),
          ],
          if (build.confirmFull && !build.busy) ...[
            const SizedBox(height: 8),
            kbFlag(context.t.kbBuildFullConfirm, theme),
            const SizedBox(height: 6),
            AppButton(
              context.t.kbBuildFullConfirmButton,
              key: const Key('kb-build-full-confirm'),
              kind: ButtonKind.danger,
              onPressed: () =>
                  ref.read(gameDataBuildProvider.notifier).buildFromSource(
                        githubToken: _currentGithubToken(),
                        allowFull: true,
                      ),
            ),
          ],
          if (build.phase == GameDataBuildPhase.done) ...[
            const SizedBox(height: 8),
            Text(
              build.incremental
                  ? context.t.kbBuildIncrementalDone
                  : context.t.kbBuildFullDone,
              style: theme.heading(14),
            ),
            if (build.report != null) ..._buildReport(context, build, theme),
          ],
          if (build.error != null) ...[
            const SizedBox(height: 10),
            NoticeBox('${context.t.kbBuildError}: ${build.error}'),
          ],
          if (build.busy) ...[
            const SizedBox(height: 14),
            SegmentProgress(
              label: _buildStageLabel(context, build),
              value: build.total > 0
                  ? (build.done / build.total).clamp(0.0, 1.0)
                  : null,
            ),
            if (build.total > 0) ...[
              const SizedBox(height: 4),
              Text('${build.done} / ${build.total}', style: theme.field()),
            ],
          ],
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: build.busy
                    ? null
                    : () => ref
                        .read(gameDataBuildProvider.notifier)
                        .checkForUpdates(githubToken: _currentGithubToken()),
                icon: const Icon(Icons.manage_search_sharp, size: 18),
                label: Text(context.t.kbBuildCheckUpdates),
              ),
              if (build.busy)
                OutlinedButton.icon(
                  onPressed: () =>
                      ref.read(gameDataBuildProvider.notifier).cancel(),
                  icon: const Icon(Icons.close_sharp, size: 18),
                  label: Text(context.t.kbBuildCancel),
                )
              else
                ElevatedButton.icon(
                  key: const Key('kb-build-start'),
                  // Nothing to pull when the installed database is known to
                  // be at the latest commit ("检查更新" looks again).
                  onPressed: build.upToDate || officialHasIt
                      ? null
                      : () => ref
                          .read(gameDataBuildProvider.notifier)
                          .buildFromSource(githubToken: _currentGithubToken()),
                  icon: const Icon(Icons.sync_sharp, size: 18),
                  label: Text(context.t.kbBuildFromSource),
                ),
            ],
          ),
          const SizedBox(height: 8),
          _buildGithubTokenSection(context, theme),
        ],
      ),
    );
  }

  /// What the last incremental update changed.
  List<Widget> _buildReport(
    BuildContext context,
    GameDataBuildUiState build,
    AppThemeTokens theme,
  ) {
    final report = build.report!;
    final entries = (report.entryDelta.entries.toList()
          ..sort((a, b) => b.value.abs().compareTo(a.value.abs())))
        .take(6)
        .map(
          (e) => '${entryTypeLabel(e.key)} ${e.value >= 0 ? '+' : ''}${e.value}',
        )
        .join('，');
    return [
      const SizedBox(height: 10),
      Text(context.t.kbBuildReportTitle, style: theme.heading(14)),
      const SizedBox(height: 4),
      kbNote(
        context.t.kbBuildReportStories(
          report.storyAdded,
          report.storyChanged,
          report.storyRemoved,
        ),
        theme,
        theme.textSecondary,
      ),
      if (entries.isNotEmpty)
        kbNote(
          context.t.kbBuildReportEntries(entries),
          theme,
          theme.textSecondary,
        ),
      if (report.newCollections.isNotEmpty)
        kbNote(
          context.t.kbBuildReportNew(report.newCollections.take(8).join('、')),
          theme,
          theme.textSecondary,
        ),
      if (report.vectorsDropped > 0)
        kbNote(
          context.t.kbBuildReportVectors(report.vectorsDropped),
          theme,
          theme.accentText,
        ),
    ];
  }

  /// Optional GitHub Personal Access Token section: raises the GitHub API
  /// quota from 60 to 5000 requests/hour, avoiding rate-limit failures when
  /// pulling GameData source. Stored in OS secure storage.
  Widget _buildGithubTokenSection(
    BuildContext context,
    AppThemeTokens theme,
  ) {
    final tokenAsync = ref.watch(githubTokenProvider);
    final hasToken = tokenAsync.valueOrNull?.isNotEmpty ?? false;
    // Folded: most updates need no token.
    final header = PressRow(
      key: const Key('kb-build-token-toggle'),
      onTap: () => setState(() => _showToken = !_showToken),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 13),
        child: Row(
          children: [
            Icon(
              _showToken ? Icons.expand_more_sharp : Icons.chevron_right_sharp,
              size: 18,
              color: theme.textSecondary,
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(context.t.kbBuildTokenTitle, style: theme.heading(15)),
            ),
            if (hasToken)
              StateStamp(context.t.kbBuildTokenSetHint),
          ],
        ),
      ),
    );
    if (!_showToken) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [Divider(color: theme.divider, height: 1), header],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Divider(color: theme.divider, height: 1),
        header,
        kbNote(context.t.kbBuildTokenDesc, theme, theme.textSecondary),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _tokenController,
                // Visible, but the keyboard must not learn or autocorrect it.
                keyboardType: TextInputType.visiblePassword,
                autocorrect: false,
                enableSuggestions: false,
                style: theme.field(color: theme.textPrimary, size: 14),
                decoration: InputDecoration(
                  labelText: context.t.kbBuildTokenTitle,
                  hintText: context.t.kbBuildTokenPlaceholder,
                ),
              ),
            ),
            const SizedBox(width: 6),
            AppButton(
              context.t.kbBuildTokenSave,
              kind: ButtonKind.go,
              onPressed: _saveGithubToken,
            ),
          ],
        ),
        
      ],
    );
  }

  String? _currentGithubToken() {
    final text = _tokenController.text.trim();
    if (text.isNotEmpty) return text;
    return ref.read(githubTokenProvider).valueOrNull;
  }

  Future<void> _saveGithubToken() async {
    final token = _tokenController.text.trim();
    await ref.read(settingsServiceProvider).saveGithubToken(token);
    ref.invalidate(githubTokenProvider);
    _tokenLoaded = false;
    if (!mounted) return;
    showToast(
      context,
      token.isEmpty
              ? context.t.kbBuildTokenCleared
              : context.t.kbBuildTokenSaved,
    );
  }

  String _buildStageLabel(
    BuildContext context,
    GameDataBuildUiState build,
  ) {
    switch (build.phase) {
      case GameDataBuildPhase.checking:
        return context.t.kbBuildChecking;
      case GameDataBuildPhase.downloading:
        if (build.stage == 'zip') return context.t.kbBuildDownloadingZip;
        if (build.stage == 'context') {
          return context.t.kbBuildDownloadingContext;
        }
        return context.t.kbBuildDownloadingChanges;
      case GameDataBuildPhase.extracting:
        return context.t.kbBuildExtracting;
      case GameDataBuildPhase.swapping:
        return context.t.kbBuildSwapping;
      case GameDataBuildPhase.building:
        switch (build.stage) {
          case 'copy':
            return context.t.kbBuildStageCopy;
          case 'incremental':
            return context.t.kbBuildStageIncremental;
          case 'profiles':
            return context.t.kbBuildStageProfiles;
          case 'voices':
            return context.t.kbBuildStageVoices;
          case 'structured':
            return context.t.kbBuildStageStructured;
          case 'stories':
            return context.t.kbBuildStageStories;
          case 'compact':
            return context.t.kbBuildStageCompact;
          case 'start':
            return context.t.kbBuildStageStart;
          default:
            return build.stage;
        }
      case GameDataBuildPhase.idle:
      case GameDataBuildPhase.done:
        return '';
    }
  }
}
