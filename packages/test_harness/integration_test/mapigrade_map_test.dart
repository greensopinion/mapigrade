// Integration tests of MapigradeMap (tasks 7.1 and 7.2 of the
// add-mapigrade-map change): the camera, its commands, limits and streams,
// markers and the frame projection, polylines and feature queries, driven by
// the camera controller, and a few tests from gesture to camera.
//
//   cd packages/test_harness && flutter test integration_test/mapigrade_map_test.dart -d macos
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:mapigrade/mapigrade.dart';
import 'package:mapigrade/src/testing.dart';
import 'package:test_harness/feature_query_style.dart';

// Narrower than every phone screen, so that the map has this size there too.
const _size = Size(360, 400);
const _center = LatLng(0, 0);

const _plainStyle =
    '{"version": 8, "sources": {}, "layers": [{"id": "background", '
    '"type": "background", "paint": {"background-color": "#ffffff"}}]}';

class _Map {
  final camera = MapigradeCameraController();
  final controller = MapigradeController();
  final boundary = GlobalKey();
  final taps = <MapigradeTap>[];
  final errors = <MapigradeException>[];
  int stylesLoaded = 0;

  MapigradeMapState state(WidgetTester tester) =>
      tester.state<MapigradeMapState>(find.byType(MapigradeMap));

  MapigradeFrame frame(WidgetTester tester) => state(tester).displayedFrame!;

  MapTextureController texture(WidgetTester tester) => state(tester).map!;

  Future<List<int>> pixelAt(Offset p) async {
    final boundary =
        this.boundary.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
    final image = await boundary.toImage();
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    final o = (p.dy.floor() * image.width + p.dx.floor()) * 4;
    return [bytes.getUint8(o), bytes.getUint8(o + 1), bytes.getUint8(o + 2)];
  }
}

Widget _app(
  _Map map, {
  String style = _plainStyle,
  MapigradeCamera initial = const MapigradeCamera(center: _center, zoom: 14),
  CameraLimits? limits,
  MapigradeGestures gestures = const MapigradeGestures(),
  List<Widget> children = const [],
}) => MaterialApp(
  home: Align(
    alignment: Alignment.topLeft,
    child: RepaintBoundary(
      key: map.boundary,
      child: SizedBox.fromSize(
        size: _size,
        child: MapigradeMap(
          styleJson: style,
          initialCamera: initial,
          limits: limits,
          gestures: gestures,
          controller: map.controller,
          cameraController: map.camera,
          onTap: map.taps.add,
          onError: map.errors.add,
          onStyleLoaded: () => map.stylesLoaded++,
          children: children,
        ),
      ),
    ),
  ),
);

/// Pumps until [condition] holds, for at most 20 seconds.
Future<void> _until(
  WidgetTester tester,
  FutureOr<bool> Function() condition,
  String what,
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 20));
  while (!await condition()) {
    if (DateTime.now().isAfter(deadline)) fail('timed out waiting for $what');
    await tester.pump(const Duration(milliseconds: 20));
  }
}

/// Pumps [app] and waits until the map has loaded its style and displayed a
/// frame. The map's events can come before a test could subscribe to them, so
/// the wait for the style uses the widget's callback.
Future<_Map> _show(WidgetTester tester, _Map map, Widget app) async {
  await tester.pumpWidget(app);
  await _until(tester, () => map.stylesLoaded > 0, 'the style');
  await _until(
    tester,
    () => map.state(tester).displayedFrame != null,
    'a displayed frame',
  );
  await _settle(tester);
  return map;
}

/// Pumps for a while, so that the frames after a change are displayed.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 25; ++i) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

