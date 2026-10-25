import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/agent/answer_options.dart';
import '../../../core/llm/llm_provider.dart'
    show deepThinkingAvailableProvider, deepThinkingProvider;
import '../../../shared/l10n/l10n.dart';
import '../../../shared/providers/settings_provider.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../shared/theme/motion.dart';
import '../../../shared/widgets/press_feedback.dart';
import 'ask_composer.dart' show ComposerButton;

/// The question box's one options button: a small panel that opens upward
/// (above the whole box, so the text being typed stays in view) with how
/// the next questions are answered — the wikis, the sub-agents, and "深度思考"
/// where the model service has a switch for it.
///
/// The panel is an overlay beside the box, not a route, and nothing in it
/// takes focus: the keyboard stays where it was. The button is filled with
/// the accent while a costlier way of answering (sub-agents, thinking) is on.
class AnswerOptionsMenu extends ConsumerStatefulWidget {
  const AnswerOptionsMenu({super.key, required this.theme, this.above});

  final AppThemeTokens theme;

  /// What the panel opens above (the question box's panel, so the text
  /// being typed stays in view); the button itself when null.
  final LayerLink? above;

  @override
  ConsumerState<AnswerOptionsMenu> createState() => _AnswerOptionsMenuState();
}

class _AnswerOptionsMenuState extends ConsumerState<AnswerOptionsMenu>
    with SingleTickerProviderStateMixin {
  final OverlayPortalController _portal = OverlayPortalController();
  final LayerLink _link = LayerLink();

  /// The panel wipes up out of the box when opened (`snap`) and back down
  /// into it when closed (`mech`); it leaves the overlay once closed.
  late final AnimationController _open = AnimationController(
    vsync: this,
    duration: Motion.wipe,
    reverseDuration: Motion.sheetOut,
  );
  late final Animation<double> _wipe = CurvedAnimation(
    parent: _open,
    curve: Motion.snap,
    reverseCurve: Motion.mech.flipped,
  );

  /// Shown, and not on its way out.
  bool get _opened => _portal.isShowing && _open.status != AnimationStatus.reverse;

  @override
  void dispose() {
    _open.dispose();
    super.dispose();
  }

  void _toggle() => _opened ? _close() : _show();

  void _show() {
    setState(_portal.show);
    _open.duration = Motion.of(context, Motion.wipe);
    _open.reverseDuration = Motion.of(context, Motion.sheetOut);
    _open.forward();
  }

  void _close() {
    if (!_opened) return;
    setState(() {});
    _open.reverse().whenCompleteOrCancel(() {
      if (mounted && _open.isDismissed) setState(_portal.hide);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final options = ref.watch(answerOptionsProvider);
    final thinkingAvailable = ref.watch(deepThinkingAvailableProvider);
    final thinking = thinkingAvailable && ref.watch(deepThinkingProvider);
    final lit = options.delegate || thinking || _opened;
    return TapRegion(
      groupId: _link,
      onTapOutside: (_) => _close(),
      child: CompositedTransformTarget(
        link: _link,
        child: OverlayPortal(
          controller: _portal,
          overlayChildBuilder: (context) => Positioned(
            left: 0,
            top: 0,
            child: CompositedTransformFollower(
              link: widget.above ?? _link,
              showWhenUnlinked: false,
              targetAnchor: Alignment.topLeft,
              followerAnchor: Alignment.bottomLeft,
              offset: Offset(widget.above == null ? 0 : 0, -6),
              child: TapRegion(
                groupId: _link,
                child: FadeTransition(
                  opacity: _wipe,
                  child: SizeTransition(
                    sizeFactor: _wipe,
                    alignment: Alignment.bottomLeft,
                    child: _panel(theme, options, thinkingAvailable, thinking),
                  ),
                ),
              ),
            ),
          ),
          child: ComposerButton(
            key: const ValueKey('answer-options'),
            theme: theme,
            tooltip: context.t.aiAnswerOptions,
            icon: Icons.tune_sharp,
            selected: lit,
            onPressed: _toggle,
          ),
        ),
      ),
    );
  }

  Widget _panel(
    AppThemeTokens theme,
    AnswerOptions options,
    bool thinkingAvailable,
    bool thinking,
  ) {
    final notifier = ref.read(answerOptionsProvider.notifier);
    return Material(
      key: const ValueKey('answer-options-panel'),
      color: theme.cardSurface,
      shape: Border.all(color: theme.divider),
      child: SizedBox(
        width: 264,
        child: Stack(
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 3),
                _row(
                  theme,
                  'wiki',
                  options.wiki,
                  context.t.aiAnswerWiki,
                  context.t.aiAnswerWikiShort,
                  () => notifier.set(options.copyWith(wiki: !options.wiki)),
                ),
                _row(
                  theme,
                  'delegate',
                  options.delegate,
                  context.t.aiAnswerDelegate,
                  context.t.aiAnswerDelegateShort,
                  () => notifier
                      .set(options.copyWith(delegate: !options.delegate)),
                ),
                if (thinkingAvailable)
                  _row(
                    theme,
                    'think',
                    thinking,
                    context.t.aiDeepThinking,
                    context.t.aiDeepThinkingShort,
                    () => ref.read(deepThinkingProvider.notifier).state =
                        !thinking,
                  ),
              ],
            ),
            Positioned(
              left: 0,
              top: 0,
              width: 32,
              height: 3,
              child: ColoredBox(color: theme.textPrimary),
            ),
          ],
        ),
      ),
    );
  }

  /// One option: a square check (accent block when on), what it is, a short
  /// note; at least 52 high.
  Widget _row(
    AppThemeTokens theme,
    String value,
    bool checked,
    String title,
    String hint,
    VoidCallback onTap,
  ) =>
      Semantics(
        button: true,
        toggled: checked,
        label: title,
        excludeSemantics: true,
        child: PressBuilder(
          builder: (context, down) => GestureDetector(
            key: ValueKey('answer-option-$value'),
            behavior: HitTestBehavior.opaque,
            onTap: () {
              HapticFeedback.selectionClick();
              onTap();
            },
            child: AnimatedContainer(
              duration: Motion.of(context, down ? Motion.press : Motion.row),
              curve: Motion.mech,
              constraints: const BoxConstraints(minHeight: 52),
              padding: const EdgeInsets.fromLTRB(12, 8, 14, 8),
              decoration: BoxDecoration(
                color: down
                    ? pressTint(Colors.transparent, theme.textPrimary)
                    : Colors.transparent,
                border: Border(bottom: BorderSide(color: theme.divider)),
              ),
              child: Row(
                children: [
                  AnimatedContainer(
                    duration: Motion.of(context, Motion.press),
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: checked ? theme.accentPrimary : Colors.transparent,
                      border: Border.all(
                        color: checked ? theme.accentPrimary : theme.cardBorder,
                        width: 1.5,
                      ),
                    ),
                    child: checked
                        ? Icon(Icons.check_sharp, size: 16, color: theme.onAccent)
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          style: theme.ui(15, weight: checked ? 700 : 500),
                        ),
                        Text(
                          hint,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.text(12.5, color: theme.textSecondary, height: 1.4),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}
