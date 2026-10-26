import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../shared/l10n/l10n.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../shared/theme/cut_border.dart';
import '../../../shared/theme/motion.dart';
import '../../../shared/widgets/press_feedback.dart';

/// How tall the question box is: grown to its text (up to four lines), half
/// of the Ask tab, or all of it.
enum AskComposerSize { collapsed, half, full }

/// The Ask page's question box: one row at rest, text above a toolbar
/// while focused. It grows with the text up to four
/// lines; the expand button opens it to half of the tab, and from there to
/// the full tab. The same [TextField] lives in every size (only the height
/// around it animates), so focus, caret and draft survive. Focused, its
/// bottom edge is a 2px trace line.
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

  /// Left end of the toolbar (the answer options). It gets the link of the
  /// box's panel while the box is at its small size, so a panel can open
  /// above the whole box and leave the text being typed in view; null once
  /// the box is opened up (there is no room above it then).
  final Widget Function(LayerLink? card)? leading;

  @override
  State<AskComposer> createState() => _AskComposerState();
}

class _AskComposerState extends State<AskComposer> {
  static const _toolbarHeight = 48.0;
  // Leave room between the text and the toolbar buttons.
  static const _textPadding = EdgeInsets.fromLTRB(14, 12, 52, 8);
  static const _maxCollapsedLines = 4;

  final FocusNode _focus = FocusNode();
  final LayerLink _cardLink = LayerLink();
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
    if (!old.isSending && widget.isSending) {
      _size = AskComposerSize.collapsed;
      _focus.unfocus();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    _focus.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) {
      setState(() {
        if (!_focus.hasFocus) _size = AskComposerSize.collapsed;
      });
    }
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
    final style = theme.text(16, height: 1.5);
    final scaler = MediaQuery.textScalerOf(context);
    final expanded = _size != AskComposerSize.collapsed;
    final focused = _focus.hasFocus;
    final editing = focused || expanded;
    final empty = widget.controller.text.trim().isEmpty;
    // What the tab bar (or the system bar) takes below the box.
    final below = MediaQuery.paddingOf(context).bottom;

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
      child: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final textWidth = constraints.maxWidth - _textPadding.horizontal;
            final lines =
                _lines(widget.controller.text, style, textWidth, scaler);
            final lineHeight = (TextPainter(
              text: TextSpan(text: 'M', style: style),
              textDirection: Directionality.of(context),
              textScaler: scaler,
            )..layout())
                .preferredLineHeight;
            // The panel's frame (1 px above, 2 below at most) takes room too.
            final collapsedHeight = _textPadding.vertical +
                lineHeight *
                    (lines > _maxCollapsedLines ? _maxCollapsedLines : lines) +
                _toolbarHeight +
                3;
            // The padding around the panel (6 + 8) takes 14, plus 1 to spare,
            // and the room below it.
            final room = widget.maxHeight - 15 - below;
            final target = switch (_size) {
              AskComposerSize.collapsed =>
                editing ? collapsedHeight : _toolbarHeight + 3,
              AskComposerSize.half => (room * 0.5).clamp(collapsedHeight, room),
              AskComposerSize.full => room,
            }
                .clamp(0.0, room > 0 ? room : collapsedHeight)
                .toDouble();

            return CompositedTransformTarget(
              link: _cardLink,
              child: AnimatedContainer(
                key: const ValueKey('ask-input-bar'),
                duration: Motion.of(context, Motion.wipe),
                curve: Motion.mech,
                height: target,
                decoration: BoxDecoration(
                  color: theme.cardSurface,
                  border: Border(
                    top: BorderSide(color: theme.divider),
                    left: BorderSide(color: theme.divider),
                    right: BorderSide(color: theme.divider),
                    bottom: BorderSide(
                      color: focused ? theme.trace : theme.divider,
                      width: focused ? 2 : 1,
                    ),
                  ),
                ),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: PressBuilder(
                        builder: (context, down) => GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: _focus.requestFocus,
                          child: ColoredBox(
                            color: down
                                ? pressTint(
                                    theme.cardSurface,
                                    theme.textPrimary,
                                  )
                                : theme.cardSurface,
                          ),
                        ),
                      ),
                    ),
                    // Fixed tree position preserves the keyboard connection.
                    Positioned(
                      top: 0,
                      bottom: editing ? _toolbarHeight : 0,
                      left: editing ? 0 : (widget.leading == null ? 4 : 48),
                      right: editing ? 0 : 56,
                      child: Opacity(
                        opacity: editing ? 1 : 0,
                        alwaysIncludeSemantics: true,
                        child: TextField(
                          key: const ValueKey('ask-input-field'),
                          controller: widget.controller,
                          focusNode: _focus,
                          style: style,
                          expands: editing,
                          maxLines: editing ? null : 1,
                          minLines: null,
                          textAlignVertical: TextAlignVertical.top,
                          keyboardType: TextInputType.multiline,
                          textInputAction: TextInputAction.newline,
                          decoration: InputDecoration(
                            hintText: widget.hintText,
                            hintStyle: theme.text(15, color: theme.textMuted),
                            contentPadding: editing
                                ? _textPadding
                                : const EdgeInsets.fromLTRB(10, 12, 4, 8),
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
                      ),
                    ),
                    Positioned(
                      left: 4,
                      bottom: 4,
                      child:
                          widget.leading?.call(expanded ? null : _cardLink) ??
                              const SizedBox.shrink(),
                    ),
                    Positioned(
                      right: 4,
                      bottom: 4,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (editing)
                            ComposerButton(
                              key: const ValueKey('ask-input-expand-toggle'),
                              theme: theme,
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
                          if (expanded) ...[
                            ComposerButton(
                              key:
                                  const ValueKey('ask-input-fullscreen-toggle'),
                              theme: theme,
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
                            const SizedBox(width: 4),
                          ],
                          _SendButton(
                            theme: theme,
                            sending: widget.isSending,
                            empty: empty,
                            onPressed: widget.onSend,
                          ),
                        ],
                      ),
                    ),
                    // A single-line preview must not flatten or scroll the
                    // underlying draft when it contains line breaks.
                    if (!editing)
                      Positioned(
                        top: 12,
                        left: widget.leading == null ? 14 : 58,
                        right: 60,
                        child: IgnorePointer(
                          child: ExcludeSemantics(
                            child: Text(
                              empty
                                  ? widget.hintText
                                  : widget.controller.text.split('\n').first,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: empty
                                  ? theme.text(15, color: theme.textMuted)
                                  : style,
                            ),
                          ),
                        ),
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
          },
        ),
      ),
    );
  }
}

