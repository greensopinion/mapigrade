// Frame rate measurement (task 7.4, design D10). Run in a release build:
//
//   flutter build macos --release --dart-define=BENCHMARK=true
//   MLT_WINDOW_SIZE=1600x1000 build/macos/Build/Products/Release/<app>/Contents/MacOS/<app>
//
// Pans continuously at a fixed zoom over central London (see [start]) for
// 30 s to load and cache the area, goes back to the start, waits for idle,
// then pans the same path again for 30 s and measures. Prints one line
// starting with BENCHMARK_RESULT and exits.
//
// On iOS (design D17), run a release build and read the line from the console:
//
//   flutter build ios --release --dart-define=BENCHMARK=true
//   xcrun devicectl device install app --device <device> build/ios/iphoneos/Runner.app
//   xcrun devicectl device process launch --device <device> --console \
//     org.maplibre.flutterMapMaplibreTextureExample
//
// With --dart-define=BENCHMARK_SUSTAINED_S=<seconds>, the measured pass
// instead pans back and forth over the warm-up path for that many seconds,
// and the result line (BENCHMARK_SUSTAINED_RESULT) has the map frame rate and
// the thermal state for each 30 s interval.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/scheduler.dart';
import 'package:flutter_map_maplibre_texture/flutter_map_maplibre_texture.dart';
import 'package:flutter_map_maplibre_texture/testing.dart';

const benchmarkEnabled = bool.fromEnvironment('BENCHMARK');
const phaseDuration = Duration(seconds: 30);
const sustainedDuration =
    Duration(seconds: int.fromEnvironment('BENCHMARK_SUSTAINED_S'));
const sustainedInterval = Duration(seconds: 30);
/// Central London, panning east from Charing Cross through Covent Garden, the
/// City, Whitechapel and Limehouse: dense streets, buildings and labels along
/// the whole path, so that the measurement covers the expensive case.
const start = MapCamera(latitude: 51.5115, longitude: -0.14, zoom: 14);

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
  Duration _measureStart = Duration.zero;

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

    if (sustainedDuration > Duration.zero) {
      await _runSustained();
      return;
    }

    stdout.writeln('benchmark: measuring');
    final before = controller.stats();
    _measureStart = _clock.elapsed;
    _measuring = true;
    await _pan();
    _measuring = false;
    final after = controller.stats();
    stdout.writeln('BENCHMARK_RESULT ${jsonEncode(_result(before, after))}');
    await stdout.flush();
    exit(0);
  }

  /// Pans back and forth over the warm-up path for [sustainedDuration] and
  /// reports the displayed map frame rate and the thermal state for each
  /// [sustainedInterval].
  Future<void> _runSustained() async {
    stdout.writeln(
        'benchmark: sustained pan for ${sustainedDuration.inSeconds} s');
    final measureStart = _measureStart = _clock.elapsed;
    final thermal = [thermalStateForTesting()];
    final timer = Timer.periodic(
        sustainedInterval, (_) => thermal.add(thermalStateForTesting()));
    final before = controller.stats();
    _measuring = true;
    await _pan(duration: sustainedDuration, backAndForth: true);
    _measuring = false;
    timer.cancel();
    final after = controller.stats();
    final intervals = (sustainedDuration.inMicroseconds /
            sustainedInterval.inMicroseconds)
        .ceil();
    final framesPerInterval = List.filled(intervals, 0);
    for (final t in _mapFrameTimes) {
      final i = (t - measureStart).inMicroseconds ~/
          sustainedInterval.inMicroseconds;
      if (i >= 0 && i < intervals) framesPerInterval[i]++;
    }
    final result = {
      'duration_s': sustainedDuration.inSeconds,
      'interval_s': sustainedInterval.inSeconds,
      'map_fps_per_interval': [
        for (final n in framesPerInterval) n / sustainedInterval.inSeconds,
      ],
      'map_fps_per_second': _perSecondFps(sustainedDuration),
      'thermal_state_per_interval_start': thermal,
      'thermal_state_end': thermalStateForTesting(),
      'map_frames_displayed': _mapFrameIds.length,
      'skipped_renders': after.skippedRenders - before.skippedRenders,
    };
    stdout.writeln('BENCHMARK_SUSTAINED_RESULT ${jsonEncode(result)}');
    await stdout.flush();
    exit(0);
  }

  /// Percentiles of the displayed map frame rate over each whole second of
  /// the measured pass, which an average over the pass hides. p10 is the low
  /// end: 10% of seconds had that many frames or fewer.
  Map<String, num> _perSecondFps(Duration duration) {
    final counts = List.filled(duration.inSeconds, 0);
    for (final t in _mapFrameTimes) {
      final second = (t - _measureStart).inMicroseconds ~/ 1000000;
      if (second >= 0 && second < counts.length) counts[second]++;
    }
    final sorted = [...counts]..sort();
    int p(double q) => sorted[((sorted.length - 1) * q).round()];
    return {'min': sorted.first, 'p10': p(0.1), 'p50': p(0.5), 'p90': p(0.9)};
  }

  Future<void> _waitForIdle(Duration timeout) => controller.events
      .firstWhere((e) => e is MapIdle)
      .timeout(timeout, onTimeout: () => const MapIdle());

  /// Changes the camera on every Flutter frame for [duration] (default
  /// [phaseDuration]), panning east, or with [backAndForth] east for
  /// [phaseDuration] and back west, repeatedly.
  Future<void> _pan(
      {Duration duration = phaseDuration, bool backAndForth = false}) {
    final done = Completer<void>();
    final degreesPerSecond = panSpeed * 360 / (1 << start.zoom.toInt());
    Duration? first;
    void tick(Duration timestamp) {
      first ??= timestamp;
      final elapsed = timestamp - first!;
      var seconds = elapsed.inMicroseconds / 1e6;
      if (backAndForth) {
        final leg = phaseDuration.inMicroseconds / 1e6;
        final phase = seconds % (2 * leg);
        seconds = phase <= leg ? phase : 2 * leg - phase;
      }
      onCamera(MapCamera(
          latitude: start.latitude,
          longitude: start.longitude + degreesPerSecond * seconds,
          zoom: start.zoom));
      if (elapsed < duration) {
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
      'map_fps_per_second': _perSecondFps(phaseDuration),
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
