import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/scheduler.dart';

/// Lightweight frame timing probe for manual profiling runs.
///
/// Enable with:
///   --dart-define=PERF_FRAME_LOG=true
class PerfProbe {
  PerfProbe._();

  static const bool _enabled =
      bool.fromEnvironment('PERF_FRAME_LOG', defaultValue: false);
  static const int _reportIntervalMs =
      int.fromEnvironment('PERF_FRAME_LOG_INTERVAL_MS', defaultValue: 5000);
  static const int _warmupMs =
      int.fromEnvironment('PERF_FRAME_WARMUP_MS', defaultValue: 1200);
  static final double _jankBudgetMs = double.tryParse(
        const String.fromEnvironment(
          'PERF_FRAME_BUDGET_MS',
          defaultValue: '16.67',
        ),
      ) ??
      16.67;

  static bool _started = false;
  static final Stopwatch _uptime = Stopwatch();
  static final List<double> _uiFrameMs = <double>[];
  static final List<double> _rasterFrameMs = <double>[];
  static final List<double> _totalFrameMs = <double>[];
  static int _windowJankCount = 0;

  static void startIfEnabled() {
    if (!_enabled || _started) {
      return;
    }
    _started = true;
    _uptime.start();
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
    final int safeIntervalMs = math.max(1000, _reportIntervalMs);
    Timer.periodic(
      Duration(milliseconds: safeIntervalMs),
      (_) => _reportWindow(),
    );
  }

  static void _onTimings(List<FrameTiming> timings) {
    if (_uptime.elapsedMilliseconds < _warmupMs) {
      return;
    }
    for (final FrameTiming timing in timings) {
      final double uiMs = timing.buildDuration.inMicroseconds / 1000.0;
      final double rasterMs = timing.rasterDuration.inMicroseconds / 1000.0;
      final double totalMs = timing.totalSpan.inMicroseconds / 1000.0;
      _uiFrameMs.add(uiMs);
      _rasterFrameMs.add(rasterMs);
      _totalFrameMs.add(totalMs);
      if (totalMs > _jankBudgetMs) {
        _windowJankCount += 1;
      }
    }
  }

  static void _reportWindow() {
    if (_totalFrameMs.isEmpty) {
      return;
    }
    final int frames = _totalFrameMs.length;
    final double avgUi = _avg(_uiFrameMs);
    final double avgRaster = _avg(_rasterFrameMs);
    final double avgTotal = _avg(_totalFrameMs);
    final double p95Total = _percentile(_totalFrameMs, 0.95);
    final double p99Total = _percentile(_totalFrameMs, 0.99);
    final double maxTotal = _max(_totalFrameMs);
    final double jankRate = (_windowJankCount / frames) * 100.0;
    // ignore: avoid_print
    print(
      '[PERF] frames=$frames avg_ui=${avgUi.toStringAsFixed(2)}ms '
      'avg_raster=${avgRaster.toStringAsFixed(2)}ms '
      'avg_total=${avgTotal.toStringAsFixed(2)}ms '
      'p95_total=${p95Total.toStringAsFixed(2)}ms '
      'p99_total=${p99Total.toStringAsFixed(2)}ms '
      'max_total=${maxTotal.toStringAsFixed(2)}ms '
      'jank>${_jankBudgetMs.toStringAsFixed(2)}ms='
      '$_windowJankCount/$frames (${jankRate.toStringAsFixed(1)}%)',
    );
    _uiFrameMs.clear();
    _rasterFrameMs.clear();
    _totalFrameMs.clear();
    _windowJankCount = 0;
  }

  static double _avg(List<double> values) {
    double sum = 0.0;
    for (final double value in values) {
      sum += value;
    }
    return sum / values.length;
  }

  static double _max(List<double> values) {
    double out = values.first;
    for (final double value in values) {
      if (value > out) {
        out = value;
      }
    }
    return out;
  }

  static double _percentile(List<double> values, double p) {
    final List<double> sorted = List<double>.from(values)..sort();
    final int index = ((sorted.length - 1) * p).round();
    return sorted[index.clamp(0, sorted.length - 1)];
  }
}
