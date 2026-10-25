// Feature query tests at rest (feature-query spec; tasks 3.2 and 3.3 of the
// add-feature-queries change).
//
//   cd packages/test_harness && flutter test integration_test/feature_query_test.dart -d macos
//
// The style is lib/feature_query_style.dart. Positions on screen come from the
// flutter_map camera, which places a coordinate where the map draws it at
// rest (map-layer spec "Alignment at rest").
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:flutter_mapigrade/flutter_mapigrade.dart';
import 'package:flutter_mapigrade/src/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:test_harness/feature_query_style.dart';

// Narrower than every phone screen, so that the map has this size there too.
const _size = Size(360, 280);
const _center = LatLng(0, 0);
const _zoom = 12.0;

/// A map with [LayerController], displayed and at rest.
class _Map {
  _Map(this.controller, this.boundary);

  final LayerController controller;
  final GlobalKey boundary;
  final mapController = fm.MapController();
  MapTextureController? texture;
  int stylesLoaded = 0;

  /// The flutter_map camera of the displayed map frame in the last build.
  fm.MapCamera? displayedCamera;

  /// The flutter_map camera at rest.
  final camera = fm.MapCamera(
    crs: const fm.Epsg3857(),
    center: _center,
    zoom: _zoom,
    rotation: 0,
    nonRotatedSize: _size,
  );

  Offset at(LatLng point) => camera.latLngToScreenOffset(point);

