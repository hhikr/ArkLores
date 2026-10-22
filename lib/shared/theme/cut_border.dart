import 'package:flutter/painting.dart';

/// A rectangle with corners cut off at 45°: the shape of everything that can
/// be pressed (buttons, chips, tags, tappable panels). Things that cannot be
/// pressed are plain rectangles. Each corner's cut is its length along an
/// edge; 0 leaves the corner square.
class CutBorder extends OutlinedBorder {
  const CutBorder({
    super.side,
    this.topLeft = 0,
    this.topRight = 0,
    this.bottomRight = 0,
    this.bottomLeft = 0,
  });

  /// Only the bottom-right corner cut: the usual mark of a pressable thing.
  const CutBorder.br(double cut, {BorderSide side = BorderSide.none})
      : this(side: side, bottomRight: cut);

  final double topLeft;
  final double topRight;
  final double bottomRight;
  final double bottomLeft;

  Path _path(Rect r, double inset) {
    double c(double v) => (v - inset).clamp(0, r.shortestSide / 2);
    final rect = r.deflate(inset);
    final tl = c(topLeft),
        tr = c(topRight),
        br = c(bottomRight),
        bl = c(bottomLeft);
    return Path()
      ..moveTo(rect.left + tl, rect.top)
      ..lineTo(rect.right - tr, rect.top)
      ..lineTo(rect.right, rect.top + tr)
      ..lineTo(rect.right, rect.bottom - br)
      ..lineTo(rect.right - br, rect.bottom)
      ..lineTo(rect.left + bl, rect.bottom)
      ..lineTo(rect.left, rect.bottom - bl)
      ..lineTo(rect.left, rect.top + tl)
      ..close();
  }

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(side.width);

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      _path(rect, side.width);

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) =>
      _path(rect, 0);

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (side.style == BorderStyle.none || side.width == 0) return;
    canvas.drawPath(_path(rect, side.width / 2), side.toPaint());
  }

  @override
  CutBorder scale(double t) => CutBorder(
        side: side.scale(t),
        topLeft: topLeft * t,
        topRight: topRight * t,
        bottomRight: bottomRight * t,
        bottomLeft: bottomLeft * t,
      );

  @override
  CutBorder copyWith({BorderSide? side}) => CutBorder(
        side: side ?? this.side,
        topLeft: topLeft,
        topRight: topRight,
        bottomRight: bottomRight,
        bottomLeft: bottomLeft,
      );

  @override
  ShapeBorder? lerpFrom(ShapeBorder? a, double t) => a is CutBorder
      ? CutBorder(
          side: BorderSide.lerp(a.side, side, t),
          topLeft: _lerp(a.topLeft, topLeft, t),
          topRight: _lerp(a.topRight, topRight, t),
          bottomRight: _lerp(a.bottomRight, bottomRight, t),
          bottomLeft: _lerp(a.bottomLeft, bottomLeft, t),
        )
      : super.lerpFrom(a, t);

  static double _lerp(double a, double b, double t) => a + (b - a) * t;

  @override
  bool operator ==(Object other) =>
      other is CutBorder &&
      other.side == side &&
      other.topLeft == topLeft &&
      other.topRight == topRight &&
      other.bottomRight == bottomRight &&
      other.bottomLeft == bottomLeft;

  @override
  int get hashCode =>
      Object.hash(side, topLeft, topRight, bottomRight, bottomLeft);
}
