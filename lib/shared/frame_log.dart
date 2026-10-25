import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Frame times in the log, only in a profile build (`install_local.ps1
/// -Build -FrameLog`): every slow frame, and a line a second while frames are drawn.
/// Read them with `adb logcat -s flutter`.
void startFrameLog() {
  if (!kProfileMode) return;
  // Every widget's build, layout and paint in the timeline (and, with the
  // engine's TraceSystrace, in a system trace): what a slow frame spent on.
  if (const bool.fromEnvironment('ARKLORES_TRACE_WIDGETS')) {
    debugProfileBuildsEnabled = true;
    debugProfileLayoutsEnabled = true;
    debugProfilePaintsEnabled = true;
  }
  var count = 0, slow = 0;
  var worstBuild = 0.0, worstRaster = 0.0;
  var start = DateTime.now();
  double ms(Duration d) => d.inMicroseconds / 1000;
  SchedulerBinding.instance.addTimingsCallback((timings) {
    for (final t in timings) {
      final build = ms(t.buildDuration), raster = ms(t.rasterDuration);
      final total = ms(t.totalSpan);
      count++;
      if (build > worstBuild) worstBuild = build;
      if (raster > worstRaster) worstRaster = raster;
      if (total > 16) {
        slow++;
        debugPrint(
            '[frame] slow #${t.frameNumber} build ${build.toStringAsFixed(1)} '
            'raster ${raster.toStringAsFixed(1)} total ${total.toStringAsFixed(1)} '
            'vsyncWait ${ms(t.vsyncOverhead).toStringAsFixed(1)}');
      }
    }
    final now = DateTime.now();
    if (now.difference(start).inMilliseconds >= 1000) {
      debugPrint('[frame] ${now.toIso8601String().substring(11, 19)} '
          '$count frames, $slow slow, worst build ${worstBuild.toStringAsFixed(1)} '
          'raster ${worstRaster.toStringAsFixed(1)}');
      count = 0;
      slow = 0;
      worstBuild = 0;
      worstRaster = 0;
      start = now;
    }
  });
}
