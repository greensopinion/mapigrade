import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:mapigrade/mapigrade.dart';
import 'package:mapigrade/src/map/mapigrade_frame.dart';
import 'package:mapigrade/src/map/mapigrade_map.dart';
import 'package:mapigrade/src/texture/map_texture_controller.dart';

import 'fake_map_controller.dart';
import 'test_matrix.dart';

void main() {
  late FakeMapController map;
  late List<({NativeCamera camera, NativeLimits limits})> creations;
  late List<MapigradeException> errors;

  setUp(() {
    map = FakeMapController();
    creations = [];
    errors = [];
    debugCreateMapigradeMap =
        ({
          required pixelRatio,
          required httpHeaders,
          required initialCamera,
          required limits,
        }) async {
          creations.add((camera: initialCamera, limits: limits));
          return map;
        };
  });
  tearDown(() => debugCreateMapigradeMap = null);

  const initial = MapigradeCamera(
    center: LatLng(48.2, 16.37),
    zoom: 14,
    pitch: 45,
  );

  Widget app(Widget child) => Directionality(
    textDirection: TextDirection.ltr,
    child: MediaQuery(
      data: const MediaQueryData(size: Size(400, 600)),
      child: Center(child: SizedBox(width: 400, height: 600, child: child)),
    ),
  );

  Widget mapWidget({
    String styleUrl = 'https://example.com/style.json',
    CameraLimits? limits,
    VoidCallback? onStyleLoaded,
    MapigradeController? controller,
    MapigradeCameraController? cameraController,
    List<Widget> children = const [],
  }) => app(
    MapigradeMap(
      styleUrl: styleUrl,
      initialCamera: initial,
      limits: limits,
      onStyleLoaded: onStyleLoaded,
      onError: errors.add,
      controller: controller,
      cameraController: cameraController,
      children: children,
    ),
  );

  FrameCamera frame({int id = 1, double pitch = 45}) => fakeFrame(
    id: id,
    latitude: 48.2,
    longitude: 16.37,
    zoom: 14,
    pitch: pitch,
    logicalSize: const Size(400, 600),
    matrix: testMatrix(
      center: const LatLng(48.2, 16.37),
      zoom: 14,
      size: const Size(400, 600),
      pitch: pitch,
    ),
  );

  testWidgets('the map starts at the initial camera and loads the style', (
    tester,
  ) async {
    var loaded = 0;
    await tester.pumpWidget(mapWidget(onStyleLoaded: () => loaded++));
    await tester.pump();
    final created = creations.single;
    expect(created.camera.fields, 1 | 2 | 8);
    expect(created.camera.latitude, 48.2);
    expect(created.camera.zoom, 14);
    expect(created.camera.pitch, 45);
    expect(created.limits.maxPitch, 60);
    expect(created.limits.hasBounds, isFalse);
    expect(map.styles, ['https://example.com/style.json']);
    expect(map.sizes.last, const Size(400, 600));
    map.send(const StyleLoaded());
    expect(loaded, 1);
  });

  testWidgets('a new style keeps the camera and calls onStyleLoaded again', (
    tester,
  ) async {
    var loaded = 0;
    await tester.pumpWidget(mapWidget(onStyleLoaded: () => loaded++));
    await tester.pump();
    map.send(const StyleLoaded());
    await tester.pumpWidget(
      mapWidget(
        styleUrl: 'https://example.com/other.json',
        onStyleLoaded: () => loaded++,
      ),
    );
    expect(map.styles.last, 'https://example.com/other.json');
    expect(map.commands, isEmpty);
    map.send(const StyleLoaded());
    expect(loaded, 2);
  });

  testWidgets('a style that fails to load is reported once', (tester) async {
    await tester.pumpWidget(mapWidget());
    await tester.pump();
    map.send(const LoadingFailed('no connection'));
    map.send(const LoadingFailed('no connection'));
    map.send(const RenderError('bad layer'));
    expect(errors.map((e) => e.runtimeType), [
      MapigradeLoadException,
      MapigradeRenderException,
    ]);
  });

  testWidgets('a map that can\'t be created reports one create exception '
      'and builds its children', (tester) async {
    debugCreateMapigradeMap = ({
      required pixelRatio,
      required httpHeaders,
      required initialCamera,
      required limits,
    }) async => throw const MapTextureException('not supported');
    await tester.pumpWidget(mapWidget(children: [const Text('child')]));
    await tester.pump();
    await tester.pump();
    expect(errors.single, isA<MapigradeCreateException>());
    expect(find.text('child'), findsOneWidget);
  });

  testWidgets('new limits are sent to the map', (tester) async {
    await tester.pumpWidget(mapWidget());
    await tester.pump();
    final limits = CameraLimits(
      maxPitch: 30,
      bounds: GeoBounds(const LatLng(1, 2), const LatLng(3, 4)),
    );
    await tester.pumpWidget(mapWidget(limits: limits));
    final sent = map.limits.single;
    expect(sent.maxPitch, 30);
    expect(sent.hasBounds, isTrue);
    expect((sent.south, sent.west, sent.north, sent.east), (1, 2, 3, 4));
  });

  testWidgets('the camera controller commands the map and reads the '
      'displayed frame', (tester) async {
    final cameraController = MapigradeCameraController();
    await tester.pumpWidget(mapWidget(cameraController: cameraController));
    expect(cameraController.camera.pitch, 45);
    await tester.pump();
    final jump = cameraController.jumpTo(const MapigradeCamera(zoom: 12));
    map.send(CameraTransitionEnded(map.commands.single.$1, 0));
    expect(await jump, CameraTransitionOutcome.completed);
    map.finish(frame(pitch: 30));
    await tester.pump();
    expect(cameraController.camera.pitch, 30);
    await tester.pumpWidget(app(const SizedBox()));
    expect(() => cameraController.camera, throwsStateError);
  });

  testWidgets('children read the displayed frame', (tester) async {
    final seen = <MapigradeFrame?>[];
    await tester.pumpWidget(
      mapWidget(
        children: [
          Builder(
            builder: (context) {
              seen.add(MapigradeFrame.maybeOf(context));
              return const SizedBox();
            },
          ),
        ],
      ),
    );
    await tester.pump();
    expect(seen.last, isNull);
    map.finish(frame());
    await tester.pump();
    final displayed = seen.last!;
    expect(displayed.camera.pitch, 45);
    expect(displayed.size, const Size(400, 600));
    final center = displayed.project(const LatLng(48.2, 16.37))!;
    expect(center.dx, closeTo(200, 1e-6));
  });

  testWidgets('a polyline layer in the children gives the map its polylines', (
    tester,
  ) async {
    await tester.pumpWidget(
      mapWidget(
        children: [
          MapigradePolylineLayer(
            polylines: [
              MapigradePolyline(
                points: const [LatLng(48.2, 16.37), LatLng(48.21, 16.38)],
              ),
            ],
          ),
        ],
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(map.overlayLayers, isNotEmpty);
    expect(map.overlaySources, isNotEmpty);
  });

  testWidgets('a feature query converts its square with the displayed frame', (
    tester,
  ) async {
    final controller = MapigradeController();
    await tester.pumpWidget(mapWidget(controller: controller));
    await tester.pump();
    map.finish(frame());
    await tester.pump();
    map.queryResult = [
      {
        'feature': {
          'type': 'Feature',
          'id': 7,
          'geometry': null,
          'properties': <String, Object?>{},
        },
        'source': 'roads',
        'sourceLayer': null,
        'state': <String, Object?>{},
      },
    ];
    final features = await controller.queryRenderedFeatures(
      const Offset(200, 400),
      radius: 4,
    );
    expect(features.single.id, 7);
    final corners = map.queries.single;
    final displayed = tester
        .state<MapigradeMapState>(find.byType(MapigradeMap))
        .displayedFrame!;
    for (final (i, position) in [
      const Offset(196, 396),
      const Offset(204, 396),
      const Offset(204, 404),
      const Offset(196, 404),
    ].indexed) {
      expect(corners[i], displayed.worldOf(position));
    }
  });
}
