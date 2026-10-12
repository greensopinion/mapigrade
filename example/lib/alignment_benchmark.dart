// Alignment benchmark (tasks 5.2 and 5.3 of the flutter-map-layer change,
// designs D25, D26 and D28). Run in a release build:
//
//   flutter build macos --release --dart-define=ALIGNMENT_BENCHMARK=true
//   MLT_WINDOW_SIZE=1600x1000 build/macos/Build/Products/Release/<app>/Contents/MacOS/<app>
//
// On iOS, build with the same define and read the lines from the console, as
// for benchmark.dart.
//
// Shows the map as the base layer of a FlutterMap over central London, warms
// up the tile cache, then runs each phase: pans at 100, 500, 1,000 and 2,000
// logical px/s, zoom at 1 level per second, rotation at 90 degrees per
// second, and the motions of design D35 of the camera-prediction change:
// `stop` (pan for 1 s, rest for 1 s), `fling` (pan for 1 s, then
// flutter_map's fling, in 3 s cycles, over 1.5 times the phase duration) and
// `reverse` (reversing every 1 s), at 1,000 px/s. For these, the result line
// gives `motion_changes` and `overshoot_px`, the p50 and largest over the
// motion changes of the largest drawn error in each change's window, and
// `overshoot_ahead_px`, the same for the largest distance at the viewport
// center by which the map is ahead of the overlays in the direction of
// motion before the change (0 if it isn't ahead). The
// camera moves through the MapController on every Flutter frame,
// as a gesture would. Each phase prints one line starting with
// ALIGNMENT_RESULT; then the app exits.
//
// `--dart-define=ALIGNMENT_PHASE_S=<seconds>` sets the phase duration
// (default 20), `--dart-define=ALIGNMENT_PHASES=pan100,zoom` runs only the
// named phases.
//
// `--dart-define=ALIGNMENT_MODE=<mode>` configures the layer (design D34 of
// the camera-prediction change): `transform` (the default here, so that
// earlier procedures still measure the transform; the layer's own default is
// `predict1`), `none` (no transform, no prediction), or `predict1`,
// `predict2`, `predict3` (camera prediction with a lead of that many refresh
// intervals). Each result line
// states the mode and gives `error_drawn_px`, the error of what the layer
// draws: with the transform in `transform` mode, without it otherwise. Pan
// phases also give `offset_along_pan_px`, the mean signed distance at the
// viewport center between the drawn map and the overlays along the pan:
// positive when the map shows the camera further along the pan than the
// overlays, negative when it lags behind them.
//
// `--dart-define=ALIGNMENT_VIDEO=true` is the screen capture check (design
// D29): a JSON style draws a grid of red discs, a CircleLayer draws a blue
// dot at the center of each, and the run is 5 s at rest followed by the pan
// at 1,000 px/s, without warm-up. The capture tool in
// example/tool/alignment_capture.swift measures the distance between discs
// and dots in the window.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_map/flutter_map.dart' hide MapCamera;
import 'package:flutter_mapigrade/flutter_mapigrade.dart';
import 'package:flutter_mapigrade/testing.dart';
import 'package:latlong2/latlong.dart';

import 'alignment_mode.dart';
import 'alignment_motion.dart';
import 'benchmark.dart' show copyFree, start;

const alignmentBenchmarkEnabled = bool.fromEnvironment('ALIGNMENT_BENCHMARK');
const alignmentPhaseDuration = Duration(
  seconds: int.fromEnvironment('ALIGNMENT_PHASE_S', defaultValue: 20),
);
const alignmentPhases = String.fromEnvironment('ALIGNMENT_PHASES');
const alignmentVideo = bool.fromEnvironment('ALIGNMENT_VIDEO');
const alignmentModeName = String.fromEnvironment(
  'ALIGNMENT_MODE',
  defaultValue: 'transform',
);

