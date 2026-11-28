// Benchmarks of MapigradeMap (tasks 8.1 to 8.3 of the add-mapigrade-map
// change). Run in a release build:
//
//   flutter build macos --release --dart-define=MAP_BENCHMARK=true
//   open -W --env MLT_WINDOW_SIZE=1600x1000 --stdout result.txt \
//     build/macos/Build/Products/Release/test_harness.app
//
// On iOS and Android, build with the same define, launch the app as for
// benchmark.dart, and read the lines from the console. The app prints one
// line starting with MAP_BENCHMARK_RESULT per phase, then exits.
// `--dart-define=MAP_BENCHMARK_PHASES=alignment,latency,markers` selects
// phases.
//
// The map shows OpenFreeMap Liberty over central London at pitch 60, or the
// pitch of `--dart-define=MAP_BENCHMARK_PITCH=<degrees>`. A warm-up eases
// along the path and runs the motion of the `alignment` phase once, so that
// the cache holds every view that the phases show. Then:
//
// - `alignment`: the camera controller eases and flies back and forth along
//   the path. For each Flutter frame, the drawn error is the largest distance,
//   over a grid of positions on the ground, between where the frame that the
//   map chose in the build draws a coordinate (where the markers are placed)
//   and where the map frame that Flutter displayed draws it, found from the
//   display times (design D25). Android reports no display times, so there
//   the phase reports only the frame counts.
// - `latency`: 20 steps of a drag of synthetic pointer events, 600 ms apart.
//   For each step, the time from Flutter's dispatch of the move until the
//   report of the first displayed map frame whose camera moved reaches Dart
//   (on Android: the first frame that Dart chose).
// - `markers`: the same commanded pan at 500 logical px/s for 10 s, with 0,
//   100 and 1,000 upright markers: Flutter frame rate, frame build and raster
//   times, and the map's frame rate.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:latlong2/latlong.dart';
import 'package:mapigrade/mapigrade.dart';
import 'package:mapigrade/src/testing.dart';

import 'benchmark.dart' show writeLine;

const mapBenchmarkEnabled = bool.fromEnvironment('MAP_BENCHMARK');
const _phases = String.fromEnvironment('MAP_BENCHMARK_PHASES');
const _style = 'https://tiles.openfreemap.org/styles/liberty';
const _start = LatLng(51.5115, -0.14);
const _end = LatLng(51.5115, -0.06);
const _zoom = 14.0;
final _pitch = double.parse(
  const String.fromEnvironment('MAP_BENCHMARK_PITCH', defaultValue: '60'),
);

bool _selected(String phase) =>
    _phases.isEmpty || _phases.split(',').contains(phase);

/// The markers of the `markers` phase: [count] pins on a grid around the path.
List<MapigradeMarker> _markers(int count) {
  if (count == 0) return const [];
  final columns = math.sqrt(count * 4).ceil();
  final rows = (count / columns).ceil();
  return [
    for (var i = 0; i < count; ++i)
      MapigradeMarker(
        coordinate: LatLng(
          51.503 + 0.017 * (i ~/ columns) / math.max(1, rows - 1),
          -0.16 + 0.12 * (i % columns) / math.max(1, columns - 1),
        ),
        alignment: Alignment.bottomCenter,
        child: const DecoratedBox(
          decoration: BoxDecoration(
            color: Color(0xFFE53935),
            borderRadius: BorderRadius.all(Radius.circular(6)),
          ),
          child: SizedBox(width: 12, height: 18),
        ),
      ),
  ];
}

class MapBenchmarkPage extends StatefulWidget {
  const MapBenchmarkPage({super.key});

  @override
  State<MapBenchmarkPage> createState() => _MapBenchmarkPageState();
}

class _MapBenchmarkPageState extends State<MapBenchmarkPage> {
  final _mapKey = GlobalKey();
  final _camera = MapigradeCameraController();
  int _markerCount = 0;
  int _styles = 0;

  MapigradeMapState get _state => _mapKey.currentState! as MapigradeMapState;

