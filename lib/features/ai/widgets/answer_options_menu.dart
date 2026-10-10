import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/agent/answer_options.dart';
import '../../../core/llm/llm_provider.dart'
    show deepThinkingAvailableProvider, deepThinkingProvider;
import '../../../shared/l10n/l10n.dart';
import '../../../shared/providers/settings_provider.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../shared/widgets/press_feedback.dart';

/// The question box's one options button: a small panel that opens upward
/// (above the whole box, so the text being typed stays in view) with how
/// the next questions are answered — the wikis, the
/// sub-agents, and "深度思考" where the model service has a switch for it.
///
/// The panel is an overlay beside the box, not a route, and nothing in it
/// takes focus: the keyboard stays where it was. The button is lit while a
/// costlier way of answering (sub-agents, thinking) is on.
class AnswerOptionsMenu extends ConsumerStatefulWidget {
  const AnswerOptionsMenu({super.key, required this.theme, this.above});

  final AppThemeTokens theme;

  /// What the panel opens above (the question box's card, so the text
  /// being typed stays in view); the button itself when null.
  final LayerLink? above;

  @override
  ConsumerState<AnswerOptionsMenu> createState() => _AnswerOptionsMenuState();
}

class _AnswerOptionsMenuState extends ConsumerState<AnswerOptionsMenu> {
  final OverlayPortalController _portal = OverlayPortalController();
  final LayerLink _link = LayerLink();

  void _toggle() => setState(_portal.toggle);

  void _close() {
    if (_portal.isShowing) setState(_portal.hide);
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final options = ref.watch(answerOptionsProvider);
    final thinkingAvailable = ref.watch(deepThinkingAvailableProvider);
    final thinking = thinkingAvailable && ref.watch(deepThinkingProvider);
    final lit = options.delegate || thinking || _portal.isShowing;
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
              offset: Offset(widget.above == null ? -4 : 0, -6),
              child: TapRegion(
                groupId: _link,
                child: _panel(theme, options, thinkingAvailable, thinking),
              ),
            ),
          ),
          child: Tooltip(
            message: context.t.aiAnswerOptions,
            child: PressFeedback(
              pressedScale: 0.88,
              child: InkResponse(
                key: const ValueKey('answer-options'),
                canRequestFocus: false,
                containedInkWell: true,
                highlightShape: BoxShape.rectangle,
                onTap: withHaptic(_toggle),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(
                    color: lit
                        ? theme.accentPrimary.withValues(alpha: 0.18)
                        : Colors.transparent,
                    border: Border.all(
                      color: lit
                          ? theme.accentText.withValues(alpha: 0.4)
                          : theme.divider,
                      width: 0.5,
                    ),
                  ),
                  child: Icon(
                    Icons.tune_sharp,
                    size: 18,
                    color: lit ? theme.accentText : theme.textSecondary,
                  ),
                ),
              ),
            ),
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
      color: theme.surfaceElevated,
      elevation: 6,
      shadowColor: Colors.black.withValues(alpha: 0.3),
      shape: Border.all(color: theme.divider, width: 0.5),
      child: SizedBox(
        width: 248,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
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
              () => notifier.set(options.copyWith(delegate: !options.delegate)),
            ),
            if (thinkingAvailable)
              _row(
                theme,
                'think',
                thinking,
                context.t.aiDeepThinking,
                context.t.aiDeepThinkingShort,
                () => ref.read(deepThinkingProvider.notifier).state = !thinking,
              ),
          ],
        ),
      ),
    );
  }

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
        child: InkWell(
          key: ValueKey('answer-option-$value'),
          canRequestFocus: false,
          onTap: withHaptic(onTap),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 7, 12, 7),
            child: Row(
              children: [
                SizedBox(
                  width: 22,
                  child: checked
                      ? Icon(Icons.check_sharp, size: 17, color: theme.accentText)
                      : null,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: theme.bodyFont.copyWith(
                          fontSize: 13.5,
                          color: theme.textPrimary,
                        ),
                      ),
                      Text(
                        hint,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.bodyFont.copyWith(
                          fontSize: 11,
                          color: theme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}