/// The layer configuration, or null if ALIGNMENT_MODE names none.
final alignmentMode = AlignmentMode.byLabel(alignmentModeName);

/// The flutter_map version in pubspec.yaml, for the result lines.
const flutterMapVersion = '8.3.2';

const libertyStyleUrl = 'https://tiles.openfreemap.org/styles/liberty';

/// The benchmark's start: the start of benchmark.dart, at the flutter_map
/// zoom that converts to its MapLibre zoom.
final startCenter = LatLng(start.latitude, start.longitude);
final startZoom = start.zoom + 1;

/// Pans go back and forth over this many logical pixels east of the start,
/// so that every speed stays in the area that the warm-up loaded.
const panPathPx = 3000.0;

/// One phase of the benchmark: the camera as a function of the time since
/// the phase started.
class Phase {
  const Phase(
    this.name,
    this.kind,
    this.speed,
    this.camera, {
    this.duration,
    this.changes,
  });
  final String name;
  final String kind;

  /// The phase's duration, if not [alignmentPhaseDuration].
  final Duration? duration;

  /// Logical px/s for pans, zoom levels/s for zoom, degrees/s for rotation.
  final double speed;
  final ({LatLng center, double zoom, double rotation}) Function(double t)
  camera;

  /// The motion changes whose windows end within a phase of the given
  /// duration in seconds, for the phases that report overshoot.
  final List<MotionChange> Function(double duration)? changes;
}

/// A triangle wave from 0 up to [amplitude] and back, moving at [speed].
double triangle(double t, double speed, double amplitude) {
  final d = (t * speed) % (2 * amplitude);
  return d <= amplitude ? d : 2 * amplitude - d;
}

/// The camera [east] logical pixels east of the start, on the pan path.
({LatLng center, double zoom, double rotation}) panCamera(double east) {
  final pxPerDegree = 256 * math.pow(2, startZoom) / 360;
  return (
    center: LatLng(
      startCenter.latitude,
      startCenter.longitude + east / pxPerDegree,
    ),
    zoom: startZoom,
    rotation: 0.0,
  );
}

Phase pan(double pxPerSecond) => Phase(
  'pan${pxPerSecond.round()}',
  'pan',
  pxPerSecond,
  (t) => panCamera(triangle(t, pxPerSecond, panPathPx)),
);

/// The phases with motion changes, for a viewport whose shorter side is
/// [shorterSide] logical pixels, which a fling covers.
List<Phase> motionPhases(double shorterSide) {
  Phase phase(String name, Motion motion, {Duration? duration}) => Phase(
    name,
    name,
    motionSpeed,
    (t) => panCamera(motion.east(t)),
    duration: duration,
    changes: motion.changes,
  );
  return [
    phase('stop', stopMotion()),
    phase(
      'fling',
      flingMotion(Fling(shorterSide)),
      duration: alignmentPhaseDuration * 1.5,
    ),
    phase('reverse', reverseMotion()),
  ];
}

final phases = [
  pan(100),
  pan(500),
  pan(1000),
  pan(2000),
  // Zoom in and out by one level around the start zoom.
  Phase(
    'zoom',
    'zoom',
    1,
    (t) => (
      center: startCenter,
      zoom: startZoom - 1 + triangle(t + 1, 1, 2),
      rotation: 0.0,
    ),
  ),
  Phase(
    'rotate',
    'rotate',
    90,
    (t) => (center: startCenter, zoom: startZoom, rotation: 90 * t % 360),
  ),
];

/// The phases of the screen capture check: at rest, then the pan at
/// 1,000 px/s.
final videoPhases = [
  Phase(
    'rest',
    'rest',
    0,
    (t) => (center: startCenter, zoom: startZoom, rotation: 0.0),
    duration: const Duration(seconds: 5),
  ),
  pan(1000),
];