  @override
  void initState() {
    super.initState();
    unawaited(_run());
  }

  @override
  Widget build(BuildContext context) => MapigradeMap(
    key: _mapKey,
    styleUrl: _style,
    initialCamera: MapigradeCamera(center: _start, zoom: _zoom, pitch: _pitch),
    cameraController: _camera,
    gestures: const MapigradeGestures(glides: false),
    onStyleLoaded: () => _styles++,
    children: [MapigradeMarkers(markers: _markers(_markerCount))],
  );

  Future<void> _until(bool Function() condition) async {
    while (!condition()) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }

  Future<void> _rest(Duration quiet) async {
    // The map is at rest once no frame finished for [quiet].
    var last = DateTime.now();
    final sub = _state.map!.readyFrames.listen((_) => last = DateTime.now());
    await _until(() => DateTime.now().difference(last) > quiet);
    await sub.cancel();
  }

  Future<void> _run() async {
    await _until(() => _mapKey.currentState != null);
    await _until(() => _state.map != null && _styles > 0);
    final size = _state.displayedFrame?.size;
    writeLine(
      'MAP_BENCHMARK_CONDITIONS ${jsonEncode({'platform': Platform.operatingSystem, 'viewport': size == null ? null : '${size.width.round()}x${size.height.round()}', 'pitch': _pitch, 'thermal_state': thermalStateForTesting()})}',
    );
    await _rest(const Duration(seconds: 3));
    writeLine('map benchmark: warm-up');
    await _await(
      _camera.easeTo(
        const MapigradeCamera(center: _end),
        duration: const Duration(seconds: 12),
      ),
    );
    await _await(_camera.jumpTo(const MapigradeCamera(center: _start)));
    await _alignmentMotion();
    await _rest(const Duration(seconds: 3));

    if (_selected('alignment')) await _alignment();
    if (_selected('latency')) await _latency();
    if (_selected('markers')) {
      for (final count in [0, 100, 1000]) {
        setState(() => _markerCount = count);
        await _await(_camera.jumpTo(const MapigradeCamera(center: _start)));
        await _rest(const Duration(seconds: 2));
        await _markersPhase(count);
      }
    }
    writeLine('MAP_BENCHMARK_END thermal_state=${thermalStateForTesting()}');
    await stdout.flush();
    exit(0);
  }

  Future<T> _await<T>(Future<T> future) => future;

  // The positions whose drawn error is measured: a grid over the lower
  // two-thirds of the map, where the pitched frame draws ground.
  List<Offset> _grid(Size size) => [
    for (var y = 1; y <= 3; ++y)
      for (var x = 1; x <= 3; ++x)
        Offset(size.width * x / 4, size.height * (0.3 + 0.2 * y)),
  ];

  /// The commanded motion of the `alignment` phase, which the warm-up also
  /// runs, so that the cache holds every view it shows.
  Future<void> _alignmentMotion() async {
    for (var i = 0; i < 2; ++i) {
      await _camera.easeTo(
        const MapigradeCamera(center: _end, bearing: 30),
        duration: const Duration(seconds: 4),
      );
      await _camera.easeTo(
        const MapigradeCamera(center: _start, bearing: 0),
        duration: const Duration(seconds: 4),
      );
    }
    await _camera.flyTo(
      const MapigradeCamera(center: _end, zoom: 13),
      duration: const Duration(seconds: 4),
    );
    await _camera.flyTo(
      const MapigradeCamera(center: _start, zoom: _zoom),
      duration: const Duration(seconds: 4),
    );
  }

