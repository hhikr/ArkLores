import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/library/portrait_provider.dart';
import '../../shared/l10n/l10n.dart';
import '../../shared/providers/theme_provider.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/ef_widgets.dart';
import '../../shared/widgets/page_frame.dart';

/// The names answers never underline: typed in here, or added by holding
/// an underlined name in an answer. Taking one off underlines it again.
class BlockedNamesPage extends ConsumerStatefulWidget {
  const BlockedNamesPage({super.key});

  @override
  ConsumerState<BlockedNamesPage> createState() => _BlockedNamesPageState();
}

class _BlockedNamesPageState extends ConsumerState<BlockedNamesPage> {
  final _input = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final name = _input.text.trim();
    if (name.isEmpty) return;
    final added = await ref.read(nameLinksProvider.notifier).block(name);
    if (!mounted) return;
    setState(() => _error = added ? null : context.t.blockedNamesDuplicate);
    if (added) _input.clear();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider);
    final blocked =
        ref.watch(nameLinksProvider).valueOrNull?.blocked ?? const <String>[];
    return PageScaffold(
      title: context.t.settingsBlockedNames,
      scrollUnder: true,
      body: ListView(
        padding: pagePadding(context, const EdgeInsets.fromLTRB(16, 4, 16, 32)),
        children: [
          Text(
            context.t.settingsBlockedNamesDesc,
            style: theme.text(14, color: theme.textSecondary, height: 1.6),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('blocked-names-input'),
                  controller: _input,
                  style: theme.text(16),
                  textInputAction: TextInputAction.done,
                  onChanged: (_) {
                    if (_error != null) setState(() => _error = null);
                  },
                  onSubmitted: (_) => _add(),
                  decoration: InputDecoration(
                    labelText: context.t.blockedNamesHint,
                    errorText: _error,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: AppButton(
                  context.t.blockedNamesAdd,
                  key: const ValueKey('blocked-names-add'),
                  kind: ButtonKind.go,
                  icon: Icons.add_sharp,
                  onPressed: _add,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (blocked.isEmpty)
            EmptyState(text: context.t.blockedNamesEmpty)
          else ...[
            Divider(height: 1, color: theme.divider),
            // The latest added first: the one just added is in sight.
            for (final name in blocked.reversed) ...[
              _NameRow(name: name, theme: theme),
              Divider(height: 1, color: theme.divider),
            ],
          ],
        ],
      ),
    );
  }
}

class _NameRow extends ConsumerWidget {
  const _NameRow({required this.name, required this.theme});

  final String name;
  final AppThemeTokens theme;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Padding(
        key: ValueKey('blocked-name-$name'),
        padding: const EdgeInsets.only(left: 8),
        child: Row(
          children: [
            Expanded(child: Text(name, style: theme.text(16))),
            SquareIconButton(
              icon: Icons.close_sharp,
              tooltip: context.t.blockedNamesRemove(name),
              color: theme.textSecondary,
              onPressed: () =>
                  ref.read(nameLinksProvider.notifier).unblock(name),
            ),
          ],
        ),
      );
}
