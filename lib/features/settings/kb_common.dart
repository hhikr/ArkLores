import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/providers/theme_provider.dart';
import '../../shared/theme/app_theme.dart';

/// A short line of status text on a knowledge-base card, in [color] (the
/// accent colours are read as ink: they are not for text on light paper).
Widget kbNote(String text, AppThemeTokens theme, Color color) => Text(
      text,
      style: theme.text(
        13.5,
        color: color == theme.accentText || color == theme.accentPrimary
            ? theme.textPrimary
            : color,
        height: 1.5,
      ),
    );

/// A line that needs a look (a warning, an error) on a knowledge-base card:
/// an accent flag in front, the text in ink. Errors are not red: red is for
/// deleting.
Widget kbFlag(String text, AppThemeTokens theme) => Semantics(
      liveRegion: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 5, right: 8),
            width: 10,
            height: 10,
            color: theme.accentPrimary,
          ),
          Expanded(
            child: Text(
              text,
              style: theme.text(13.5, color: theme.textPrimary, height: 1.5),
            ),
          ),
        ],
      ),
    );

/// The head of a knowledge-base card: an icon, the title in bold Chinese,
/// and a state stamp on the right.
class KbCardHeader extends ConsumerWidget {
  const KbCardHeader({
    super.key,
    required this.icon,
    required this.title,
    this.stamp,
  });

  final IconData icon;
  final String title;
  final Widget? stamp;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    return Row(
      children: [
        Icon(icon, color: theme.textSecondary, size: 22),
        const SizedBox(width: 10),
        Expanded(child: Text(title, style: theme.heading(17))),
        if (stamp != null) stamp!,
      ],
    );
  }
}

enum StampKind {
  /// In effect: a solid ink frame.
  live,

  /// Working in the background, or not yet in effect: a dashed frame.
  pending,

  /// Look at this: an accent block.
  alert,
}

/// A state stamp: solid frame = in effect, dashed = in the background,
/// accent block = needs a look.
class StateStamp extends ConsumerWidget {
  const StateStamp(this.text, {super.key, this.kind = StampKind.live});

  final String text;
  final StampKind kind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    final alert = kind == StampKind.alert;
    return CustomPaint(
      painter: kind == StampKind.pending ? _DashedFrame(theme.textSecondary) : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: kind == StampKind.live
            ? BoxDecoration(border: Border.all(color: theme.textPrimary))
            : alert
                ? BoxDecoration(color: theme.accentPrimary)
                : null,
        child: Text(
          text,
          style: theme.ui(
            13,
            weight: 600,
            color: alert ? theme.onAccent : theme.textPrimary,
          ),
        ),
      ),
    );
  }
}

class _DashedFrame extends CustomPainter {
  const _DashedFrame(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = color;
    void dash(Offset a, Offset b) {
      final len = (b - a).distance;
      final dir = (b - a) / len;
      for (var d = 0.0; d < len; d += 6) {
        canvas.drawLine(a + dir * d, a + dir * (d + 3).clamp(0, len), p);
      }
    }

    final r = (Offset.zero & size).deflate(0.5);
    dash(r.topLeft, r.topRight);
    dash(r.topRight, r.bottomRight);
    dash(r.bottomRight, r.bottomLeft);
    dash(r.bottomLeft, r.topLeft);
  }

  @override
  bool shouldRepaint(_DashedFrame old) => old.color != color;
}

/// The first 7 characters of a commit hash, `-` when there is none.
String shortCommit(String? commit) {
  if (commit == null || commit.isEmpty) return '-';
  if (commit.length <= 7) return commit;
  return commit.substring(0, 7);
}
