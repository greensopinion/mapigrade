// Frame rate measurement (task 7.4, design D10). Run in a release build:
//
//   flutter build macos --release --dart-define=BENCHMARK=true
//   MLT_WINDOW_SIZE=1600x1000 build/macos/Build/Products/Release/<app>/Contents/MacOS/<app>
//
// Pans continuously at a fixed zoom for 30 s to load and cache the area, goes
// back to the start, waits for idle, then pans the same path again for 30 s
// and measures. Prints one line starting with BENCHMARK_RESULT and exits.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/scheduler.dart';
import 'package:flutter_map_maplibre_texture/flutter_map_maplibre_texture.dart';

const benchmarkEnabled = bool.fromEnvironment('BENCHMARK');
const phaseDuration = Duration(seconds: 30);
const start = MapCamera(latitude: 37.7749, longitude: -122.4194, zoom: 14);

/// Viewport widths per second of the pan.
const panSpeed = 0.2;

class Benchmark {
  Benchmark(this.controller, {required this.onCamera});

  final MapTextureController controller;
  final void Function(MapCamera) onCamera;

  final _frameTimings = <FrameTiming>[];
  final _mapFrameTimes = <Duration>[];
  final _mapFrameIds = <int>{};
  bool _measuring = false;
  final _clock = Stopwatch()..start();

  Future<void> run() async {
    controller.frames.listen((f) {
      if (!_measuring) return;
      if (_mapFrameIds.add(f.frameId)) _mapFrameTimes.add(_clock.elapsed);
    });
    SchedulerBinding.instance.addTimingsCallback((timings) {
      if (_measuring) _frameTimings.addAll(timings);
    });

    await _waitForIdle(const Duration(seconds: 30));
    stdout.writeln('benchmark: warm-up pan');
    await _pan();
    onCamera(start);
    await _waitForIdle(const Duration(seconds: 10));

    stdout.writeln('benchmark: measuring');
    final before = controller.stats();
    _measuring = true;
    await _pan();
    _measuring = false;
    final after = controller.stats();
    stdout.writeln('BENCHMARK_RESULT ${jsonEncode(_result(before, after))}');
    await stdout.flush();
    exit(0);
  }

  Future<void> _waitForIdle(Duration timeout) => controller.events
      .firstWhere((e) => e is MapIdle)
      .timeout(timeout, onTimeout: () => const MapIdle());

  /// Changes the camera on every Flutter frame for [phaseDuration].
  Future<void> _pan() {
    final done = Completer<void>();
    final degreesPerSecond = panSpeed * 360 / (1 << start.zoom.toInt());
    Duration? first;
    void tick(Duration timestamp) {
      first ??= timestamp;
      final elapsed = timestamp - first!;
      onCamera(MapCamera(
          latitude: start.latitude,
          longitude: start.longitude +
              degreesPerSecond * elapsed.inMicroseconds / 1e6,
          zoom: start.zoom));
      if (elapsed < phaseDuration) {
        SchedulerBinding.instance.scheduleFrameCallback(tick);
      } else {
        done.complete();
      }
    }

    SchedulerBinding.instance.scheduleFrameCallback(tick);
    return done.future;
  }

  Map<String, Object> _result(MapTextureStats before, MapTextureStats after) {
    double ms(Duration d) => d.inMicroseconds / 1000;
    Map<String, double> percentiles(List<double> values) {
      values.sort();
      double p(double q) => values.isEmpty
          ? double.nan
          : values[((values.length - 1) * q).round()];
      return {'median': p(0.5), 'p95': p(0.95), 'p99': p(0.99), 'max': p(1)};
    }

    final mapIntervals = [
      for (var i = 1; i < _mapFrameTimes.length; i++)
        ms(_mapFrameTimes[i] - _mapFrameTimes[i - 1]),
    ];
    final seconds = phaseDuration.inMicroseconds / 1e6;
    final renders = after.renderUpdateCount - before.renderUpdateCount;
    final copies = after.copyCount - before.copyCount;
    return {
      'duration_s': seconds,
      'flutter_frames': _frameTimings.length,
      'flutter_frame_total_span_ms':
          percentiles([for (final t in _frameTimings) ms(t.totalSpan)]),
      'flutter_frame_build_ms':
          percentiles([for (final t in _frameTimings) ms(t.buildDuration)]),
      'flutter_frame_raster_ms':
          percentiles([for (final t in _frameTimings) ms(t.rasterDuration)]),
      'flutter_frame_interval_ms': percentiles([
        for (var i = 1; i < _frameTimings.length; i++)
          (_frameTimings[i].timestampInMicroseconds(FramePhase.vsyncStart) -
                  _frameTimings[i - 1]
                      .timestampInMicroseconds(FramePhase.vsyncStart)) /
              1000,
      ]),
      'map_frames_displayed': _mapFrameIds.length,
      'map_fps': _mapFrameIds.length / seconds,
      'map_frame_interval_ms': percentiles(mapIntervals),
      'rendered_frames': after.renderedFrames - before.renderedFrames,
      'render_update_calls': renders,
      'render_update_avg_ms': renders == 0
          ? 0
          : ms(after.renderUpdateTotal - before.renderUpdateTotal) / renders,
      'render_update_max_ms': ms(after.renderUpdateMax),
      'copy_avg_ms':
          copies == 0 ? 0 : ms(after.copyTotal - before.copyTotal) / copies,
      'skipped_renders': after.skippedRenders - before.skippedRenders,
      'waits_for_display': after.waitsForDisplay - before.waitsForDisplay,
    };
  }
}
