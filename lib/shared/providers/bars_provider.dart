import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether the main screen's bars (the top bar and the tab bar) are out of
/// the way: the wiki's page or the conversation was dragged on, to give the
/// reading the whole screen. Dragged back, at the top of the page, or on
/// another tab, they come back (MainShell resets it on a tab change).
final barsHiddenProvider = StateProvider<bool>((ref) => false);

/// Follows the drags of one scrolling view and hides or shows the bars:
/// [_run] of content moved one way hides them (onward) or shows them (back),
/// so a finger's jitter does neither.
class BarsFollower {
  double _run = 0;

  static const double _run0 = 24;

  /// The view moved by [delta] (positive: onward) by the reader's own
  /// drag; [atTop] when it is at its start.
  void moved(WidgetRef ref, double delta, {required bool atTop}) {
    final bars = ref.read(barsHiddenProvider.notifier);
    if (atTop) {
      _run = 0;
      if (bars.state) bars.state = false;
      return;
    }
    if (delta == 0) return;
    // A turn starts the run over.
    if ((delta > 0) != (_run > 0)) _run = 0;
    _run += delta;
    if (_run > _run0 && !bars.state) bars.state = true;
    if (_run < -_run0 && bars.state) bars.state = false;
  }

  /// A tap that ended on nothing tappable in the view (not a drag, not a
  /// button or a link): away, the bars come back; back, they go away again
  /// when [canHide] (the view is not at its start).
  void tapped(WidgetRef ref, {required bool canHide}) {
    _run = 0;
    final bars = ref.read(barsHiddenProvider.notifier);
    if (bars.state) {
      bars.state = false;
    } else if (canHide) {
      bars.state = true;
    }
  }

  /// The bars back (a new question, another page).
  void show(WidgetRef ref) {
    _run = 0;
    final bars = ref.read(barsHiddenProvider.notifier);
    if (bars.state) bars.state = false;
  }
}
