import 'package:flutter/material.dart';

import '../../shared/theme/app_theme.dart';

/// A short line of status text on a knowledge-base card.
Widget kbNote(String text, AppThemeTokens theme, Color color) => Text(
      text,
      style: theme.bodyFont.copyWith(color: color, fontSize: 12, height: 1.4),
    );

/// The first 7 characters of a commit hash, `-` when there is none.
String shortCommit(String? commit) {
  if (commit == null || commit.isEmpty) return '-';
  if (commit.length <= 7) return commit;
  return commit.substring(0, 7);
}