  Future<void> _alignment() async {
    writeLine('map benchmark: phase alignment');
    final map = _state.map!;
    final frames = <int, FrameCamera>{};
    final displays = <({int id, int time})>[];
    final builds = <int, int>{};
    final timings = <FrameTiming>[];
    var recording = true;
    final ready = map.readyFrames.listen((f) => frames[f.frameId] = f);
    final shown = map.frames.listen((f) {
      if (recording && f.displayTime != null) {
        displays.add((id: f.frameId, time: f.displayTime!));
      }
    });
    void onTimings(List<FrameTiming> t) => timings.addAll(t);
    SchedulerBinding.instance.addTimingsCallback(onTimings);
    var listening = true;
    void onBuild(Duration _) {
      if (!listening) return;
      if (recording) {
        final chosen = map.selectedFrame;
        if (chosen != null) {
          builds[PlatformDispatcher.instance.frameData.frameNumber] =
              chosen.frameId;
        }
      }
      SchedulerBinding.instance.addPostFrameCallback(onBuild);
    }

    SchedulerBinding.instance.addPostFrameCallback(onBuild);
    final stopwatch = Stopwatch()..start();
    await _alignmentMotion();
    final seconds = stopwatch.elapsedMicroseconds / 1e6;
    recording = false;
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    listening = false;
    SchedulerBinding.instance.removeTimingsCallback(onTimings);
    await ready.cancel();
    await shown.cancel();

    final errors = <double>[];
    var withoutFrame = 0;
    // The Flutter frames of the motion, up to the last recorded build.
    final lastBuild = builds.keys.fold(0, math.max);
    timings.removeWhere((t) => t.frameNumber > lastBuild);
    if (displays.isNotEmpty) {
      timings.sort((a, b) => a.frameNumber.compareTo(b.frameNumber));
      displays.sort((a, b) => a.time.compareTo(b.time));
      var di = 0;
      int? shownId;
      int? lastChosen;
      for (final t in timings) {
        final finish = t.timestampInMicroseconds(FramePhase.rasterFinish);
        while (di < displays.length && displays[di].time <= finish) {
          shownId = displays[di++].id;
        }
        lastChosen = builds[t.frameNumber] ?? lastChosen;
        if (shownId == null || lastChosen == null) continue;
        final a = frames[lastChosen], b = frames[shownId];
        final chosenFrame = a == null ? null : MapigradeFrameInternals.fromFrame(a);
        final shownFrame = b == null ? null : MapigradeFrameInternals.fromFrame(b);
        if (chosenFrame == null || shownFrame == null) {
          withoutFrame++;
          continue;
        }
        var error = 0.0;
        for (final p in _grid(chosenFrame.size)) {
          final c = chosenFrame.unproject(p);
          final q = c == null ? null : shownFrame.project(c);
          if (q != null) error = math.max(error, (q - p).distance);
        }
        errors.add(error);
      }
    }
    writeLine(
      'MAP_BENCHMARK_RESULT ${jsonEncode({
        'phase': 'alignment',
        'duration_s': seconds,
        'flutter_frames': timings.length,
        'map_frames_ready': frames.length,
        'display_events': displays.length,
        if (displays.isEmpty) 'error_drawn_px': 'not measured: no display times',
        if (displays.isNotEmpty) ...{'frames_measured': errors.length, 'frames_without_map_frame': withoutFrame, 'frames_over_1px': errors.where((e) => e > 1).length, 'error_drawn_px': _percentiles(errors)},
        'thermal_state_end': thermalStateForTesting(),
      })}',
    );
  }

  Future<void> _latency() async {
    writeLine('map benchmark: phase latency');
    final map = _state.map!;
    final clock = Stopwatch()..start();
    int? sentAt;
    MapCamera? before;
    final latencies = <double>[];
    final sub = map.frames.listen((f) {
      final sent = sentAt;
      final camera = before;
      if (sent == null || camera == null) return;
      if (f.camera.longitude != camera.longitude ||
          f.camera.latitude != camera.latitude) {
        latencies.add((clock.elapsedMicroseconds - sent) / 1000);
        sentAt = null;
      }
    });
    final size = _state.displayedFrame!.size;
    var position = Offset(size.width * 0.3, size.height * 0.7);
    const pointer = 7;
    void dispatch(PointerEvent event) =>
        GestureBinding.instance.handlePointerEvent(event);
    final start = clock.elapsed;
    Duration stamp() => clock.elapsed - start;
    dispatch(
      PointerDownEvent(
        pointer: pointer,
        position: position,
        timeStamp: stamp(),
      ),
    );
    // Past the pan slop, so that the map has won the pointer.
    for (var i = 0; i < 5; ++i) {
      position += const Offset(10, 0);
      dispatch(
        PointerMoveEvent(
          pointer: pointer,
          position: position,
          timeStamp: stamp(),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 16));
    }
    await Future<void>.delayed(const Duration(milliseconds: 600));
    for (var i = 0; i < 20; ++i) {
      before = map.displayedFrame?.camera ?? map.selectedFrame?.camera;
      position += const Offset(8, 0);
      sentAt = clock.elapsedMicroseconds;
      dispatch(
        PointerMoveEvent(
          pointer: pointer,
          position: position,
          timeStamp: stamp(),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 600));
    }
    dispatch(
      PointerUpEvent(pointer: pointer, position: position, timeStamp: stamp()),
    );
    await sub.cancel();
    writeLine(
      'MAP_BENCHMARK_RESULT ${jsonEncode({'phase': 'latency', 'steps': 20, 'measured': latencies.length, 'until': Platform.isAndroid ? 'frame chosen by Dart' : 'frame displayed', 'latency_ms': _percentiles(latencies), 'thermal_state_end': thermalStateForTesting()})}',
    );
  }

  Future<void> _markersPhase(int count) async {
    writeLine('map benchmark: phase markers $count');
    final map = _state.map!;
    final timings = <FrameTiming>[];
    void onTimings(List<FrameTiming> t) => timings.addAll(t);
    var mapFrames = 0;
    var panning = true;
    final ready = map.readyFrames.listen((_) {
      if (panning) mapFrames++;
    });
    // The Flutter frames built during the pan; timings arrive later.
    final built = <int>{};
    SchedulerBinding.instance.addTimingsCallback(onTimings);
    // Each Flutter frame jumps the camera east at 500 logical px/s.
    const pxPerSecond = 500.0;
    final degreesPerSecond = pxPerSecond / (512 * math.pow(2, _zoom)) * 360;
    final done = Completer<void>();
    Duration? first;
    void tick(Duration timestamp) {
      first ??= timestamp;
      final t = (timestamp - first!).inMicroseconds / 1e6;
      if (t >= 10) {
        panning = false;
        done.complete();
        return;
      }
      built.add(PlatformDispatcher.instance.frameData.frameNumber);
      _camera.jumpTo(
        MapigradeCamera(
          center: LatLng(
            _start.latitude,
            _start.longitude + degreesPerSecond * t,
          ),
        ),
      );
      SchedulerBinding.instance.scheduleFrameCallback(tick);
    }

    SchedulerBinding.instance.scheduleFrameCallback(tick);
    await done.future;
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    SchedulerBinding.instance.removeTimingsCallback(onTimings);
    await ready.cancel();
    final measured = [
      for (final t in timings)
        if (built.contains(t.frameNumber)) t,
    ];
    double ms(Duration d) => d.inMicroseconds / 1000;
    writeLine(
      'MAP_BENCHMARK_RESULT ${jsonEncode({
        'phase': 'markers',
        'markers': count,
        'duration_s': 10,
        'flutter_fps': measured.length / 10,
        'map_fps': mapFrames / 10,
        'build_ms': _percentiles([for (final t in measured) ms(t.buildDuration)]),
        'raster_ms': _percentiles([for (final t in measured) ms(t.rasterDuration)]),
        'thermal_state_end': thermalStateForTesting(),
      })}',
    );
  }
}

Map<String, double>? _percentiles(List<double> values) {
  if (values.isEmpty) return null;
  values.sort();
  double p(double q) => values[((values.length - 1) * q).round()];
  double r(double v) => (v * 100).round() / 100;
  return {'p50': r(p(0.5)), 'p90': r(p(0.9)), 'max': r(p(1))};
}
