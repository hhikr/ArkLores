import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/l10n/l10n.dart';
import '../../shared/providers/theme_provider.dart';
import '../../shared/widgets/theme_aware_card.dart';

/// Materials tab.
///
/// User-imported material indexing is paused while v0.4.5 stabilizes on the
/// structured Chinese GameData knowledge base.
class MaterialsPage extends ConsumerWidget {
  const MaterialsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);

    return Scaffold(
      backgroundColor: theme.bgPrimary,
      body: Padding(
        padding: const EdgeInsets.fromLTRB(16, 48, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.menu_book_rounded, color: theme.warning, size: 28),
                const SizedBox(width: 10),
                Text(
                  context.t.materialsTitle,
                  style: theme.titleFont.copyWith(fontSize: 22),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ThemeAwareCard(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.pause_circle_outline_rounded,
                      color: theme.warning, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '用户资料导入暂未启用',
                          style: theme.titleFont.copyWith(fontSize: 16),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '旧版 PDF/TXT 导入链路已暂停。v0.4.5 当前 Agent 只使用 GameData 结构化知识库、FTS 和精确匹配。',
                          style: theme.bodyFont.copyWith(
                            color: theme.textSecondary,
                            fontSize: 13,
                            height: 1.45,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
