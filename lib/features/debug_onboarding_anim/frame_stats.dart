import 'dart:collection';
import 'dart:ui';

import 'package:flutter/foundation.dart';

/// Build and raster times of the last [window] frames (lab readout only).
class FrameStats extends ChangeNotifier {
  FrameStats({this.window = 120});

  final int window;
  final _build = Queue<double>();
  final _raster = Queue<double>();
  final _span = Queue<double>();

  int get count => _build.length;
  double get avgBuildMs => _avg(_build);
  double get avgRasterMs => _avg(_raster);
  double get worstBuildMs => _max(_build);
  double get worstRasterMs => _max(_raster);

  /// Frames per second from the average whole frame time (vsync caps it).
  double get fps {
    final a = _avg(_span);
    return a <= 0 ? 0 : 1000 / a;
  }

  void record(List<FrameTiming> timings) {
    for (final t in timings) {
      add(
        buildMs: t.buildDuration.inMicroseconds / 1000,
        rasterMs: t.rasterDuration.inMicroseconds / 1000,
        spanMs: t.totalSpan.inMicroseconds / 1000,
      );
    }
    notifyListeners();
  }

  @visibleForTesting
  void add({
    required double buildMs,
    required double rasterMs,
    required double spanMs,
  }) {
    for (final entry in [(_build, buildMs), (_raster, rasterMs), (_span, spanMs)]) {
      entry.$1.addLast(entry.$2);
      while (entry.$1.length > window) {
        entry.$1.removeFirst();
      }
    }
  }

  static double _avg(Iterable<double> v) =>
      v.isEmpty ? 0 : v.reduce((a, b) => a + b) / v.length;

  static double _max(Iterable<double> v) =>
      v.isEmpty ? 0 : v.reduce((a, b) => a > b ? a : b);
}
