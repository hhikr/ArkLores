import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/l10n/l10n.dart';
import '../../shared/providers/settings_provider.dart';
import '../../shared/providers/theme_provider.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/ef_widgets.dart';
import '../../shared/widgets/page_frame.dart';
import 'settings_service.dart';

/// The Wiki sites shown on the Wiki tab: add, edit, delete, reset. Deleting
/// and resetting ask first.
class WikiSourcesSettingsPage extends ConsumerWidget {
  const WikiSourcesSettingsPage({super.key});

  Future<void> _resetSites(BuildContext context, WidgetRef ref) async {
    final ok = await confirmAction(
      context,
      title: context.t.wikiSourcesReset,
      message: context.t.wikiSourcesResetConfirm,
      confirm: context.t.wikiSourcesReset,
      cancel: context.t.wikiSourcesCancel,
      danger: true,
    );
    if (!ok) return;
    await ref.read(settingsServiceProvider).resetWikiSites();
    // The list reads the sites again.
    ref.read(wikiSourcesRevisionProvider.notifier).state++;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PageScaffold(
      title: context.t.settingsWikiSources,
      scrollUnder: true,
      actions: [
        SquareIconButton(
          tooltip: context.t.wikiSourcesReset,
          icon: Icons.restore_sharp,
          onPressed: () => _resetSites(context, ref),
        ),
      ],
      body: ListView(
        padding: pagePadding(context, const EdgeInsets.fromLTRB(16, 16, 16, 32)),
        children: const [WikiSourcesList()],
      ),
    );
  }
}

/// The saved Wiki sites as rows (name, address, edit, delete) and a button
/// that adds one; every change is saved at once. On the settings page and
/// in the onboarding.
class WikiSourcesList extends ConsumerStatefulWidget {
  const WikiSourcesList({super.key});

  @override
  ConsumerState<WikiSourcesList> createState() => _WikiSourcesListState();
}

class _WikiSourcesListState extends ConsumerState<WikiSourcesList> {
  var _sites = <WikiSiteConfig>[];
  var _loading = true;

  @override
  void initState() {
    super.initState();
    _loadSites();
  }

  Future<void> _loadSites() async {
    final sites = await ref.read(settingsServiceProvider).loadWikiSites();
    if (!mounted) return;
    setState(() {
      _sites = sites;
      _loading = false;
    });
  }

  Future<void> _saveSites(List<WikiSiteConfig> sites) async {
    setState(() => _sites = sites);
    await ref.read(settingsServiceProvider).saveWikiSites(sites);
    ref.read(wikiSourcesRevisionProvider.notifier).state++;
  }

  Future<void> _editSite({WikiSiteConfig? site, int? index}) async {
    final result = await showAppDialog<WikiSiteConfig>(
      context,
      (context) => _WikiSourceDialog(site: site),
    );
    if (result == null) return;

    final next = [..._sites];
    if (index == null) {
      next.add(result);
    } else {
      next[index] = result;
    }
    await _saveSites(next);
  }

  Future<void> _deleteSite(int index) async {
    final site = _sites[index];
    if (site.builtIn) return;
    final ok = await confirmAction(
      context,
      title: '${context.t.wikiSourcesDelete} ${site.label}',
      confirm: context.t.wikiSourcesDelete,
      cancel: context.t.wikiSourcesCancel,
      danger: true,
    );
    if (!ok) return;
    final next = [..._sites]..removeAt(index);
    await _saveSites(next);
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider);
    // Reset on the settings page (or a change elsewhere): read them again.
    ref.listen<int>(wikiSourcesRevisionProvider, (_, __) => _loadSites());
    return _loading
          ? const LoadingView()
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (index, site) in _sites.indexed) ...[
                  Divider(height: 1, color: theme.divider),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 36,
                          child: Text(
                            (index + 1).toString().padLeft(2, '0'),
                            style: theme.field(color: theme.textMuted, size: 14),
                          ),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      site.label,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.heading(16),
                                    ),
                                  ),
                                  if (site.builtIn) ...[
                                    const SizedBox(width: 8),
                                    const Icon(Icons.lock_outline_sharp, size: 16),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                site.url,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.field(),
                              ),
                            ],
                          ),
                        ),
                        SquareIconButton(
                          tooltip: context.t.wikiSourcesEdit,
                          icon: Icons.edit_sharp,
                          onPressed: () => _editSite(site: site, index: index),
                        ),
                        if (!site.builtIn)
                          SquareIconButton(
                            tooltip: context.t.wikiSourcesDelete,
                            icon: Icons.delete_outline_sharp,
                            color: theme.danger,
                            onPressed: () => _deleteSite(index),
                          ),
                      ],
                    ),
                  ),
                ],
                Divider(height: 1, color: theme.divider),
                const SizedBox(height: 20),
                AppButton(
                  context.t.wikiSourcesAddTitle,
                  key: const ValueKey('wiki-sources-add'),
                  kind: ButtonKind.go,
                  icon: Icons.add_sharp,
                  expand: true,
                  onPressed: () => _editSite(),
                ),
              ],
            );
  }
}

