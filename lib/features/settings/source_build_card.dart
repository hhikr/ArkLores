import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/gamedata/build/update_report.dart' show entryTypeLabel;
import '../../core/gamedata/gamedata_build_provider.dart';
import '../../shared/l10n/l10n.dart';
import '../../shared/providers/settings_provider.dart';
import '../../shared/providers/theme_provider.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/theme_aware_card.dart';
import 'kb_common.dart';

/// Building or updating the knowledge base from the upstream GameData
/// repository: check for updates, build, the progress and the report, and
/// the optional GitHub token.
class SourceBuildCard extends ConsumerStatefulWidget {
  const SourceBuildCard({super.key});

  @override
  ConsumerState<SourceBuildCard> createState() => _SourceBuildCardState();
}

class _SourceBuildCardState extends ConsumerState<SourceBuildCard> {
  final TextEditingController _tokenController = TextEditingController();
  bool _tokenLoaded = false;

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
    return ThemeAwareCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.sync_sharp, color: theme.accentPrimary, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.t.kbBuildSectionTitle,
                      style: theme.titleFont.copyWith(fontSize: 15),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      context.t.kbBuildSectionDesc,
                      style: theme.bodyFont.copyWith(
                        color: theme.textSecondary,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (build.latestCommit != null)
            Text(
              '${context.t.kbBuildLatestCommit}: ${shortCommit(build.latestCommit)}'
              '${build.installedCommit != null ? ' (${context.t.kbBuildInstalledCommit}: ${shortCommit(build.installedCommit)})' : ''}',
              style: theme.bodyFont.copyWith(
                color: theme.textSecondary,
                fontSize: 12,
              ),
            ),
          if (build.phase == GameDataBuildPhase.idle &&
              build.changedFileCount == -1) ...[
            const SizedBox(height: 8),
            kbNote(context.t.kbBuildTooManyChanges, theme, theme.warning),
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
          if (build.phase == GameDataBuildPhase.done) ...[
            const SizedBox(height: 8),
            Text(
              build.incremental
                  ? context.t.kbBuildIncrementalDone
                  : context.t.kbBuildFullDone,
              style: theme.bodyFont.copyWith(
                color: theme.accentPrimary,
                fontSize: 12,
              ),
            ),
            if (build.report != null) ..._buildReport(context, build, theme),
          ],
          if (build.error != null) ...[
            const SizedBox(height: 8),
            Text(
              '${context.t.kbBuildError}: ${build.error}',
              style: theme.bodyFont.copyWith(
                color: theme.danger,
                fontSize: 12,
              ),
            ),
          ],
          if (build.busy) ...[
            const SizedBox(height: 12),
            Text(
              _buildStageLabel(context, build),
              style: theme.bodyFont.copyWith(
                color: theme.textPrimary,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: build.total > 0
                  ? (build.done / build.total).clamp(0.0, 1.0)
                  : null,
              backgroundColor: theme.divider,
              valueColor: AlwaysStoppedAnimation(theme.accentPrimary),
              minHeight: 6,
            ),
            if (build.total > 0) ...[
              const SizedBox(height: 4),
              Text(
                '${build.done} / ${build.total}',
                style: theme.bodyFont.copyWith(
                  color: theme.textSecondary,
                  fontSize: 11,
                ),
              ),
            ],
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: build.busy
                    ? null
                    : () => ref
                        .read(gameDataBuildProvider.notifier)
                        .checkForUpdates(githubToken: _currentGithubToken()),
                icon: const Icon(Icons.manage_search_sharp, size: 18),
                label: Text(context.t.kbBuildCheckUpdates),
                style: OutlinedButton.styleFrom(
                  foregroundColor: theme.accentPrimary,
                  side: BorderSide(color: theme.divider),
                ),
              ),
              const SizedBox(width: 8),
              if (build.busy)
                OutlinedButton.icon(
                  onPressed: () =>
                      ref.read(gameDataBuildProvider.notifier).cancel(),
                  icon: const Icon(Icons.close_sharp, size: 18),
                  label: Text(context.t.kbBuildCancel),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: theme.danger,
                    side: BorderSide(color: theme.divider),
                  ),
                )
              else
                ElevatedButton.icon(
                  onPressed: () => ref
                      .read(gameDataBuildProvider.notifier)
                      .buildFromSource(githubToken: _currentGithubToken()),
                  icon: const Icon(Icons.build_sharp, size: 18),
                  label: Text(context.t.kbBuildFromSource),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.accentPrimary,
                    foregroundColor: theme.bgPrimary,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
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
      Text(
        context.t.kbBuildReportTitle,
        style: theme.titleFont.copyWith(fontSize: 13),
      ),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Divider(color: theme.divider, height: 1),
        const SizedBox(height: 12),
        Text(
          context.t.kbBuildTokenTitle,
          style: theme.titleFont.copyWith(fontSize: 13),
        ),
        const SizedBox(height: 2),
        Text(
          context.t.kbBuildTokenDesc,
          style: theme.bodyFont.copyWith(
            color: theme.textSecondary,
            fontSize: 11,
            height: 1.4,
          ),
        ),
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
                style: theme.bodyFont.copyWith(color: theme.textPrimary),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: context.t.kbBuildTokenPlaceholder,
                  hintStyle: theme.bodyFont.copyWith(
                    color: theme.textSecondary,
                    fontSize: 12,
                  ),
                  filled: true,
                  fillColor: theme.bgPrimary,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.zero,
                    borderSide: BorderSide(color: theme.divider),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.zero,
                    borderSide: BorderSide(color: theme.divider),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            FilledButton(
              onPressed: _saveGithubToken,
              style: FilledButton.styleFrom(
                backgroundColor: theme.accentPrimary,
                foregroundColor: theme.bgPrimary,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              child: Text(
                context.t.kbBuildTokenSave,
                style: theme.titleFont.copyWith(fontSize: 12),
              ),
            ),
          ],
        ),
        if (tokenAsync.valueOrNull?.isNotEmpty ?? false) ...[
          const SizedBox(height: 4),
          Text(
            context.t.kbBuildTokenSetHint,
            style: theme.bodyFont.copyWith(
              color: theme.accentPrimary,
              fontSize: 11,
            ),
          ),
        ],
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          token.isEmpty
              ? context.t.kbBuildTokenCleared
              : context.t.kbBuildTokenSaved,
        ),
      ),
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
          case 'coverage':
            return context.t.kbBuildStageCoverage;
          case 'coverage_speakers':
            return context.t.kbBuildStageCoverageSpeakers;
          case 'coverage_trie':
            return context.t.kbBuildStageCoverageTrie;
          case 'coverage_scan':
            return context.t.kbBuildStageCoverageScan;
          case 'coverage_rare':
            return context.t.kbBuildStageCoverageRare;
          case 'coverage_profiles':
            return context.t.kbBuildStageCoverageProfiles;
          case 'fts':
            return context.t.kbBuildStageFts;
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