/// A square button of the question box: 44 to the finger, drawn 40; never
/// takes keyboard focus (the keyboard stays up). [selected]: an option is
/// on (an accent fill).
class ComposerButton extends StatefulWidget {
  const ComposerButton({
    super.key,
    required this.theme,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.selected = false,
  });

  final AppThemeTokens theme;
  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;
  final bool selected;

  @override
  State<ComposerButton> createState() => _ComposerButtonState();
}

class _ComposerButtonState extends State<ComposerButton>
    with PressHold<ComposerButton> {
  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final down = pressed;
    final on = down || widget.selected;
    return Tooltip(
      message: widget.tooltip,
      child: Semantics(
        button: true,
        label: widget.tooltip,
        toggled: widget.selected ? true : null,
        excludeSemantics: true,
        child: pressListener(
          enabled: true,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              HapticFeedback.selectionClick();
              widget.onPressed();
            },
            child: SizedBox(
              width: 44,
              height: 44,
              child: Center(
                child: AnimatedContainer(
                  duration:
                      Motion.of(context, down ? Motion.press : Motion.wipe),
                  curve: Motion.mech,
                  width: 40,
                  height: 40,
                  decoration: ShapeDecoration(
                    color: on ? theme.accentPrimary : theme.surfaceElevated,
                    shape: const CutBorder.br(7),
                  ),
                  child: Icon(
                    widget.icon,
                    size: 20,
                    color: on ? theme.onAccent : theme.textPrimary,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Send (the one main action: the accent, cut corner), or, while an answer
/// runs, stop (an ink block). Dimmed while there is nothing to send.
class _SendButton extends StatefulWidget {
  const _SendButton({
    required this.theme,
    required this.sending,
    required this.empty,
    required this.onPressed,
  });

  final AppThemeTokens theme;
  final bool sending;
  final bool empty;
  final VoidCallback onPressed;

  @override
  State<_SendButton> createState() => _SendButtonState();
}

class _SendButtonState extends State<_SendButton> with PressHold<_SendButton> {
  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final idle = !widget.sending && widget.empty;
    final bg = widget.sending
        ? theme.tagBackground
        : idle
            ? theme.surfaceElevated
            : theme.accentPrimary;
    final fg = widget.sending
        ? theme.tagForeground
        : idle
            ? theme.textMuted
            : theme.onAccent;
    final label = widget.sending ? context.t.aiCancel : context.t.aiSend;
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        child: pressListener(
          enabled: true,
          child: GestureDetector(
            key: const ValueKey('ask-send'),
            behavior: HitTestBehavior.opaque,
            onTap: () {
              HapticFeedback.lightImpact();
              widget.onPressed();
            },
            child: SizedBox(
              width: 52,
              height: 44,
              child: Center(
                child: ClipPath(
                  clipper: const ShapeBorderClipper(shape: CutBorder.br(8)),
                  child: SizedBox(
                    width: 48,
                    height: 40,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ColoredBox(color: bg),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: AnimatedFractionallySizedBox(
                            duration: Motion.of(
                              context,
                              pressed ? Motion.press : Motion.wipe,
                            ),
                            curve: Motion.mech,
                            widthFactor: pressed ? 1 : 0,
                            heightFactor: 1,
                            child: ColoredBox(
                              color: theme.textPrimary.withValues(alpha: 0.16),
                            ),
                          ),
                        ),
                        Icon(
                          widget.sending
                              ? Icons.stop_sharp
                              : Icons.arrow_upward_sharp,
                          size: 22,
                          color: fg,
                        ),
                      ],
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
}
