import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/library/portrait_provider.dart';
import '../../../shared/l10n/l10n.dart';
import '../../../shared/providers/theme_provider.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../shared/widgets/ef_widgets.dart';
import '../../library/portrait_preview.dart';

/// Asks, beside an underlined [name] held down in an answer, whether to stop
/// underlining it; yes adds it to the blocked names (every answer drops its
/// underline at once).
void showBlockNameCard(
  BuildContext context, {
  required String name,
  required Rect anchor,
}) =>
    showAnchoredCard(
      context,
      anchor: anchor,
      width: 248,
      height: 152,
      builder: (close) => _BlockNameCard(name: name, onClose: close),
    );

class _BlockNameCard extends ConsumerWidget {
  const _BlockNameCard({required this.name, required this.onClose});

  final String name;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 2, 0, 0),
      child: Column(
        key: const ValueKey('block-name-card'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.t.aiBlockNameQuestion, style: theme.heading(15)),
          const SizedBox(height: 2),
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.text(14, weight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            context.t.aiBlockNameDesc,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.text(12, color: theme.textSecondary, height: 1.4),
          ),
          const Spacer(),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              AppButton(
                context.t.aiBlockNameCancel,
                small: true,
                kind: ButtonKind.quiet,
                onPressed: onClose,
              ),
              const SizedBox(width: 6),
              AppButton(
                context.t.aiBlockNameConfirm,
                key: const ValueKey('block-name-confirm'),
                small: true,
                kind: ButtonKind.go,
                onPressed: () {
                  onClose();
                  ref.read(nameLinksProvider.notifier).block(name);
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}