/// The coordinates of the video mode's grid: every 150 logical px over the
/// pan path and one viewport around it.
final videoGrid = () {
  const crs = Epsg3857();
  final origin = crs.latLngToOffset(startCenter, startZoom);
  return [
    for (var x = -900.0; x <= panPathPx + 900; x += 150)
      for (var y = -600.0; y <= 600; y += 150)
        crs.offsetToLatLng(origin + Offset(x, y), startZoom),
  ];
}();

/// A white style with a red disc at each grid coordinate.
String videoStyle() => jsonEncode({
  'version': 8,
  'sources': {
    'grid': {
      'type': 'geojson',
      'data': {
        'type': 'FeatureCollection',
        'features': [
          for (final p in videoGrid)
            {
              'type': 'Feature',
              'properties': {},
              'geometry': {
                'type': 'Point',
                'coordinates': [p.longitude, p.latitude],
              },
            },
        ],
      },
    },
  },
  'layers': [
    {
      'id': 'background',
      'type': 'background',
      'paint': {'background-color': '#ffffff'},
    },
    {
      'id': 'discs',
      'type': 'circle',
      'source': 'grid',
      'paint': {'circle-radius': 20, 'circle-color': '#ff0000'},
    },
  ],
});

class AlignmentBenchmarkPage extends StatefulWidget {
  const AlignmentBenchmarkPage({super.key});

  @override
  State<AlignmentBenchmarkPage> createState() => _AlignmentBenchmarkPageState();
}

class _AlignmentBenchmarkPageState extends State<AlignmentBenchmarkPage> {
  final _mapController = MapController();
  final _mode = alignmentMode ?? AlignmentMode.transform;

  void _onController(MapTextureController controller) {
    // Start after the first build, when the MapController is attached.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => AlignmentBenchmark(controller, _mapController).run(),
    );
  }

  @override
  Widget build(BuildContext context) => FlutterMap(
    mapController: _mapController,
    options: MapOptions(
      initialCenter: startCenter,
      initialZoom: startZoom,
      interactionOptions: const InteractionOptions(flags: InteractiveFlag.none),
    ),
    children: [
      if (alignmentVideo) ...[
        MapLibreTextureLayer(
          styleJson: videoStyle(),
          copyFree: copyFree,
          alignment: _mode.alignment,
          onController: _onController,
        ),
        CircleLayer(
          circles: [
            for (final p in videoGrid)
              CircleMarker(point: p, radius: 3, color: const Color(0xff0000ff)),
          ],
        ),
      ] else ...[
        MapLibreTextureLayer(
          styleUrl: libertyStyleUrl,
          copyFree: copyFree,
          alignment: _mode.alignment,
          onController: _onController,
        ),
        MarkerLayer(
          markers: [
            for (final p in const [
              LatLng(51.5080, -0.1247),
              LatLng(51.5138, -0.0984),
              LatLng(51.5081, -0.0759),
            ])
              Marker(
                point: p,
                width: 16,
                height: 16,
                child: const ColoredBox(color: Colors.orange),
              ),
          ],
        ),
      ],
    ],
  );
}

/// The p50, p95 and largest of [values], rounded to 0.01, or null if
/// [values] is empty. Sorts [values].
Map<String, double>? percentiles(List<double> values) {
  if (values.isEmpty) return null;
  values.sort();
  double p(double q) => values[((values.length - 1) * q).round()];
  double r(double v) => (v * 100).round() / 100;
  return {'p50': r(p(0.5)), 'p95': r(p(0.95)), 'max': r(p(1))};
}

/// What the layer used in one Flutter frame build.
class _Build {
  const _Build(this.target, this.usedId, this.used, this.time, this.east);
  final ViewCamera target;
  final int? usedId;
  final ViewCamera? used;

  /// The frame's vsync target time since the phase started, in seconds.
  final double time;

  /// The sign of the target's longitude change since the previous build:
  /// 1 eastwards, -1 westwards, 0 unchanged.
  final double east;
}

