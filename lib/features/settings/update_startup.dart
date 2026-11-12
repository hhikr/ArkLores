import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/gamedata/gamedata_channel.dart';
import '../../core/gamedata/gamedata_installer.dart';
import '../../core/gamedata/gamedata_provider.dart';
import '../../core/gamedata/story_art_pack_provider.dart';
import '../../core/update/app_update_provider.dart';
import '../../shared/l10n/l10n.dart';
import '../../shared/providers/theme_provider.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/ef_widgets.dart';
import '../../shared/widgets/smooth_page_route.dart';
import 'settings_sections.dart';

bool _isNews(GameDataInstallStatus status) =>
    status.updateReason != null &&
    status.updateReason != GameDataUpdateReason.sameDataOfficial;

/// Checks after the main screen opens and whenever the app comes back to the
/// front; never starts a download. The app's own update follows its setting;
/// new knowledge bases and art are asked about at once: they come about
/// weekly and the channel is the only place to hear of them.
class UpdateStartup extends ConsumerStatefulWidget {
  const UpdateStartup({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<UpdateStartup> createState() => _UpdateStartupState();
}

class _UpdateStartupState extends ConsumerState<UpdateStartup>
    with WidgetsBindingObserver {
  bool _checkingKnowledge = false;

  /// What was asked about in this run: coming back to the app does not ask
  /// about the same files again.
  String? _asked;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_check());
      unawaited(_checkKnowledge());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    ref.invalidate(gameDataChannelProvider);
    unawaited(_checkKnowledge());
  }

  Future<void> _check() async {
    if (!mounted) return;
    final enabled = ref.read(autoUpdateCheckProvider);
    if (!enabled) return;
    try {
      final release = await ref
          .read(appUpdateProvider.notifier)
          .autoCheck(enabled: enabled);
      if (!mounted || release == null) return;
      showToast(
        context,
        context.t.updateFound(release.versionName),
        action: SnackBarAction(
          label: context.t.updateFoundOpen,
          onPressed: () => Navigator.of(context).push(
            smoothPageRoute<void>(builder: (_) => const HelpSettingsPage()),
          ),
        ),
      );
    } catch (_) {
      // A startup check must not interrupt opening the app.
    }
  }

  Future<void> _checkKnowledge() async {
    if (!mounted || _checkingKnowledge) return;
    _checkingKnowledge = true;
    try {
      await ref.read(gameDataChannelProvider.future);
      final arknights = await ref.read(gameDataInstallStatusProvider.future);
      final endfield = await ref.read(endfieldInstallStatusProvider.future);
      // Each story-art pack that is installed is checked.
      final arts = [
        for (final variant in StoryArtVariant.values)
          await ref.read(storyArtPackStatusProvider(variant).future),
      ];
      if (!mounted) return;
      // A download on its way is already the answer.
      if (ref.read(gameDataDownloadProvider).downloading ||
          ref.read(endfieldDownloadProvider).downloading ||
          arts.any((art) => art.downloading)) {
        return;
      }
      final t = context.t;
      final items = [
        if (_isNews(arknights)) t.kbUpdateFoundArknights,
        if (_isNews(endfield)) t.kbUpdateFoundEndfield,
        for (final art in arts)
          if (art.updateAvailable)
            t.kbUpdateFoundArt(
              '${(art.asset!.size / 1024 / 1024).toStringAsFixed(0)} MB',
            ),
      ];
      final what = [
        if (_isNews(arknights)) arknights.releaseAssetSha,
        if (_isNews(endfield)) endfield.releaseAssetSha,
        for (final art in arts)
          if (art.updateAvailable) art.asset!.sha256,
      ].join('/');
      if (items.isEmpty || what == _asked) return;
      _asked = what;
      await _ask(items);
    } catch (_) {
      // No network or no file: the knowledge-base page says so when opened.
    } finally {
      _checkingKnowledge = false;
    }
  }

  Future<void> _ask(List<String> items) => showAppDialog<void>(
        context,
        (dialog) {
          final theme = ProviderScope.containerOf(dialog).read(themeProvider);
          return AppDialog(
            key: const ValueKey('kb-update-found'),
            title: dialog.t.kbUpdateFoundTitle,
            message: dialog.t.kbUpdateFoundBody,
            content: _UpdateList(items: items, theme: theme),
            actions: [
              AppButton(
                dialog.t.kbUpdateFoundLater,
                small: true,
                kind: ButtonKind.quiet,
                onPressed: () => Navigator.of(dialog).pop(),
              ),
              AppButton(
                dialog.t.kbUpdateFoundOpen,
                key: const ValueKey('kb-update-found-open'),
                small: true,
                kind: ButtonKind.go,
                onPressed: () {
                  Navigator.of(dialog).pop();
                  Navigator.of(context).pushNamed('/knowledge-base');
                },
              ),
            ],
          );
        },
      );

  @override
  Widget build(BuildContext context) => widget.child;
}

class _UpdateList extends StatelessWidget {
  const _UpdateList({required this.items, required this.theme});
  final List<String> items;
  final AppThemeTokens theme;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(item, style: theme.ui(15, weight: 700)),
            ),
        ],
      );
}
