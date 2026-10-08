import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../shared/l10n/l10n.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../shared/widgets/press_feedback.dart';

/// How tall the question box is: grown to its text (up to four lines), half
/// of the Ask tab, or all of it.
enum AskComposerSize { collapsed, half, full }

/// The Ask page's question box: one square card with the text on top and a
/// toolbar (the "深度思考" switch, send) below. It grows with the text up to
/// four lines; the expand button opens it to half of the tab, and from there
/// to the full tab. The same [TextField] lives in every size (only the
/// height around it animates), so focus, caret and draft survive.
class AskComposer extends StatefulWidget {
  const AskComposer({
    super.key,
    required this.controller,
    required this.theme,
    required this.isSending,
    required this.onSend,
    required this.hintText,
    required this.maxHeight,
    this.leading,
  });

  final TextEditingController controller;
  final AppThemeTokens theme;

  /// An answer is running: the send button cancels it.
  final bool isSending;
  final VoidCallback onSend;
  final String hintText;

  /// Height of the whole Ask tab (the composer never grows past it).
  final double maxHeight;

  /// Left end of the toolbar (the deep-thinking switch).
  final Widget? leading;

  @override
  State<AskComposer> createState() => _AskComposerState();
}

class _AskComposerState extends State<AskComposer> {
  static const _toolbarHeight = 42.0;
  // The text keeps a gap above the toolbar's buttons.
  static const _textPadding = EdgeInsets.fromLTRB(14, 10, 44, 8);
  static const _maxCollapsedLines = 4;
  static const _duration = Duration(milliseconds: 220);