/// A map frame that Flutter took for display.
class DisplayedMapFrame {
  const DisplayedMapFrame(this.id, this.view, this.time);
  final int id;
  final ViewCamera view;
  final int time;
}

/// Records builds, frame timings and display events during a phase, and
/// matches them afterwards (design D25).
class AlignmentRecorder {
  AlignmentRecorder(this.initiallyShown);

  /// The map frame displayed when recording started, which Flutter shows
  /// until it takes a newer one.
  final DisplayedMapFrame? initiallyShown;
  final builds = <int, _Build>{};

  /// The vsync target time of the phase's first frame.
  Duration? start;

  /// The target of the last recorded build.
  ViewCamera? lastTarget;

  /// The per-frame drawn errors from the last [analyze].
  final frameErrors = <FrameError>[];
  final timings = <FrameTiming>[];
  final displays = <DisplayedMapFrame>[];
  bool recording = false;
  bool collectingTimings = false;

  /// Matches the records and computes the error of every Flutter frame that
  /// showed a map frame.
  Map<String, Object?> analyze(
    Duration duration, {
    required bool transformDrawn,
    required bool pan,
  }) {
    final sorted = [...timings]
      ..sort((a, b) => a.frameNumber.compareTo(b.frameNumber));
    final events = [...displays]..sort((a, b) => a.time.compareTo(b.time));
    var di = 0;
    var shown = initiallyShown;
    _Build? lastBuild;
    var matchedBuilds = 0;
    var rasterOnly = 0;
    var noShownFrame = 0;
    var displaysOutsideRaster = 0;
    var mismatched = 0;
    final withT = <double>[];
    final withoutT = <double>[];
    final drawn = <double>[];
    final alongPan = <double>[];
    frameErrors.clear();
    final timingNumbers = <int>{};
    for (final t in sorted) {
      timingNumbers.add(t.frameNumber);
      final rasterStart = t.timestampInMicroseconds(FramePhase.rasterStart);
      final rasterFinish = t.timestampInMicroseconds(FramePhase.rasterFinish);
      while (di < events.length && events[di].time <= rasterFinish) {
        if (events[di].time < rasterStart) displaysOutsideRaster++;
        shown = events[di];
        di++;
      }
      final build = builds[t.frameNumber];
      if (build != null) {
        lastBuild = build;
      } else {
        // Flutter rasterized the last layer tree again, for example because
        // only the texture changed. The screen shows the last build's camera
        // and transform.
        if (lastBuild == null) continue;
        rasterOnly++;
      }
      if (shown == null) {
        if (build != null) noShownFrame++;
        continue;
      }
      if (build != null) matchedBuilds++;
      if (lastBuild.usedId != shown.id) mismatched++;
      final error = alignmentError(
        target: lastBuild.target,
        used: lastBuild.used,
        shown: shown.view,
      );
      withT.add(error.withTransform);
      withoutT.add(error.withoutTransform);
      final drawnError = transformDrawn
          ? error.withTransform
          : error.withoutTransform;
      drawn.add(drawnError);
      final center = transformDrawn
          ? error.centerWithTransform
          : error.centerWithoutTransform;
      frameErrors.add((
        time: lastBuild.time,
        error: drawnError,
        centerDx: center.dx,
      ));
      // The pans move east or west at bearing 0. A map behind the overlays
      // draws their center coordinate on the side the camera moves to.
      if (pan && lastBuild.east != 0) alongPan.add(-center.dx * lastBuild.east);
    }
    final buildsWithoutTiming = builds.keys
        .where((n) => !timingNumbers.contains(n))
        .length;

    final frames = withT.length;
    return {
      'builds': builds.length,
      'matched_builds': matchedBuilds,
      'matched_fraction': builds.isEmpty ? 0 : matchedBuilds / builds.length,
      'builds_without_timing': buildsWithoutTiming,
      'builds_without_shown_frame': noShownFrame,
      'raster_only_frames': rasterOnly,
      'frames': frames,
      'mismatch_fraction': frames == 0 ? 0 : mismatched / frames,
      'display_events': displays.length,
      // Each display event is a new map frame that Flutter took.
      'map_fps': displays.length / (duration.inMicroseconds / 1e6),
      'display_events_outside_raster': displaysOutsideRaster,
      'error_with_transform_px': percentiles(withT),
      'error_without_transform_px': percentiles(withoutT),
      'error_drawn_px': percentiles(drawn),
      if (pan)
        'offset_along_pan_px': alongPan.isEmpty
            ? null
            : (alongPan.reduce((a, b) => a + b) / alongPan.length * 100)
                      .round() /
                  100,
    };
  }
}

