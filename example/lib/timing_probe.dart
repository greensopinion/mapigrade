// Probe for the timing assumptions of the alignment measurement (tasks 1.1
// and 1.2, designs D24 and D25). Run in a profile or release build:
//
//   flutter run -d macos --profile --dart-define=TIMING_PROBE=true
//
// Waits for the style, pans for [probeDuration] as the benchmark does, and
// prints one line starting with TIMING_PROBE_RESULT:
//
// - display_in_raster: the fraction of displayed map frames whose display
//   time lies between rasterStart and rasterFinish of a FrameTiming (1.1).
// - build_matches: for each Flutter frame build, how many FrameTimings have a
//   vsyncStart equal to the build's currentSystemFrameTimeStamp (1.2).
// - build_frame_number_matches: the same, by the engine's frame number
//   (PlatformDispatcher.frameData.frameNumber and FrameTiming.frameNumber),
//   and for those pairs currentSystemFrameTimeStamp minus vsyncStart. The
//   engine passes the vsync target time to beginFrame, not the vsync start.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/scheduler.dart';
import 'package:flutter_mapigrade/flutter_mapigrade.dart';

import 'benchmark.dart' show panSpeed, start;

const timingProbeEnabled = bool.fromEnvironment('TIMING_PROBE');
const probeDuration = Duration(seconds: 10);

class TimingProbe {
  TimingProbe(this.controller, {required this.onCamera});

  final MapTextureController controller;
  final void Function(MapCamera) onCamera;

  final _buildVsyncs = <int>[];
  final _buildFrameNumbers = <int>[];
  final _timings = <FrameTiming>[];
  final _displayTimes = <int>[];
  bool _recording = false;
  bool _collectTimings = false;

  Future<void> run() async {
    controller.frames.listen((f) {
      if (_recording) _displayTimes.add(f.displayTime);
    });
    SchedulerBinding.instance.addTimingsCallback((timings) {
      if (_collectTimings) _timings.addAll(timings);
    });
    SchedulerBinding.instance.addPersistentFrameCallback((_) {
      if (!_recording) return;
      _buildVsyncs.add(
        SchedulerBinding.instance.currentSystemFrameTimeStamp.inMicroseconds,
      );
      _buildFrameNumbers.add(PlatformDispatcher.instance.frameData.frameNumber);
    });

    await controller.events
        .firstWhere((e) => e is MapIdle)
        .timeout(const Duration(seconds: 30), onTimeout: () => const MapIdle());
    stdout.writeln('timing probe: panning');
    _recording = _collectTimings = true;
    await _pan();
    _recording = false;
    // FrameTimings arrive in batches, up to 1 s after the frame.
    await Future<void>.delayed(const Duration(seconds: 2));
    _collectTimings = false;
    stdout.writeln('TIMING_PROBE_RESULT ${jsonEncode(_result())}');
    await stdout.flush();
    exit(0);
  }

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
        zoom: start.zoom,
      ));
      if (elapsed < probeDuration) {
        SchedulerBinding.instance.scheduleFrameCallback(tick);
      } else {
        done.complete();
      }
    }

    SchedulerBinding.instance.scheduleFrameCallback(tick);
    return done.future;
  }

  Map<String, Object> _result() {
    int at(FrameTiming t, FramePhase p) => t.timestampInMicroseconds(p);
    final rasters = [
      for (final t in _timings)
        (at(t, FramePhase.rasterStart), at(t, FramePhase.rasterFinish)),
    ];

    // 1.1: display times inside a raster interval. For the others, the
    // signed distance in µs to the nearest interval, to tell a clock offset
    // from occasional misses.
    var inside = 0;
    final misses = <int>[];
    for (final d in _displayTimes) {
      var best = 1 << 62;
      var hit = false;
      for (final (s, f) in rasters) {
        if (d >= s && d <= f) {
          hit = true;
          break;
        }
        final dist = d < s ? d - s : d - f;
        if (dist.abs() < best.abs()) best = dist;
      }
      if (hit) {
        inside++;
      } else {
        misses.add(best);
      }
    }
    misses.sort();

    // 1.2: FrameTimings per build with an equal vsync timestamp.
    final vsyncCounts = <int, int>{};
    for (final t in _timings) {
      final v = at(t, FramePhase.vsyncStart);
      vsyncCounts[v] = (vsyncCounts[v] ?? 0) + 1;
    }
    final matchHistogram = <String, int>{};
    final nearestDiffs = <int>[];
    for (final b in _buildVsyncs) {
      final n = vsyncCounts[b] ?? 0;
      matchHistogram['$n'] = (matchHistogram['$n'] ?? 0) + 1;
      if (n == 0 && _timings.isNotEmpty) {
        var best = 1 << 62;
        for (final v in vsyncCounts.keys) {
          if ((b - v).abs() < best.abs()) best = b - v;
        }
        nearestDiffs.add(best);
      }
    }
    nearestDiffs.sort();
    final buildSet = _buildVsyncs.toSet();

    final timingsByNumber = <int, List<FrameTiming>>{};
    for (final t in _timings) {
      (timingsByNumber[t.frameNumber] ??= []).add(t);
    }
    final numberHistogram = <String, int>{};
    final targetMinusStart = <int>[];
    for (var i = 0; i < _buildFrameNumbers.length; i++) {
      final matches = timingsByNumber[_buildFrameNumbers[i]] ?? const [];
      numberHistogram['${matches.length}'] =
          (numberHistogram['${matches.length}'] ?? 0) + 1;
      if (matches.length == 1) {
        targetMinusStart
            .add(_buildVsyncs[i] - at(matches.single, FramePhase.vsyncStart));
      }
    }
    targetMinusStart.sort();
    final buildNumberSet = _buildFrameNumbers.toSet();

    List<int> sample(List<int> sorted) => sorted.isEmpty
        ? const []
        : [for (final q in [0.0, 0.1, 0.5, 0.9, 1.0])
            sorted[((sorted.length - 1) * q).round()]];

    return {
      'platform': Platform.operatingSystem,
      'display_events': _displayTimes.length,
      'display_in_raster': _displayTimes.isEmpty
          ? 0
          : inside / _displayTimes.length,
      'display_miss_us_min_p10_p50_p90_max': sample(misses),
      'frame_timings': _timings.length,
      'builds': _buildVsyncs.length,
      'build_matches': matchHistogram,
      'unmatched_build_nearest_diff_us_min_p10_p50_p90_max':
          sample(nearestDiffs),
      'frame_timings_without_build': vsyncCounts.keys
          .where((v) => !buildSet.contains(v))
          .length,
      'build_frame_number_matches': numberHistogram,
      'frame_timings_without_build_by_number':
          timingsByNumber.keys.where((n) => !buildNumberSet.contains(n)).length,
      'build_vsync_minus_timing_vsync_us_min_p10_p50_p90_max':
          sample(targetMinusStart),
      'example_build_vsync_us': _buildVsyncs.isEmpty ? 0 : _buildVsyncs.first,
      'example_timing_vsync_us':
          _timings.isEmpty ? 0 : at(_timings.first, FramePhase.vsyncStart),
      'example_display_us': _displayTimes.isEmpty ? 0 : _displayTimes.first,
    };
  }
}