  final FocusNode _focus = FocusNode();
  AskComposerSize _size = AskComposerSize.collapsed;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
    _focus.addListener(_changed);
  }

  @override
  void didUpdateWidget(AskComposer old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
    }
    // A question was sent: give the answer the room back.
    if (!old.isSending && widget.isSending) _size = AskComposerSize.collapsed;
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    _focus.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  /// Number of lines [text] takes in a field [width] wide.
  int _lines(String text, TextStyle style, double width, TextScaler scaler) {
    if (text.isEmpty) return 1;
    final painter = TextPainter(
      // A trailing newline shows an empty last line.
      text: TextSpan(text: text.endsWith('\n') ? '$text ' : text, style: style),
      textDirection: Directionality.of(context),
      textScaler: scaler,
    )..layout(maxWidth: width);
    final lines = painter.computeLineMetrics().length;
    painter.dispose();
    return lines < 1 ? 1 : lines;
  }

  void _setSize(AskComposerSize size) {
    setState(() => _size = size);
    // The buttons never take focus; the keyboard stays where it was.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final style = theme.bodyFont.copyWith(color: theme.textPrimary);
    final scaler = MediaQuery.textScalerOf(context);
    final expanded = _size != AskComposerSize.collapsed;
    final focused = _focus.hasFocus;
    // What the floating navigation (or the system bar) takes below the box.
    final below = MediaQuery.paddingOf(context).bottom;

    // A floating card, no strip behind it: the conversation shows around
    // and under it.
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
      child: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final textWidth = constraints.maxWidth - _textPadding.horizontal;
            final lines = _lines(widget.controller.text, style, textWidth, scaler);
            final lineHeight = (TextPainter(
              text: TextSpan(text: 'M', style: style),
              textDirection: Directionality.of(context),
              textScaler: scaler,
            )..layout())
                .preferredLineHeight;
            // The card's own border (1 px at most each side) takes room too.
            final collapsedHeight = _textPadding.vertical +
                lineHeight *
                    (lines > _maxCollapsedLines ? _maxCollapsedLines : lines) +
                _toolbarHeight +
                2;
            // The padding around the card (6 + 8) takes 14, plus 1 to spare,
            // and the room below it.
            final room = widget.maxHeight - 15 - below;
            final target = switch (_size) {
              AskComposerSize.collapsed => collapsedHeight,
              AskComposerSize.half => (room * 0.5).clamp(collapsedHeight, room),
              AskComposerSize.full => room,
            }
                .clamp(0.0, room > 0 ? room : collapsedHeight)
                .toDouble();
            final showExpand = lines >= 3 || expanded;

            return AnimatedContainer(
              key: const ValueKey('ask-input-bar'),
              duration: _duration,
              curve: Curves.easeOutCubic,
              height: target,
              decoration: BoxDecoration(
                color: theme.cardSurface.withValues(alpha: 0.97),
                borderRadius: BorderRadius.zero,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.14),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
                border: Border.all(
                  color: focused
                      ? theme.accentText.withValues(alpha: 0.55)
                      : theme.divider,
                  width: focused ? 1 : 0.5,
                ),
              ),
              child: Column(
                children: [
                  Expanded(
                    child: Stack(
                      children: [
                        TextField(
                          key: const ValueKey('ask-input-field'),
                          controller: widget.controller,
                          focusNode: _focus,
                          style: style,
                          cursorColor: theme.accentPrimary,
                          expands: true,
                          maxLines: null,
                          minLines: null,
                          textAlignVertical: TextAlignVertical.top,
                          keyboardType: TextInputType.multiline,
                          // Collapsed: the keyboard's key sends; opened up,
                          // it writes a new line.
                          textInputAction: expanded
                              ? TextInputAction.newline
                              : TextInputAction.send,
                          onSubmitted: expanded || widget.isSending
                              ? null
                              : (_) => widget.onSend(),
                          decoration: InputDecoration(
                            hintText: widget.hintText,
                            hintStyle: theme.bodyFont.copyWith(
                              color: theme.textSecondary,
                              fontSize: 13,
                            ),
                            contentPadding: _textPadding,
                            filled: false,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            disabledBorder: InputBorder.none,
                            errorBorder: InputBorder.none,
                            focusedErrorBorder: InputBorder.none,
                            isDense: true,
                          ),
                        ),
                        Positioned(
                          top: 4,
                          right: 4,
                          child: AnimatedOpacity(
                            duration: const Duration(milliseconds: 120),
                            opacity: showExpand ? 1 : 0,
                            child: IgnorePointer(
                              ignoring: !showExpand,
                              child: _roundButton(
                                key: const ValueKey('ask-input-expand-toggle'),
                                tooltip: expanded
                                    ? context.t.aiInputCollapse
                                    : context.t.aiInputExpand,
                                icon: expanded
                                    ? Icons.unfold_less_sharp
                                    : Icons.unfold_more_sharp,
                                onPressed: () => _setSize(
                                  expanded
                                      ? AskComposerSize.collapsed
                                      : AskComposerSize.half,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    height: _toolbarHeight,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(10, 0, 6, 8),
                      child: Row(
                        children: [
                          if (widget.leading != null) widget.leading!,
                          const Spacer(),
                          if (expanded) ...[
                            _roundButton(
                              key: const ValueKey('ask-input-fullscreen-toggle'),
                              tooltip: _size == AskComposerSize.full
                                  ? context.t.aiInputExitFullscreen
                                  : context.t.aiInputFullscreen,
                              icon: _size == AskComposerSize.full
                                  ? Icons.close_fullscreen_sharp
                                  : Icons.open_in_full_sharp,
                              onPressed: () => _setSize(
                                _size == AskComposerSize.full
                                    ? AskComposerSize.half
                                    : AskComposerSize.full,
                              ),
                            ),
                            const SizedBox(width: 6),
                          ],
                          // Sinks under the finger, ticks, and the icon turns
                          // (send ⇄ stop) with a small spin.
                          PressFeedback(
                            pressedScale: 0.86,
                            child: IconButton.filled(
                            key: const ValueKey('ask-send'),
                            onPressed: () {
                              HapticFeedback.lightImpact();
                              widget.onSend();
                            },
                            tooltip: widget.isSending
                                ? context.t.aiCancel
                                : context.t.aiSend,
                            icon: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 220),
                              transitionBuilder: (child, animation) =>
                                  RotationTransition(
                                turns: Tween<double>(begin: -0.25, end: 0)
                                    .animate(animation),
                                child: ScaleTransition(
                                  scale: animation,
                                  child: child,
                                ),
                              ),
                              child: Icon(
                                widget.isSending
                                    ? Icons.stop_sharp
                                    : Icons.arrow_upward_sharp,
                                key: ValueKey(widget.isSending),
                                size: 20,
                              ),
                            ),
                            style: IconButton.styleFrom(
                              backgroundColor: widget.isSending
                                  ? theme.danger
                                  : theme.accentPrimary,
                              foregroundColor:
                                  widget.isSending ? Colors.white : theme.onAccent,
                              minimumSize: const Size(32, 32),
                              maximumSize: const Size(32, 32),
                              padding: EdgeInsets.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                          ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  /// A small round icon button that never takes keyboard focus.
  Widget _roundButton({
    required Key key,
    required String tooltip,
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    final theme = widget.theme;
    return Tooltip(
      message: tooltip,
      child: PressFeedback(
        pressedScale: 0.88,
        child: InkResponse(
        key: key,
        canRequestFocus: false,
        containedInkWell: true,
        highlightShape: BoxShape.rectangle,
        onTap: withHaptic(onPressed),
        child: Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border.all(color: theme.divider, width: 0.5),
          ),
          child: Icon(icon, size: 18, color: theme.textSecondary),
        ),
      ),
      ),
    );
  }
}