class AlignmentBenchmark {
  AlignmentBenchmark(this.controller, this.mapController);

  final MapTextureController controller;
  final MapController mapController;
  AlignmentRecorder? _recorder;

  Future<void> run() async {
    if (alignmentMode == null) {
      stderr.writeln(
        'ALIGNMENT_MODE=$alignmentModeName is not one of '
        '${AlignmentMode.values.map((m) => m.label).join(', ')}',
      );
      await stderr.flush();
      exit(2);
    }
    final mode = alignmentMode!;
    controller.frames.listen((f) {
      final r = _recorder;
      if (r != null && r.recording) {
        r.displays.add(
          DisplayedMapFrame(f.frameId, ViewCamera.ofFrame(f), f.displayTime),
        );
      }
    });
    SchedulerBinding.instance.addTimingsCallback((timings) {
      final r = _recorder;
      if (r != null && r.collectingTimings) r.timings.addAll(timings);
    });
    // Runs after the build of every frame, so the layer has set its
    // transform from displayedFrame, and the overlays have used the camera.
    SchedulerBinding.instance.addPersistentFrameCallback((_) {
      final r = _recorder;
      if (r == null || !r.recording) return;
      final used = controller.displayedFrame;
      final target = viewCameraOf(mapController.camera);
      final now = SchedulerBinding.instance.currentSystemFrameTimeStamp;
      final start = r.start ??= now;
      final previous = r.lastTarget;
      r.lastTarget = target;
      r.builds[PlatformDispatcher.instance.frameData.frameNumber] = _Build(
        target,
        used?.frameId,
        used == null ? null : ViewCamera.ofFrame(used),
        (now - start).inMicroseconds / 1e6,
        previous == null
            ? 0
            : _wrapDegrees(target.camera.longitude - previous.camera.longitude)
                  .sign,
      );
    });

    final selected = alignmentVideo
        ? videoPhases
        : [
            for (final p in [
              ...phases,
              ...motionPhases(mapController.camera.nonRotatedSize.shortestSide),
            ])
              if (alignmentPhases.isEmpty ||
                  alignmentPhases.split(',').contains(p.name))
                p,
          ];
    stdout.writeln(
      'ALIGNMENT_CONDITIONS ${jsonEncode({'mode': mode.label, 'platform': Platform.operatingSystem, 'flutter_map': flutterMapVersion, 'viewport': '${mapController.camera.nonRotatedSize.width.round()}x'
          '${mapController.camera.nonRotatedSize.height.round()}', 'phase_s': alignmentPhaseDuration.inSeconds, 'copy_free': copyFree, 'thermal_state': thermalStateForTesting()})}',
    );

    // The video mode's style has no tiles, and its idle event can come
    // before this waits for it.
    const short = Duration(seconds: 3);
    await _waitForIdle(alignmentVideo ? short : const Duration(seconds: 30));
    stdout.writeln('alignment benchmark: map idle');
    if (!alignmentVideo) await _warmUp();

    for (final phase in selected) {
      _moveTo(phase.camera(0));
      await _waitForIdle(alignmentVideo ? short : const Duration(seconds: 10));
      stdout.writeln('alignment benchmark: phase ${phase.name}');
      final duration = phase.duration ?? alignmentPhaseDuration;
      final initial = controller.displayedFrame;
      final recorder = _recorder =
          AlignmentRecorder(
              initial == null
                  ? null
                  : DisplayedMapFrame(
                      initial.frameId,
                      ViewCamera.ofFrame(initial),
                      0,
                    ),
            )
            ..recording = true
            ..collectingTimings = true;
      await _move(phase, duration);
      recorder.recording = false;
      // FrameTimings arrive in batches, up to about 1 s after the frame.
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      recorder.collectingTimings = false;
      _recorder = null;
      final result = recorder.analyze(
        duration,
        transformDrawn: mode == AlignmentMode.transform,
        pan: phase.kind == 'pan',
      );
      final changes = phase.changes?.call(duration.inMicroseconds / 1e6);
      final overshoot = changes == null
          ? null
          : overshoots(recorder.frameErrors, changes);
      final ahead = changes == null
          ? null
          : overshootsAhead(recorder.frameErrors, changes);
      stdout.writeln(
        'ALIGNMENT_RESULT ${jsonEncode({
          'mode': mode.label,
          'phase': phase.name,
          'kind': phase.kind,
          'speed': phase.speed,
          'speed_unit': switch (phase.kind) {
            'pan' => 'logical px/s',
            'zoom' => 'zoom levels/s',
            'rotate' => 'degrees/s',
            'stop' || 'fling' || 'reverse' => 'logical px/s',
            _ => 'none',
          },
          'duration_s': duration.inMicroseconds / 1e6,
          'viewport': '${mapController.camera.nonRotatedSize.width.round()}x'
              '${mapController.camera.nonRotatedSize.height.round()}',
          ...result,
          if (overshoot != null) ...{'motion_changes': overshoot.length, 'overshoot_px': percentiles(overshoot), 'overshoot_ahead_px': percentiles(ahead!)},
          'thermal_state_end': thermalStateForTesting(),
        })}',
      );
    }
    await stdout.flush();
    exit(0);
  }

  /// Runs every kind of camera change, so that the tile cache holds the
  /// area of the phases.
  Future<void> _warmUp() async {
    stdout.writeln('alignment benchmark: warm-up');
    for (final phase in phases.where(
      (p) => p.name == 'pan500' || p.kind != 'pan',
    )) {
      await _move(phase, const Duration(seconds: 6));
    }
    _moveTo(phases.first.camera(0));
    await _waitForIdle(const Duration(seconds: 15));
  }

  void _moveTo(({LatLng center, double zoom, double rotation}) c) =>
      mapController.moveAndRotate(c.center, c.zoom, c.rotation);

  /// Moves the camera on every Flutter frame for [duration].
  Future<void> _move(Phase phase, Duration duration) {
    final done = Completer<void>();
    Duration? first;
    void tick(Duration timestamp) {
      first ??= timestamp;
      // The phase's time 0, in the clock of the recorded builds; frame
      // callbacks get the timestamp relative to an epoch instead.
      _recorder?.start ??=
          SchedulerBinding.instance.currentSystemFrameTimeStamp;
      final elapsed = timestamp - first!;
      _moveTo(phase.camera(elapsed.inMicroseconds / 1e6));
      if (elapsed < duration) {
        SchedulerBinding.instance.scheduleFrameCallback(tick);
      } else {
        done.complete();
      }
    }

    SchedulerBinding.instance.scheduleFrameCallback(tick);
    return done.future;
  }

  /// [degrees] moved into [-180, 180) by whole turns.
  static double _wrapDegrees(double degrees) => (degrees + 180) % 360 - 180;

  Future<void> _waitForIdle(Duration timeout) => controller.events
      .firstWhere((e) => e is MapIdle)
      .timeout(timeout, onTimeout: () => const MapIdle());
}
