import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/l10n/l10n.dart';
import '../../shared/providers/settings_provider.dart';
import '../../shared/providers/theme_provider.dart';
import '../../shared/widgets/theme_aware_card.dart';
import 'settings_service.dart';

/// The Wiki sites shown on the Wiki tab: add, edit, delete, reset.
class WikiSourcesSettingsPage extends ConsumerStatefulWidget {
  const WikiSourcesSettingsPage({super.key});

  @override
  ConsumerState<WikiSourcesSettingsPage> createState() =>
      _WikiSourcesSettingsPageState();
}

class _WikiSourcesSettingsPageState
    extends ConsumerState<WikiSourcesSettingsPage> {
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
    await ref.read(settingsServiceProvider).saveWikiSites(sites);
    ref.read(wikiSourcesRevisionProvider.notifier).state++;
    if (!mounted) return;
    setState(() => _sites = sites);
  }

  Future<void> _resetSites() async {
    await ref.read(settingsServiceProvider).resetWikiSites();
    ref.read(wikiSourcesRevisionProvider.notifier).state++;
    await _loadSites();
  }

  Future<void> _editSite({WikiSiteConfig? site, int? index}) async {
    final result = await showDialog<WikiSiteConfig>(
      context: context,
      builder: (context) => _WikiSourceDialog(site: site),
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
    final next = [..._sites]..removeAt(index);
    await _saveSites(next);
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider);
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: theme.bgSecondary,
        title: Text(context.t.settingsWikiSources,
            style: theme.titleFont.copyWith(fontSize: 18),),
        iconTheme: IconThemeData(color: theme.textPrimary),
        actions: [
          IconButton(
            tooltip: context.t.wikiSourcesReset,
            icon: const Icon(Icons.restore_rounded),
            onPressed: _resetSites,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: theme.accentPrimary,
        foregroundColor: theme.bgPrimary,
        onPressed: () => _editSite(),
        child: const Icon(Icons.add_rounded),
      ),
      body: _loading
          ? Center(
              child: CircularProgressIndicator(color: theme.accentPrimary),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              itemBuilder: (context, index) {
                final site = _sites[index];
                return ThemeAwareCard(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: theme.surfaceElevated,
                          border: Border.all(color: theme.divider),
                        ),
                        child: Icon(
                          site.builtIn
                              ? Icons.public_rounded
                              : Icons.travel_explore_rounded,
                          color: theme.accentPrimary,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              site.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.titleFont.copyWith(fontSize: 16),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              site.url,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.bodyFont.copyWith(
                                color: theme.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: context.t.wikiSourcesEdit,
                        icon: const Icon(Icons.edit_rounded),
                        color: theme.textSecondary,
                        onPressed: () => _editSite(site: site, index: index),
                      ),
                      if (!site.builtIn)
                        IconButton(
                          tooltip: context.t.wikiSourcesDelete,
                          icon: const Icon(Icons.delete_outline_rounded),
                          color: theme.danger,
                          onPressed: () => _deleteSite(index),
                        ),
                    ],
                  ),
                );
              },
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemCount: _sites.length,
            ),
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
  String? _error;

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
    if (label.isEmpty) {
      setState(() => _error = context.t.wikiSourcesNameRequired);
      return;
    }
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      setState(() => _error = context.t.wikiSourcesUrlRequired);
      return;
    }
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
    setState(() => _error = null);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(widget.site == null
          ? context.t.wikiSourcesAddTitle
          : context.t.wikiSourcesEditTitle,),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _labelController,
              decoration: InputDecoration(labelText: context.t.wikiSourcesNameLabel),
              textInputAction: TextInputAction.next,
            ),
            TextField(
              controller: _urlController,
              decoration: const InputDecoration(labelText: 'URL'),
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                context.t.wikiSourcesEndfieldPreset,
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ActionChip(
                    avatar: const Icon(Icons.public_rounded, size: 16),
                    label: const Text('Warfarin'),
                    onPressed: () => _selectEndfieldPreset(
                      url: 'https://warfarin.wiki/cn',
                      iconUrl: 'https://warfarin.wiki/icon.png',
                    ),
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.public_rounded, size: 16),
                    label: const Text('fz.wiki'),
                    onPressed: () => _selectEndfieldPreset(
                      url: 'https://fz.wiki',
                      iconUrl: 'https://fz.wiki/icon.svg',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _iconController,
              decoration: InputDecoration(
                labelText: context.t.wikiSourcesIconUrlLabel,
              ),
              keyboardType: TextInputType.url,
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _error!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.t.wikiSourcesCancel),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(context.t.wikiSourcesSave),
        ),
      ],
    );
  }
}