class _WikiSourceDialog extends StatefulWidget {
  const _WikiSourceDialog({this.site});

  final WikiSiteConfig? site;

  @override
  State<_WikiSourceDialog> createState() => _WikiSourceDialogState();
}

class _WikiSourceDialogState extends State<_WikiSourceDialog> {
  late final TextEditingController _labelController;
  late final TextEditingController _urlController;
  late final TextEditingController _iconController;
  String? _nameError;
  String? _urlError;

  bool get _isBuiltInEndfield => widget.site?.id == 'endfield';

  @override
  void initState() {
    super.initState();
    final site = widget.site;
    _labelController = TextEditingController(text: site?.label ?? '');
    _urlController = TextEditingController(text: site?.url ?? 'https://');
    _iconController = TextEditingController(text: site?.iconUrl ?? '');
  }

  @override
  void dispose() {
    _labelController.dispose();
    _urlController.dispose();
    _iconController.dispose();
    super.dispose();
  }

  void _submit() {
    final label = _labelController.text.trim();
    final url = _urlController.text.trim();
    final iconUrl = _iconController.text.trim();
    final uri = Uri.tryParse(url);
    setState(() {
      _nameError = label.isEmpty ? context.t.wikiSourcesNameRequired : null;
      _urlError = uri == null || !uri.hasScheme || uri.host.isEmpty
          ? context.t.wikiSourcesUrlRequired
          : null;
    });
    if (_nameError != null || _urlError != null) return;
    Navigator.of(context).pop(
      WikiSiteConfig(
        id: widget.site?.id ??
            'custom_${DateTime.now().microsecondsSinceEpoch}',
        label: label,
        url: url,
        iconUrl: iconUrl.isEmpty ? null : iconUrl,
        builtIn: widget.site?.builtIn ?? false,
      ),
    );
  }

  void _selectEndfieldPreset({
    required String url,
    required String iconUrl,
  }) {
    if (_labelController.text.trim().isEmpty || _isBuiltInEndfield) {
      _labelController.text = 'Endfield Wiki';
    }
    _urlController.text = url;
    _iconController.text = iconUrl;
    setState(() {
      _nameError = null;
      _urlError = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, _) {
        final theme = ref.watch(themeProvider);
        return AppDialog(
          title: widget.site == null
              ? context.t.wikiSourcesAddTitle
              : context.t.wikiSourcesEditTitle,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _labelController,
                decoration: InputDecoration(
                  labelText: context.t.wikiSourcesNameLabel,
                  errorText: _nameError,
                ),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _urlController,
                decoration: InputDecoration(
                  labelText: 'URL',
                  errorText: _urlError,
                ),
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 12),
              Text(
                context.t.wikiSourcesEndfieldPreset,
                style: theme.ui(13, weight: 600, color: theme.textSecondary),
              ),
              Wrap(
                spacing: 8,
                children: [
                  FilterBlock(
                    label: 'Warfarin',
                    selected: _urlController.text == 'https://warfarin.wiki/cn',
                    onTap: () => _selectEndfieldPreset(
                      url: 'https://warfarin.wiki/cn',
                      iconUrl: 'https://warfarin.wiki/icon.png',
                    ),
                  ),
                  FilterBlock(
                    label: 'fz.wiki',
                    selected: _urlController.text == 'https://fz.wiki',
                    onTap: () => _selectEndfieldPreset(
                      url: 'https://fz.wiki',
                      iconUrl: 'https://fz.wiki/icon.svg',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _iconController,
                decoration: InputDecoration(
                  labelText: context.t.wikiSourcesIconUrlLabel,
                ),
                keyboardType: TextInputType.url,
              ),
            ],
          ),
          actions: [
            AppButton(
              context.t.wikiSourcesCancel,
              small: true,
              kind: ButtonKind.quiet,
              onPressed: () => Navigator.of(context).pop(),
            ),
            AppButton(
              context.t.wikiSourcesSave,
              small: true,
              kind: ButtonKind.go,
              onPressed: _submit,
            ),
          ],
        );
      },
    );
  }
}
