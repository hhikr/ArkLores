import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../../../shared/theme/motion.dart';

Duration answerRevealDuration(int characters) => Duration(
      microseconds: math.min(1200000, (characters / 120 * 1000000).round()),
    );

/// One clock preserves paragraph order even when several blocks arrive together.
class AnswerRevealQueue extends ChangeNotifier {
  AnswerRevealQueue(TickerProvider vsync) {
    _ticker = vsync.createTicker(_tick);
  }
  late final Ticker _ticker;
  final _remaining = <String>[];
  final _durations = <String, Duration>{};
  final _values = <String, double>{};
  Duration _last = Duration.zero;
  bool ended = false;
  bool immediate = false;

  double value(String id) => _values[id] ?? 1;
  void add(String id, int characters, {required bool animate}) {
    if (_values.containsKey(id)) return;
    _values[id] = animate && !immediate ? 0 : 1;
    if (_values[id] == 1) return;
    _remaining.add(id);
    _durations[id] = answerRevealDuration(characters);
    if (!_ticker.isActive) {
      _last = Duration.zero;
      _ticker.start();
    }
  }

  void reset() {
    _ticker.stop();
    _remaining.clear();
    _durations.clear();
    _values.clear();
  }

  void flush() {
    for (final id in _remaining) {
      _values[id] = 1;
    }
    _remaining.clear();
    _ticker.stop();
    notifyListeners();
  }

  void _tick(Duration elapsed) {
    var micros = (elapsed - _last).inMicroseconds.toDouble();
    _last = elapsed;
    while (_remaining.isNotEmpty && micros > 0) {
      final id = _remaining.first;
      final speed = ended ? 3 : (_remaining.length > 2 ? 2 : 1);
      final duration = math.max(1, _durations[id]!.inMicroseconds);
      final needed = (1 - _values[id]!) * duration / speed;
      if (micros < needed) {
        _values[id] = _values[id]! + micros * speed / duration;
        break;
      }
      micros -= needed;
      _values[id] = 1;
      _remaining.removeAt(0);
    }
    if (_remaining.isEmpty) _ticker.stop();
    notifyListeners();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }
}

class AnswerReveal extends StatelessWidget {
  const AnswerReveal({
    super.key,
    required this.queue,
    required this.id,
    required this.lineHeight,
    required this.text,
    this.evidence,
  });
  final AnswerRevealQueue queue;
  final String id;
  final double lineHeight;
  final Widget text;
  final Widget? evidence;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: queue,
        child: text,
        builder: (context, child) {
          final progress = queue.immediate ? 1.0 : queue.value(id);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _LineWipe(
                progress: progress,
                lineHeight: lineHeight,
                child: child!,
              ),
              if (evidence != null)
                IgnorePointer(
                  ignoring: progress < 1,
                  child: AnimatedOpacity(
                    opacity: progress == 1 ? 1 : 0,
                    duration: queue.immediate
                        ? Duration.zero
                        : Motion.of(context, Motion.row),
                    curve: Curves.linear,
                    child: evidence!,
                  ),
                ),
            ],
          );
        },
      );
}

class _LineWipe extends SingleChildRenderObjectWidget {
  const _LineWipe({
    required this.progress,
    required this.lineHeight,
    required super.child,
  });
  final double progress;
  final double lineHeight;
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderLineWipe(progress, lineHeight);
  @override
  void updateRenderObject(BuildContext context, _RenderLineWipe renderObject) {
    renderObject.update(progress, lineHeight);
  }
}

class _RenderLineWipe extends RenderProxyBox {
  _RenderLineWipe(this.progress, this.lineHeight);
  double progress;
  double lineHeight;
  void update(double next, double height) {
    if (next == progress && height == lineHeight) return;
    progress = next;
    lineHeight = height;
    markNeedsPaint();
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) =>
      progress == 1 && super.hitTest(result, position: position);
  @override
  void paint(PaintingContext context, Offset offset) {
    if (progress <= 0) return;
    if (progress >= 1) {
      super.paint(context, offset);
      return;
    }
    final canvas = context.canvas;
    final rows = (size.height / lineHeight).ceil();
    final cursor = progress * rows;
    final row = cursor.floor();
    final x = (cursor - row) * (size.width + 24);
    final y = row * lineHeight;
    canvas.saveLayer(offset & size, Paint());
    super.paint(context, offset);
    final erase = Paint()
      ..blendMode = BlendMode.dstOut
      ..color = const Color(0xff000000);
    canvas.drawRect(
      Rect.fromLTWH(
        offset.dx,
        offset.dy + y + lineHeight,
        size.width,
        math.max(0, size.height - y - lineHeight),
      ),
      erase,
    );
    canvas.drawRect(
      Rect.fromLTWH(
        offset.dx + x,
        offset.dy + y,
        math.max(0, size.width - x),
        lineHeight,
      ),
      erase,
    );
    final edge =
        Rect.fromLTWH(offset.dx + x - 24, offset.dy + y, 24, lineHeight);
    canvas.drawRect(
      edge,
      Paint()
        ..blendMode = BlendMode.dstOut
        ..shader = const LinearGradient(
          colors: [Color(0x00000000), Color(0xff000000)],
        ).createShader(edge),
    );
    canvas.restore();
  }
}
