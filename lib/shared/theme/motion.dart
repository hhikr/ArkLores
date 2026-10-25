import 'package:flutter/widgets.dart';

/// The app's motion: short, hard, mechanical; every move answers one
/// action or one change of state; nothing bounces, nothing loops for show.
abstract final class Motion {
  /// Things that appear: arrive fast, then settle.
  static const snap = Cubic(0.16, 1, 0.3, 1);

  /// Wipes, shutters, panels and every exit: start slow, stop hard.
  static const mech = Cubic(0.7, 0, 0.2, 1);

  /// Plain transitions (a colour change).
  static const ease = Cubic(0.2, 0.7, 0.1, 1);

  static const press = Duration(milliseconds: 100);
  static const wipe = Duration(milliseconds: 280);
  static const row = Duration(milliseconds: 200);
  static const shutter = Duration(milliseconds: 360);
  static const shutterOut = Duration(milliseconds: 240);

  /// A pushed page's frosted pane sliding over the screen; the page is
  /// built behind it once it covers the screen.
  static const coverIn = Duration(milliseconds: 280);

  /// The pane clearing after the page's first frame: slow, the page comes
  /// into focus (the developer, 2026-10-24).
  static const reveal = Duration(milliseconds: 900);
  static const sheetIn = Duration(milliseconds: 360);
  static const sheetOut = Duration(milliseconds: 240);
  static const dialogIn = Duration(milliseconds: 280);
  static const dialogOut = Duration(milliseconds: 180);
  static const toastHold = Duration(milliseconds: 2000);

  /// Gap between list rows that come in one after another.
  static const staggerRow = Duration(milliseconds: 38);

  /// [value], or nothing when the system asks for reduced motion.
  static Duration of(BuildContext context, Duration value) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false
          ? Duration.zero
          : value;

  /// Whether the system asks for reduced motion.
  static bool reduced(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;
}