  /// The color of the pixel at the logical position [p].
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
  required String style,
  LatLng center = _center,
  double rotation = 0,
  double pitch = 0,
  LayerAlignment alignment = const LayerAlignment.prediction(),
}) => MaterialApp(
  home: Align(
    alignment: Alignment.topLeft,
    child: RepaintBoundary(
      key: map.boundary,
      child: SizedBox.fromSize(
        size: _size,
        child: fm.FlutterMap(
          mapController: map.mapController,
          options: fm.MapOptions(
            initialCenter: center,
            initialZoom: _zoom,
            initialRotation: rotation,
            initialPitch: pitch,
            maxPitch: fm.MapOptions.pitchLimit,
          ),
          children: [
            MapTextureLayer(
              styleJson: style.startsWith('{') ? style : null,
              styleUrl: style.startsWith('{') ? null : style,
              alignment: alignment,
              controller: map.controller,
              onController: (texture) => map.texture = texture,
              onStyleLoaded: () => map.stylesLoaded++,
              onChildCamera: (_, camera) => map.displayedCamera = camera,
            ),
          ],
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
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Shows [style] and waits until the map is idle and displayed.
Future<_Map> _show(
  WidgetTester tester, {
  String? style,
  LatLng center = _center,
  double rotation = 0,
  double pitch = 0,
  LayerAlignment alignment = const LayerAlignment.prediction(),
}) async {
  final map = _Map(LayerController(), GlobalKey());
  await tester.pumpWidget(
    _app(
      map,
      style: style ?? featureQueryStyle(),
      center: center,
      rotation: rotation,
      pitch: pitch,
      alignment: alignment,
    ),
  );
  await _until(tester, () => map.texture != null, 'the map');
  final idle = map.texture!.events
      .firstWhere((e) => e is MapIdle)
      .timeout(const Duration(seconds: 20));
  await idle;
  await _until(
    tester,
    () => map.texture!.displayedFrame != null,
    'a displayed frame',
  );
  // The frames after idle show, and the layer rebuilds with the displayed one.
  await Future<void>.delayed(const Duration(milliseconds: 500));
  await tester.pump();
  return map;
}

Set<Object?> _ids(List<QueriedFeature> features) => {
  for (final f in features) f.id,
};

/// Logical pixels per degree of longitude at [_zoom].
final _pxPerDegree = 256 * math.pow(2, _zoom) / 360;

/// The logical position at which a map at [camera] draws [point], using the
/// copy of [point] nearest the camera's center, so that a point across the
/// antimeridian from the center stays near it. flutter_map's
/// `latLngToScreenOffset` doesn't wrap.
Offset _screenOf(fm.MapCamera camera, LatLng point) {
  Offset mercator(LatLng p) {
    final phi = p.latitude * math.pi / 180;
    return Offset(
      (p.longitude + 180) / 360,
      (1 - math.log(math.tan(math.pi / 4 + phi / 2)) / math.pi) / 2,
    );
  }

  final center = mercator(camera.center);
  final world = mercator(point);
  var dx = world.dx - center.dx;
  dx -= dx.roundToDouble();
  final d =
      Offset(dx, world.dy - center.dy) *
      (256 * math.pow(2, camera.zoom).toDouble());
  final a = camera.rotation * math.pi / 180;
  return Offset(
        math.cos(a) * d.dx - math.sin(a) * d.dy,
        math.sin(a) * d.dx + math.cos(a) * d.dy,
      ) +
      camera.nonRotatedSize.center(Offset.zero);
}

/// Whether this is the Android emulator, which renders with a software GPU
/// and so draws only a few frames per second.
Future<bool> _isAndroidEmulator() async {
  if (!Platform.isAndroid) return false;
  for (final property in ['ro.kernel.qemu', 'ro.boot.qemu']) {
    final result = await Process.run('getprop', [property]);
    if ('${result.stdout}'.trim() == '1') return true;
  }
  return false;
}

/// A camera of the moving tests: center, flutter_map zoom and rotation.
typedef _Camera = ({LatLng center, double zoom, double rotation});

/// The east offset in logical pixels at [t] seconds of a pan back and forth
/// at 1,000 logical px/s between -125 and 125.
double _panOffset(double t) {
  final s = (t * 1000) % 500;
  return s < 250 ? s - 125 : 375 - s;
}

/// Moves the camera with [cameraAt] on every Flutter frame for [duration].
/// After each frame's build, queries the route [routeId] with a radius of 2
/// at the position where the displayed map frame draws [onRoute], and 6
/// logical pixels east of the route. Returns the number of frames, the
/// queries on the route that missed it, and the queries beside the route that
/// found it.
Future<({int frames, int misses, int falseHits})> _queryWhileMoving(
  _Map map,
  _Camera Function(double t) cameraAt, {
  required LatLng onRoute,
  required int routeId,
  Duration duration = const Duration(seconds: 2),
}) async {
  final checks = <Future<(bool, bool)>>[];
  final done = Completer<void>();
  Duration? first;
  void tick(Duration timestamp) {
    first ??= timestamp;
    final elapsed = timestamp - first!;
    final c = cameraAt(elapsed.inMicroseconds / 1e6);
    map.mapController.moveAndRotate(c.center, c.zoom, c.rotation);
    SchedulerBinding.instance.addPostFrameCallback((_) {
      // The results are awaited once the motion is done; a later query would
      // still be pending when the next test disposes the map.
      if (done.isCompleted) return;
      final camera = map.displayedCamera!;
      final p = _screenOf(camera, onRoute);
      // The routes are meridians; east on screen is turned by the rotation.
      final a = camera.rotation * math.pi / 180;
      final beside = p + Offset(math.cos(a), math.sin(a)) * 6;
      Future<bool> hits(Offset at) => map.controller
          .queryRenderedFeatures(at, radius: 2, layerIds: ['routes'])
          .then((features) => _ids(features).contains(routeId));
      checks.add(
        Future.wait([hits(p), hits(beside)]).then((r) => (r[0], r[1])),
      );
    });
    if (elapsed < duration) {
      SchedulerBinding.instance.scheduleFrameCallback(tick);
    } else {
      done.complete();
    }
  }

  SchedulerBinding.instance.scheduleFrameCallback(tick);
  SchedulerBinding.instance.scheduleFrame();
  await done.future;
  final results = await Future.wait(checks);
  return (
    frames: results.length,
    misses: results.where((r) => !r.$1).length,
    falseHits: results.where((r) => r.$2).length,
  );
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  // Below the highlight lines, where only the routes cross.
  const routeLatitude = -0.02;

  group('queries at rest', () {
    testWidgets('a point query finds the route at the tap', (tester) async {
      final map = await _show(tester);
      final features = await map.controller.queryRenderedFeatures(
        map.at(const LatLng(routeLatitude, primaryRouteLongitude)),
      );
      final route = features.singleWhere((f) => f.id == 1);
      expect(route.sourceId, 'routes');
      expect(route.sourceLayerId, isNull);
      expect(route.properties, containsPair('class', 'primary'));
      expect(route.geometry['type'], anyOf('LineString', 'MultiLineString'));
      expect(route.state, isEmpty);
    });

    testWidgets('the default radius finds a thin line 6 px away, a radius of '
        '2 does not', (tester) async {
      final map = await _show(tester);
      final beside =
          map.at(const LatLng(routeLatitude, primaryRouteLongitude)) +
          const Offset(6, 0);
      expect(
        _ids(await map.controller.queryRenderedFeatures(beside)),
        contains(1),
      );
      expect(
        _ids(await map.controller.queryRenderedFeatures(beside, radius: 2)),
        isNot(contains(1)),
      );
    });

    testWidgets('a point query finds the route near the top of a map pitched '
        'at 60 degrees', (tester) async {
      final map = await _show(tester, pitch: 60);
      final camera = fm.MapCamera(
        crs: const fm.Epsg3857(),
        center: _center,
        zoom: _zoom,
        rotation: 0,
        nonRotatedSize: _size,
        pitch: 60,
      );
      final top = camera.screenOffsetToLatLng(const Offset(0, 20)).latitude;
      final onRoute = camera.latLngToScreenOffset(
        LatLng(top, primaryRouteLongitude),
      );
      expect(onRoute.dy, closeTo(20, 1));
      expect(
        _ids(await map.controller.queryRenderedFeatures(onRoute, radius: 2)),
        contains(1),
      );
    });

    testWidgets('a rectangle over the viewport finds every layer', (
      tester,
    ) async {
      final map = await _show(tester);
      final features = await map.controller.queryRenderedFeaturesInRect(
        Offset.zero & _size,
      );
      expect({
        for (final f in features) f.sourceId,
      }, containsAll(['routes', 'unnamed', 'highlights', 'pois']));
    });

    testWidgets('a rectangle outside the viewport finds nothing', (
      tester,
    ) async {
      final map = await _show(tester);
      expect(
        await map.controller.queryRenderedFeaturesInRect(
          const Rect.fromLTWH(1000, 1000, 20, 20),
        ),
        isEmpty,
      );
    });

    testWidgets('layer IDs restrict the result', (tester) async {
      final map = await _show(tester);
      final features = await map.controller.queryRenderedFeaturesInRect(
        Offset.zero & _size,
        layerIds: ['poi'],
      );
      expect(features, isNotEmpty);
      expect(features.map((f) => f.sourceId), everyElement('pois'));
      expect(features.single.properties['class'], 'cafe');
    });

    testWidgets('a filter restricts the result', (tester) async {
      final map = await _show(tester);
      final features = await map.controller.queryRenderedFeaturesInRect(
        Offset.zero & _size,
        filter: [
          '==',
          ['get', 'class'],
          'primary',
        ],
      );
      expect(features, isNotEmpty);
      expect(
        features.map((f) => f.properties['class']),
        everyElement('primary'),
      );
    });

    testWidgets('an invalid filter fails with a LayerQueryException', (
      tester,
    ) async {
      final map = await _show(tester);
      await expectLater(
        map.controller.queryRenderedFeatures(
          map.at(const LatLng(routeLatitude, primaryRouteLongitude)),
          filter: ['no-such-operator'],
        ),
        throwsA(isA<LayerQueryException>()),
      );
    });

    testWidgets('a query where only the background is drawn is empty', (
      tester,
    ) async {
      final map = await _show(tester);
      expect(
        await map.controller.queryRenderedFeatures(
          map.at(const LatLng(-0.04, -0.035)),
          radius: 2,
        ),
        isEmpty,
      );
    });

    testWidgets('queries complete in call order', (tester) async {
      final map = await _show(tester);
      final order = <String>[];
      final rect = map.controller
          .queryRenderedFeaturesInRect(Offset.zero & _size)
          .then((_) => order.add('rect'));
      final point = map.controller
          .queryRenderedFeatures(map.at(_center))
          .then((_) => order.add('point'));
      await Future.wait([rect, point]);
      expect(order, ['rect', 'point']);
    });

    testWidgets('a feature of a vector source has its source layer', (
      tester,
    ) async {
      // assets/area.pmtiles has a square in the source layer `area` around
      // this center.
      const center = LatLng(51.5, -0.12);
      final map = await _show(
        tester,
        style: 'asset://assets/style.json',
        center: center,
      );
      final features = await map.controller.queryRenderedFeatures(
        _size.center(Offset.zero),
      );
      final area = features.singleWhere((f) => f.sourceId == 'area');
      expect(area.sourceLayerId, 'area');
      expect(area.geometry['type'], anyOf('Polygon', 'MultiPolygon'));
    });
  });

  group('feature state', () {
    // On the west highlight line (ID 10) and the east one (ID 11).
    const west = LatLng(highlightLatitude, -0.03);
    const east = LatLng(highlightLatitude, 0.03);

    Future<QueriedFeature> highlightAt(_Map map, LatLng point) async {
      final features = await map.controller.queryRenderedFeatures(
        map.at(point),
        radius: 2,
        layerIds: ['highlights'],
      );
      return features.single;
    }

    Future<void> expectColor(
      WidgetTester tester,
      _Map map,
      LatLng point,
      List<int> color,
    ) => _until(
      tester,
      () async => listEquals(await map.pixelAt(map.at(point)), color),
      'the color $color at $point',
    );

    testWidgets('setting state highlights the tapped feature, and removing '
        'it restores the color', (tester) async {
      final map = await _show(tester);
      final tapped = await highlightAt(map, west);
      expect(tapped.id, 10);
      map.controller.setFeatureState(
        sourceId: tapped.sourceId,
        sourceLayerId: tapped.sourceLayerId,
        id: tapped.id,
        state: {'selected': true},
      );
      await expectColor(tester, map, west, selectedColor);
      expect(await map.pixelAt(map.at(east)), lightDefaultColor);

      map.controller.removeFeatureState(
        sourceId: tapped.sourceId,
        id: tapped.id,
        key: 'selected',
      );
      await expectColor(tester, map, west, lightDefaultColor);
    });

    testWidgets('a query returns the state, also when set with an integral '
        'double ID', (tester) async {
      final map = await _show(tester);
      map.controller.setFeatureState(
        sourceId: 'highlights',
        id: 10.0,
        state: {'selected': true},
      );
      expect((await highlightAt(map, west)).state, {'selected': true});
      expect((await highlightAt(map, east)).state, isEmpty);
    });

    testWidgets('a feature without an ID is rejected with promoteId in the '
        'message', (tester) async {
      final map = await _show(tester);
      final features = await map.controller.queryRenderedFeatures(
        map.at(const LatLng(routeLatitude, unnamedLineLongitude)),
        layerIds: ['unnamed'],
      );
      expect(features.single.id, isNull);
      expect(
        () => map.controller.setFeatureState(
          sourceId: features.single.sourceId,
          id: features.single.id,
          state: {'selected': true},
        ),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('promoteId'),
          ),
        ),
      );
    });

    testWidgets('removing the state of a source clears every feature', (
      tester,
    ) async {
      final map = await _show(tester);
      for (final id in [10, 11]) {
        map.controller.setFeatureState(
          sourceId: 'highlights',
          id: id,
          state: {'selected': true},
        );
      }
      expect((await highlightAt(map, east)).state, {'selected': true});
      map.controller.removeFeatureState(sourceId: 'highlights');
      expect((await highlightAt(map, west)).state, isEmpty);
      expect((await highlightAt(map, east)).state, isEmpty);
    });

    testWidgets('state is kept when switching from a dark to a light style', (
      tester,
    ) async {
      final map = await _show(tester, style: featureQueryStyle(dark: true));
      expect(await map.pixelAt(map.at(west)), darkDefaultColor);
      map.controller.setFeatureState(
        sourceId: 'highlights',
        id: 10,
        state: {'selected': true},
      );
      await expectColor(tester, map, west, selectedColor);

      await tester.pumpWidget(_app(map, style: featureQueryStyle()));
      await _until(tester, () => map.stylesLoaded >= 2, 'the light style');
      await expectColor(tester, map, east, lightDefaultColor);
      await expectColor(tester, map, west, selectedColor);
      expect((await highlightAt(map, west)).state, {'selected': true});
    });
  });

  group('queries while the camera moves', () {
    Future<void> expectAligned(
      _Map map,
      _Camera Function(double t) cameraAt, {
      required LatLng onRoute,
      required int routeId,
    }) async {
      final r = await _queryWhileMoving(
        map,
        cameraAt,
        onRoute: onRoute,
        routeId: routeId,
      );
      debugPrint(
        'QUERY ALIGNMENT frames ${r.frames}, misses ${r.misses}, '
        'false hits ${r.falseHits}',
      );
      // Enough frames that the camera moved between them, except on the
      // emulator, where only the misses and false hits are checked.
      expect(r.frames, greaterThan(await _isAndroidEmulator() ? 0 : 30));
      expect(r.misses, 0, reason: 'queries on the route missed it');
      expect(r.falseHits, 0, reason: 'queries 6 px beside the route found it');
    }

    _Camera pan(double t) => (
      center: LatLng(0, _panOffset(t) / _pxPerDegree),
      zoom: _zoom,
      rotation: 0,
    );

    testWidgets('a pan at 1,000 px/s with camera prediction (lead 1)', (
      tester,
    ) async {
      final map = await _show(tester);
      await expectAligned(
        map,
        pan,
        onRoute: const LatLng(routeLatitude, primaryRouteLongitude),
        routeId: 1,
      );
    });

    testWidgets('a pan at 1,000 px/s without alignment', (tester) async {
      final map = await _show(tester, alignment: LayerAlignment.none);
      await expectAligned(
        map,
        pan,
        onRoute: const LatLng(routeLatitude, primaryRouteLongitude),
        routeId: 1,
      );
    });

    testWidgets('a continuous zoom at a rotation of 30 degrees', (
      tester,
    ) async {
      final map = await _show(tester, rotation: 30);
      await expectAligned(
        map,
        (t) => (center: _center, zoom: _zoom + t / 2, rotation: 30),
        onRoute: const LatLng(-0.005, primaryRouteLongitude),
        routeId: 1,
      );
    });

    testWidgets('a pan across the antimeridian', (tester) async {
      final map = await _show(tester, center: const LatLng(0, 180));
      await expectAligned(
        map,
        (t) {
          var longitude = 180 + _panOffset(t) / _pxPerDegree;
          if (longitude > 180) longitude -= 360;
          return (center: LatLng(0, longitude), zoom: _zoom, rotation: 0);
        },
        onRoute: const LatLng(routeLatitude, antimeridianRouteLongitude),
        routeId: 3,
      );
    });
  });
}
