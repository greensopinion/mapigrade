import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:mapigrade/src/camera_projection.dart';
import 'package:mapigrade/src/map/camera.dart';
import 'package:mapigrade/src/map/mapigrade_frame.dart';
import 'package:mapigrade/src/map/mapigrade_map.dart';
import 'package:mapigrade/src/map/markers.dart';

import 'fake_map_controller.dart';
import 'test_matrix.dart';

const _size = Size(400, 600);
const _center = LatLng(48.2, 16.37);

void main() {
  late FakeMapController map;
  var frameId = 0;

  setUp(() {
    map = FakeMapController();
    debugCreateMapigradeMap = ({
      required pixelRatio,
      required httpHeaders,
      required initialCamera,
      required limits,
    }) async => map;
  });
  tearDown(() => debugCreateMapigradeMap = null);

  Future<void> pumpMarkers(
    WidgetTester tester,
    List<MapigradeMarker> markers,
  ) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: MediaQuery(
          data: const MediaQueryData(size: Size(800, 800)),
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox.fromSize(
              size: _size,
              child: MapigradeMap(
                styleJson: '{}',
                initialCamera: const MapigradeCamera(center: _center, zoom: 14),
                children: [MapigradeMarkers(markers: markers)],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Future<MapigradeFrame> show(
    WidgetTester tester, {
    LatLng center = _center,
    double zoom = 14,
    double bearing = 0,
    double pitch = 0,
  }) async {
    map.finish(
      fakeFrame(
        id: ++frameId,
        latitude: center.latitude,
        longitude: center.longitude,
        zoom: zoom,
        bearing: bearing,
        pitch: pitch,
        logicalSize: _size,
        matrix: testMatrix(
          center: center,
          zoom: zoom,
          size: _size,
          bearing: bearing,
          pitch: pitch,
        ),
      ),
    );
    await tester.pump();
    return tester
        .state<MapigradeMapState>(find.byType(MapigradeMap))
        .displayedFrame!;
  }

  RenderMapigradeMarkers markersOf(WidgetTester tester) =>
      tester.renderObject(find.byType(MapigradeMarkers));

  RenderBox boxOf(WidgetTester tester, Key key) =>
      tester.renderObject<RenderBox>(find.byKey(key));

  Offset at(WidgetTester tester, Key key, Offset local) =>
      boxOf(tester, key).localToGlobal(local);

  group('placement', () {
    testWidgets('a child isn\'t rebuilt while frames change, and follows '
        'them', (tester) async {
      var builds = 0;
      const key = Key('pin');
      await pumpMarkers(tester, [
        MapigradeMarker(
          coordinate: const LatLng(48.201, 16.371),
          alignment: Alignment.bottomCenter,
          child: Builder(
            builder: (context) {
              builds++;
              return const SizedBox(key: key, width: 20, height: 30);
            },
          ),
        ),
      ]);
      for (var i = 0; i < 5; ++i) {
        final frame = await show(
          tester,
          center: LatLng(48.2, 16.37 + i * 0.001),
          pitch: 10.0 * i,
          bearing: 5.0 * i,
        );
        final expected = frame.project(const LatLng(48.201, 16.371))!;
        final bottomCenter = at(tester, key, const Offset(10, 30));
        expect((bottomCenter - expected).distance, lessThan(0.5));
        expect(boxOf(tester, key).size, const Size(20, 30));
      }
      expect(builds, 1);
    });

    testWidgets('overlapping markers paint in order of distance', (
      tester,
    ) async {
      const near = Key('near'), far = Key('far');
      await pumpMarkers(tester, [
        const MapigradeMarker(
          coordinate: LatLng(48.1995, 16.37),
          child: SizedBox(key: near, width: 200, height: 200),
        ),
        const MapigradeMarker(
          coordinate: LatLng(48.2005, 16.37),
          child: SizedBox(key: far, width: 200, height: 200),
        ),
      ]);
      await show(tester, pitch: 60);
      final painted = markersOf(tester).paintedChildren;
      expect(painted, hasLength(2));
      expect(painted.first, same(boxOf(tester, far)));
      expect(painted.last, same(boxOf(tester, near)));
    });

    testWidgets('perspective scaling shrinks far upright markers', (
      tester,
    ) async {
      const constNear = Key('constNear'), constFar = Key('constFar');
      const scaledNear = Key('scaledNear'), scaledFar = Key('scaledFar');
      MapigradeMarker marker(Key key, LatLng at, bool scaled) =>
          MapigradeMarker(
            coordinate: at,
            scaleWithPerspective: scaled,
            child: SizedBox(key: key, width: 20, height: 20),
          );
      const nearPoint = LatLng(48.197, 16.37), farPoint = LatLng(48.206, 16.37);
      await pumpMarkers(tester, [
        marker(constNear, nearPoint, false),
        marker(constFar, farPoint, false),
        marker(scaledNear, nearPoint, true),
        marker(scaledFar, farPoint, true),
      ]);
      await show(tester, pitch: 60);
      double width(Key key) =>
          (at(tester, key, const Offset(20, 0)) - at(tester, key, Offset.zero))
              .distance;
      expect(width(constNear), closeTo(20, 1e-6));
      expect(width(constFar), closeTo(20, 1e-6));
      expect(width(scaledFar), lessThan(width(scaledNear)));
    });

    testWidgets('a marker is drawn once, in the copy nearest the center', (
      tester,
    ) async {
      const key = Key('pin');
      await pumpMarkers(tester, [
        const MapigradeMarker(
          coordinate: LatLng(0, -179),
          child: SizedBox(key: key, width: 10, height: 10),
        ),
      ]);
      await show(tester, center: const LatLng(0, 179), zoom: 6);
      expect(markersOf(tester).paintedChildren, hasLength(1));
      expect(at(tester, key, const Offset(5, 5)).dx, greaterThan(200));
    });
  });

  group('alignment with the map', () {
    testWidgets('a ground marker\'s corners are the projections of its ground '
        'corners, and a tap on it reaches its child', (tester) async {
      const key = Key('arrow');
      var taps = 0;
      const coordinate = LatLng(48.199, 16.371);
      await pumpMarkers(tester, [
        MapigradeMarker(
          coordinate: coordinate,
          pitchAlignment: MarkerAlignment.map,
          rotationAlignment: MarkerAlignment.map,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => taps++,
            child: const SizedBox(key: key, width: 40, height: 20),
          ),
        ),
      ]);
      final frame = await show(tester, bearing: 90, pitch: 60);
      final world = mercator(coordinate.latitude, coordinate.longitude);
      final unit = 1 / worldSize(14);
      for (final corner in const [
        Offset(0, 0),
        Offset(40, 0),
        Offset(40, 20),
        Offset(0, 20),
      ]) {
        // The center of the child is at the coordinate; east is the child's
        // right and south its down.
        final groundWorld = world + (corner - const Offset(20, 10)) * unit;
        final ground = _latLngOf(groundWorld);
        final expected = frame.project(ground)!;
        expect(
          (at(tester, key, corner) - expected).distance,
          lessThan(0.5),
          reason: '$corner',
        );
      }
      // Pointing to north at bearing 90 is pointing left, and the pitch
      // shortens it.
      final top = at(tester, key, const Offset(20, 0));
      final bottom = at(tester, key, const Offset(20, 20));
      expect(top.dx, lessThan(bottom.dx));
      await tester.tapAt(frame.project(coordinate)!);
      expect(taps, 1);
    });

    testWidgets('an upright marker with rotation alignment map turns with '
        'the bearing', (tester) async {
      const key = Key('pin');
      await pumpMarkers(tester, [
        const MapigradeMarker(
          coordinate: _center,
          rotationAlignment: MarkerAlignment.map,
          child: SizedBox(key: key, width: 20, height: 40),
        ),
      ]);
      await show(tester, bearing: 90, pitch: 60);
      final top = at(tester, key, const Offset(10, 0));
      final bottom = at(tester, key, const Offset(10, 40));
      // The top points to the map's north, which is to the left.
      expect(top.dx, lessThan(bottom.dx - 39));
      expect((top.dy - bottom.dy).abs(), lessThan(1e-6));
    });
  });

  group('hidden markers', () {
    testWidgets('a marker behind the camera or off screen isn\'t painted or '
        'hit, and keeps its State', (tester) async {
      var taps = 0;
      await pumpMarkers(tester, [
        MapigradeMarker(
          coordinate: const LatLng(48.2, 16.4),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => taps++,
            child: const _Counter(),
          ),
        ),
        const MapigradeMarker(
          coordinate: LatLng(40, 16.37),
          child: SizedBox(width: 10, height: 10),
        ),
      ]);
      var frame = await show(tester, center: const LatLng(48.2, 16.4));
      expect(markersOf(tester).paintedChildren, hasLength(1));
      final state = tester.state<_CounterState>(find.byType(_Counter));
      // Behind the camera at pitch 80.
      frame = await show(tester, center: const LatLng(48.2, 16.4), pitch: 80);
      expect(frame.project(const LatLng(40, 16.37)), isNull);
      expect(markersOf(tester).paintedChildren, hasLength(1));
      // Off screen to the west.
      frame = await show(tester, center: const LatLng(48.2, 16.3));
      expect(markersOf(tester).paintedChildren, isEmpty);
      final hidden = frame.project(const LatLng(48.2, 16.4))!;
      await tester.tapAt(Offset(399, hidden.dy));
      expect(taps, 0);
      // Back on screen: the same State, and hit again.
      frame = await show(tester, center: const LatLng(48.2, 16.4));
      expect(tester.state<_CounterState>(find.byType(_Counter)), same(state));
      expect(state.inits, 1);
      await tester.tapAt(frame.project(const LatLng(48.2, 16.4))!);
      expect(taps, 1);
    });

    testWidgets('a marker beyond the ground that the frame draws isn\'t '
        'drawn', (tester) async {
      await pumpMarkers(tester, [
        const MapigradeMarker(
          coordinate: LatLng(70, 16.37),
          child: SizedBox(width: 10, height: 10),
        ),
      ]);
      final frame = await show(tester, pitch: 85);
      expect(frame.withinDepth(frame.clipOf(const LatLng(70, 16.37))), isFalse);
      expect(markersOf(tester).paintedChildren, isEmpty);
    });
  });
}

LatLng _latLngOf(Offset world) {
  final n = math.pi - 2 * math.pi * world.dy;
  return LatLng(
    180 / math.pi * math.atan(0.5 * (math.exp(n) - math.exp(-n))),
    world.dx * 360 - 180,
  );
}

class _Counter extends StatefulWidget {
  const _Counter();

  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  int inits = 0;

  @override
  void initState() {
    super.initState();
    inits++;
  }

  @override
  Widget build(BuildContext context) => const SizedBox(width: 30, height: 30);
}