/// Pumps until [future] completes.
Future<T> _await<T>(WidgetTester tester, Future<T> future, String what) async {
  T? value;
  var done = false;
  unawaited(
    future.then((v) {
      value = v;
      done = true;
    }),
  );
  await _until(tester, () => done, what);
  return value as T;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('camera', () {
    testWidgets('the first frame has the initial camera', (tester) async {
      final map = _Map();
      await _show(
        tester,
        map,
        _app(
          map,
          initial: const MapigradeCamera(
            center: _center,
            zoom: 14,
            bearing: 30,
            pitch: 45,
            roll: 10,
            fieldOfView: 50,
          ),
        ),
      );
      final camera = map.frame(tester).camera;
      expect(camera.zoom, closeTo(14, 0.001));
      expect(camera.bearing, closeTo(30, 0.001));
      expect(camera.pitch, closeTo(45, 0.001));
      expect(camera.roll, closeTo(10, 0.001));
      expect(camera.fieldOfView, closeTo(50, 0.001));
      expect(map.camera.camera, camera);
    });

    testWidgets('padding moves the center', (tester) async {
      final map = _Map();
      await _show(
        tester,
        map,
        _app(
          map,
          initial: const MapigradeCamera(
            center: _center,
            zoom: 14,
            padding: EdgeInsets.only(top: 200),
          ),
        ),
      );
      final p = map.frame(tester).project(_center)!;
      expect(p.dy, closeTo(_size.height / 2 + 100, 0.5));
      expect(p.dx, closeTo(_size.width / 2, 0.5));
    });

    testWidgets('the frame projection matches MapLibre\'s projection', (
      tester,
    ) async {
      final map = _Map();
      await _show(
        tester,
        map,
        _app(
          map,
          initial: const MapigradeCamera(
            center: LatLng(48.2, 16.37),
            zoom: 14,
            bearing: 30,
            pitch: 60,
          ),
        ),
      );
      final frame = map.frame(tester);
      for (final c in const [
        LatLng(48.2, 16.37),
        LatLng(48.205, 16.375),
        LatLng(48.197, 16.36),
        LatLng(48.21, 16.38),
      ]) {
        final mine = frame.project(c)!;
        final theirs = map
            .texture(tester)
            .projectForTesting(c.latitude, c.longitude)!;
        expect((mine - theirs).distance, lessThan(0.1), reason: '$c');
      }
    });

    testWidgets('commands complete with their outcomes', (tester) async {
      final map = _Map();
      await _show(tester, map, _app(map));
      final jump = await _await(
        tester,
        map.camera.jumpTo(const MapigradeCamera(zoom: 12)),
        'the jump',
      );
      expect(jump, CameraTransitionOutcome.completed);
      await _settle(tester);
      expect(map.frame(tester).camera.zoom, closeTo(12, 1e-6));

      final ease = map.camera.easeTo(
        const MapigradeCamera(zoom: 16),
        duration: const Duration(seconds: 5),
      );
      await _settle(tester);
      map.camera.cancelTransitions();
      expect(
        await _await(tester, ease, 'the ease'),
        CameraTransitionOutcome.cancelled,
      );

      final route = [
        const LatLng(0.01, -0.02),
        const LatLng(-0.015, 0.01),
        const LatLng(0.005, 0.03),
      ];
      final fit = await _await(
        tester,
        map.camera.fitBounds(
          GeoBounds.fromPoints(route),
          padding: const EdgeInsets.all(20),
        ),
        'the fit',
      );
      expect(fit, CameraTransitionOutcome.completed);
      await _settle(tester);
      final frame = map.frame(tester);
      for (final point in route) {
        final p = frame.project(point)!;
        expect(p.dx, inInclusiveRange(19, _size.width - 19), reason: '$point');
        expect(p.dy, inInclusiveRange(19, _size.height - 19), reason: '$point');
      }
    });

    testWidgets('limits hold the camera', (tester) async {
      final map = _Map();
      await _show(
        tester,
        map,
        _app(
          map,
          initial: const MapigradeCamera(center: _center, zoom: 14, pitch: 45),
        ),
      );
      await tester.pumpWidget(
        _app(
          map,
          initial: const MapigradeCamera(center: _center, zoom: 14, pitch: 45),
          limits: CameraLimits(
            maxPitch: 30,
            bounds: GeoBounds(
              const LatLng(-0.01, -0.01),
              const LatLng(0.01, 0.01),
            ),
          ),
        ),
      );
      await _settle(tester);
      expect(map.frame(tester).camera.pitch, closeTo(30, 0.001));
      await _await(
        tester,
        map.camera.jumpTo(
          const MapigradeCamera(center: LatLng(1, 1), pitch: 60),
        ),
        'the jump',
      );
      await _settle(tester);
      final camera = map.frame(tester).camera;
      expect(camera.pitch, closeTo(30, 0.001));
      expect(camera.center!.latitude, lessThanOrEqualTo(0.01 + 1e-9));
      expect(camera.center!.longitude, lessThanOrEqualTo(0.01 + 1e-9));
    });

    testWidgets('an ease reports command changes and one rest', (tester) async {
      final map = _Map();
      await _show(tester, map, _app(map));
      final changes = <CameraChange>[];
      final rests = <MapigradeCamera>[];
      final subscriptions = [
        map.camera.cameraChanges.listen(changes.add),
        map.camera.rests.listen(rests.add),
      ];
      await _await(
        tester,
        map.camera.easeTo(
          const MapigradeCamera(zoom: 15),
          duration: const Duration(milliseconds: 500),
        ),
        'the ease',
      );
      await _until(tester, () => rests.isNotEmpty, 'a rest');
      await _settle(tester);
      for (final s in subscriptions) {
        await s.cancel();
      }
      expect(changes.length, greaterThan(2));
      expect(
        changes.map((c) => c.source),
        everyElement(CameraChangeSource.command),
      );
      expect(rests, hasLength(1));
      expect(rests.single.zoom, closeTo(15, 1e-6));
    });
  });

  group('children', () {
    testWidgets('a marker is at the coordinate where MapLibre draws it under '
        'pitch, and a marker behind the camera is hidden', (tester) async {
      final map = _Map();
      const pin = Key('pin');
      const coordinate = LatLng(0.002, 0.001);
      await _show(
        tester,
        map,
        _app(
          map,
          initial: const MapigradeCamera(center: _center, zoom: 14, pitch: 45),
          children: [
            MapigradeMarkers(
              markers: const [
                MapigradeMarker(
                  coordinate: coordinate,
                  alignment: Alignment.bottomCenter,
                  child: SizedBox(key: pin, width: 20, height: 30),
                ),
                MapigradeMarker(
                  coordinate: LatLng(-5, 0),
                  child: SizedBox(width: 20, height: 30),
                ),
              ],
            ),
          ],
        ),
      );
      final box = tester.renderObject<RenderBox>(find.byKey(pin));
      final drawn = box.localToGlobal(const Offset(10, 30));
      final theirs = map
          .texture(tester)
          .projectForTesting(coordinate.latitude, coordinate.longitude)!;
      expect((drawn - theirs).distance, lessThan(1));
      await _await(
        tester,
        map.camera.jumpTo(const MapigradeCamera(pitch: 80)),
        'the jump',
      );
      await _settle(tester);
      final markers = tester.renderObject<RenderMapigradeMarkers>(
        find.byType(MapigradeMarkers),
      );
      expect(markers.paintedChildren, [box]);
    });

    testWidgets('a polyline is drawn at its coordinates under pitch', (
      tester,
    ) async {
      final map = _Map();
      await _show(
        tester,
        map,
        _app(
          map,
          initial: const MapigradeCamera(center: _center, zoom: 14, pitch: 45),
          children: [
            MapigradePolylineLayer(
              polylines: [
                MapigradePolyline(
                  points: const [LatLng(-0.002, 0), LatLng(0.002, 0)],
                  color: const Color(0xFFFF0000),
                  strokeWidth: 6,
                ),
              ],
            ),
          ],
        ),
      );
      await _settle(tester);
      final p = map.frame(tester).project(const LatLng(0.0005, 0))!;
      final c = await map.pixelAt(p);
      expect(c[0], greaterThan(200), reason: '$c');
      expect(c[1], lessThan(80), reason: '$c');
    });

    testWidgets('a feature query finds the road at its position under pitch', (
      tester,
    ) async {
      final map = _Map();
      await _show(
        tester,
        map,
        _app(
          map,
          style: featureQueryStyle(),
          initial: const MapigradeCamera(center: _center, zoom: 12, pitch: 45),
        ),
      );
      final p = map
          .frame(tester)
          .project(const LatLng(0.003, primaryRouteLongitude))!;
      final features = await _await(
        tester,
        map.controller.queryRenderedFeatures(p),
        'the query',
      );
      expect(features.map((f) => f.id), contains(1));
    });
  });

  group('gestures', () {
    const noGlides = MapigradeGestures(glides: false, doubleTapZoom: false);

    testWidgets('a drag pans by its distance on the ground', (tester) async {
      final map = _Map();
      await _show(tester, map, _app(map, gestures: noGlides));
      const start = Offset(180, 250), end = Offset(240, 210);
      final grabbed = map.frame(tester).unproject(start)!;
      final gesture = await tester.startGesture(start);
      for (var i = 1; i <= 20; ++i) {
        await gesture.moveTo(
          Offset.lerp(start, end, i / 20)!,
          timeStamp: Duration(milliseconds: 16 * i),
        );
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up(timeStamp: const Duration(milliseconds: 400));
      await _settle(tester);
      final p = map.frame(tester).project(grabbed)!;
      expect((p - end).distance, lessThan(1));
    });

    testWidgets('a pinch zooms by its scale', (tester) async {
      final map = _Map();
      await _show(tester, map, _app(map, gestures: noGlides));
      final zoom = map.frame(tester).camera.zoom!;
      final a = await tester.startGesture(const Offset(130, 200), pointer: 1);
      final b = await tester.startGesture(const Offset(230, 200), pointer: 2);
      for (var i = 1; i <= 20; ++i) {
        final t = Duration(milliseconds: 16 * i);
        await a.moveTo(Offset(130 - 2.5 * i, 200), timeStamp: t);
        await b.moveTo(Offset(230 + 2.5 * i, 200), timeStamp: t);
        await tester.pump(const Duration(milliseconds: 16));
      }
      await a.up(timeStamp: const Duration(milliseconds: 400));
      await b.up(timeStamp: const Duration(milliseconds: 400));
      await _settle(tester);
      // The fingers went from 100 to 200 logical pixels apart. The recognizer
      // decides whether two fingers tilt once both have moved 2 pixels, and
      // that first step of 2.5 pixels each doesn't zoom, so the zoom follows
      // the spread from 105 to 200 pixels.
      expect(
        map.frame(tester).camera.zoom,
        closeTo(zoom + math.log(200 / 105) / math.ln2, 0.01),
      );
    });

    testWidgets('a tap reports the coordinate that the displayed frame draws '
        'at its position', (tester) async {
      final map = _Map();
      await _show(
        tester,
        map,
        _app(
          map,
          gestures: noGlides,
          initial: const MapigradeCamera(center: _center, zoom: 14, pitch: 45),
        ),
      );
      const at = Offset(150, 260);
      await tester.tapAt(at);
      await _settle(tester);
      final tap = map.taps.single;
      expect(tap.position, at);
      final theirs = map
          .texture(tester)
          .projectForTesting(
            tap.coordinate!.latitude,
            tap.coordinate!.longitude,
          )!;
      expect((theirs - at).distance, lessThan(1));
    });
  });
}
