import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/agent/agent_provider.dart';
import '../../../core/agent/question_router.dart';
import '../../../shared/l10n/l10n.dart';
import '../../../shared/providers/theme_provider.dart';
import '../../../shared/theme/app_theme.dart';

/// R17d: the Ask mode button ("自动 ▾") in the input row. The four modes
/// slide up from it in a rounded panel drawn in the overlay — no route is
/// pushed and nothing takes focus, so the text field keeps the keyboard up.
/// Closes on a choice, a tap outside it or the back gesture.
class AskModePicker extends ConsumerStatefulWidget {
  const AskModePicker({super.key});

  @override
  ConsumerState<AskModePicker> createState() => _AskModePickerState();
}

class _AskModePickerState extends ConsumerState<AskModePicker>
    with SingleTickerProviderStateMixin {
  final OverlayPortalController _portal = OverlayPortalController();
  final LayerLink _link = LayerLink();
  final Object _tapGroup = Object();
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
    reverseDuration: const Duration(milliseconds: 160),
  );
  late final Animation<double> _curve = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );

  /// Open, or opening; false while it closes.
  bool _open = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _show() {
    setState(() => _open = true);
    _portal.show();
    _controller.forward();
  }

  Future<void> _hide() async {
    if (!_open) return;
    setState(() => _open = false);
    await _controller.reverse();
    if (mounted && !_open) _portal.hide();
  }

  void _choose(AiMode mode) {
    ref.read(aiModeProvider.notifier).state = mode;
    _hide();
  }

  String _label(AiMode mode) => switch (mode) {
        AiMode.auto => context.t.aiModeAuto,
        AiMode.summarize => context.t.aiModeSummarize,
        AiMode.verify => context.t.aiModeVerify,
        AiMode.investigate => context.t.aiModeInvestigate,
      };

  String _description(AiMode mode) => switch (mode) {
        AiMode.auto => context.t.aiModeAutoDesc,
        AiMode.summarize => context.t.aiModeSummarizeDesc,
        AiMode.verify => context.t.aiModeVerifyDesc,
        AiMode.investigate => context.t.aiModeInvestigateDesc,
      };

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider);
    final mode = ref.watch(aiModeProvider);
    return PopScope(
      canPop: !_open,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _hide();
      },
      child: OverlayPortal(
        controller: _portal,
        overlayChildBuilder: (overlayContext) =>
            _buildPanel(overlayContext, theme, mode),
        child: CompositedTransformTarget(
          link: _link,
          child: TapRegion(
            groupId: _tapGroup,
            child: _buildButton(theme, mode),
          ),
        ),
      ),
    );
  }

  Widget _buildButton(AppThemeTokens theme, AiMode mode) => Tooltip(
        message: context.t.aiModeMenuTooltip,
        child: InkWell(
          key: const ValueKey('ask-mode-menu'),
          canRequestFocus: false,
          borderRadius: BorderRadius.circular(16),
          onTap: () => _open ? _hide() : _show(),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: theme.accentPrimary.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: theme.accentText.withValues(alpha: 0.4),
                width: 0.5,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _label(mode),
                  style: theme.bodyFont.copyWith(
                    color: theme.accentText,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                AnimatedRotation(
                  turns: _open ? 0.5 : 0,
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  child: Icon(
                    Icons.arrow_drop_up_rounded,
                    size: 18,
                    color: theme.accentText,
                  ),
                ),
              ],
            ),
          ),
        ),
      );

  Widget _buildPanel(
    BuildContext overlayContext,
    AppThemeTokens theme,
    AiMode mode,
  ) {
    final media = MediaQuery.of(overlayContext);
    final button = context.findRenderObject() as RenderBox?;
    final buttonTop = button != null && button.attached
        ? button.localToGlobal(Offset.zero).dy
        : media.size.height / 2;
    // Room above the button (the keyboard only takes space below it).
    final maxHeight =
        math.max(120.0, buttonTop - media.padding.top - 16);
    final width = math.min(320.0, media.size.width - 32);
    return Positioned(
      left: 0,
      top: 0,
      width: width,
      child: CompositedTransformFollower(
        link: _link,
        showWhenUnlinked: false,
        targetAnchor: Alignment.topLeft,
        followerAnchor: Alignment.bottomLeft,
        offset: const Offset(0, -8),
        child: TapRegion(
          groupId: _tapGroup,
          onTapOutside: (_) => _hide(),
          child: ExcludeFocus(
            child: FadeTransition(
              opacity: _curve,
              child: SlideTransition(
                position: Tween(
                  begin: const Offset(0, 0.06),
                  end: Offset.zero,
                ).animate(_curve),
                child: ScaleTransition(
                  alignment: Alignment.bottomLeft,
                  scale: Tween(begin: 0.96, end: 1.0).animate(_curve),
                  child: Material(
                    key: const ValueKey('ask-mode-panel'),
                    color: theme.cardSurface,
                    elevation: 8,
                    shadowColor: Colors.black.withValues(alpha: 0.3),
                    clipBehavior: Clip.antiAlias,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                      side: BorderSide(color: theme.divider, width: 0.5),
                    ),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxHeight: maxHeight),
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(6),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (final candidate in AiMode.values)
                              _buildOption(theme, candidate, candidate == mode),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOption(AppThemeTokens theme, AiMode mode, bool selected) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Ink(
          decoration: BoxDecoration(
            color: selected
                ? theme.accentPrimary.withValues(alpha: 0.16)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: InkWell(
            key: ValueKey('ask-mode-${mode.name}'),
            borderRadius: BorderRadius.circular(12),
            onTap: () => _choose(mode),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _label(mode),
                          style: theme.bodyFont.copyWith(
                            color: selected
                                ? theme.accentText
                                : theme.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _description(mode),
                          style: theme.bodyFont.copyWith(
                            color: theme.textSecondary,
                            fontSize: 11,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (selected) ...[
                    const SizedBox(width: 8),
                    Icon(
                      Icons.check_rounded,
                      size: 18,
                      color: theme.accentText,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
}
