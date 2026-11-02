import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../speaker_highlight.dart';

/// Where a card about a name opens: over the finger.
Rect nameCardAnchor(Offset position) =>
    Rect.fromLTWH(position.dx, position.dy - 16, 32, 24);

/// The underlined name under [position], if any: the linked run of the
/// paragraph there, when [isName] says it is one of the names.
String? linkedNameAt(
  BuildContext context,
  Offset position,
  bool Function(String) isName,
) {
  final result = HitTestResult();
  WidgetsBinding.instance
      .hitTestInView(result, position, View.of(context).viewId);
  for (final entry in result.path) {
    final target = entry.target;
    if (target is! RenderParagraph) continue;
    final at = target.getPositionForOffset(target.globalToLocal(position));
    final span = target.text.getSpanForPosition(at);
    final text = span is TextSpan ? span.text : null;
    return span is TextSpan &&
            span.recognizer != null &&
            text != null &&
            isName(text)
        ? text
        : null;
  }
  return null;
}

/// A line of plain text with the names in it underlined, as in an answer:
/// a tap opens the name's card, holding it offers to stop underlining it.
class NameLinkedText extends StatefulWidget {
  const NameLinkedText(
    this.text, {
    super.key,
    required this.matcher,
    required this.style,
    required this.underline,
    required this.onName,
    required this.onHold,
  });

  final String text;
  final SpeakerMatcher? matcher;
  final TextStyle style;
  final Color underline;
  final void Function(String name, Rect anchor) onName;
  final void Function(String name, Rect anchor) onHold;

  @override
  State<NameLinkedText> createState() => _NameLinkedTextState();
}

class _NameLinkedTextState extends State<NameLinkedText> {
  List<NameRun> _runs = const [];
  final _taps = <TapGestureRecognizer>[];
  Offset _down = Offset.zero;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  @override
  void didUpdateWidget(NameLinkedText old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text || !identical(old.matcher, widget.matcher)) {
      _prepare();
    }
  }

  void _prepare() {
    _release();
    _runs = widget.matcher?.runs(widget.text) ?? const [];
    for (final run in _runs) {
      if (!run.isName) continue;
      _taps.add(
        TapGestureRecognizer()
          ..onTap = () => widget.onName(run.text, nameCardAnchor(_down)),
      );
    }
  }

  void _release() {
    for (final tap in _taps) {
      tap.dispose();
    }
    _taps.clear();
  }

  @override
  void dispose() {
    _release();
    super.dispose();
  }

  void _hold(LongPressStartDetails details) {
    final name = linkedNameAt(
      context,
      details.globalPosition,
      (text) => _runs.any((run) => run.isName && run.text == text),
    );
    if (name == null) return;
    HapticFeedback.mediumImpact();
    widget.onHold(name, nameCardAnchor(details.globalPosition));
  }

  @override
  Widget build(BuildContext context) {
    if (_taps.isEmpty) return Text(widget.text, style: widget.style);
    final linked = widget.style.copyWith(
      decoration: TextDecoration.underline,
      decorationColor: widget.underline,
      decorationThickness: 2,
    );
    var tap = 0;
    return Listener(
      onPointerDown: (event) => _down = event.position,
      child: GestureDetector(
        onLongPressStart: _hold,
        child: Text.rich(
          TextSpan(
            children: [
              for (final run in _runs)
                run.isName
                    ? TextSpan(
                        text: run.text,
                        style: linked,
                        recognizer: _taps[tap++],
                      )
                    : TextSpan(text: run.text),
            ],
          ),
          style: widget.style,
        ),
      ),
    );
  }
}
