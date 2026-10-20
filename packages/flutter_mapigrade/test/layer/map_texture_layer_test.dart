// Widget tests for the layer when its map can't be created (design D67 of the
// public-api change), its header rules (D80 of http-headers-and-assets), its
// metrics (D111 of layer-metrics), its children (D125 and D127 of
// layer-children-alignment), and its asynchronous creation (D155 of
// multiple-flutter-engines).
// The other scenarios need the native map and are integration tests in
// packages/test_harness/integration_test/.
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart' hide MapCamera, MapEvent;
import 'package:flutter_map/flutter_map.dart' as fm show MapCamera;
// The layer's children read the camera through MapInheritedModel; the test
// that builds it directly fails when a flutter_map release changes it.
// ignore: implementation_imports
import 'package:flutter_map/src/map/inherited_model.dart';
import 'package:flutter_mapigrade/src/layer/camera_projection.dart';
import 'package:flutter_mapigrade/src/layer/layer_alignment.dart';
import 'package:flutter_mapigrade/src/layer/http_header_rule.dart';
import 'package:flutter_mapigrade/src/layer/layer_exception.dart';
import 'package:flutter_mapigrade/src/layer/layer_metrics.dart';
import 'package:flutter_mapigrade/src/layer/map_texture_layer.dart';
import 'package:flutter_mapigrade/src/texture/map_texture_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

const _markerKey = Key('marker');

Future<MapTextureController> _failingCreate({
  required double pixelRatio,
  required bool copyFree,
  required List<HttpHeaderRule> httpHeaders,
}) async =>
    throw const MapTextureException('map_texture_create failed with -3');

// A controller without a native map.
class _FakeController implements MapTextureController {
  _FakeController({this.textureIds = const [1]});

  final _events = StreamController<MapEvent>.broadcast();
  final _frames = StreamController<FrameCamera>.broadcast();
  final _readyFrames = StreamController<FrameCamera>.broadcast();
  bool _disposed = false;

  /// The counters that [stats] returns.
  MapTextureStats values = const MapTextureStats.forTesting();

  /// The cameras passed to [setCamera], in order; the sequence number of
  /// each is its index plus one.
  final List<MapCamera> cameras = [];

  /// The frames that [selectNewest] chose, in order.
  final List<FrameCamera> selected = [];

  /// The newest finished frame that [selectNewest] hasn't chosen, as the map
  /// holds it.
  FrameCamera? finished;

  @override
  final List<int> textureIds;
  @override
  FrameCamera? readyFrame;
  @override
  FrameCamera? get selectedFrame => selected.lastOrNull;
  @override
  Stream<FrameCamera> get readyFrames => _readyFrames.stream;

  /// Finishes [frame] and reports it as ready, as the native map does after
  /// a render.
  void addReadyFrame(FrameCamera frame) {
    finished = frame;
    readyFrame = frame;
    _readyFrames.add(frame);
  }

  @override
  FrameCamera? selectNewest() {
    final frame = finished;
    if (frame == null) return null;
    finished = null;
    selected.add(frame);
    return frame;
  }

  @override
  bool get isDisposed => _disposed;
  @override
  Stream<MapEvent> get events => _events.stream;
  @override
  Stream<FrameCamera> get frames => _frames.stream;

  /// The URLs passed to [loadStyleUrl], in order.
  final List<String> styleUrls = [];

  @override
  void loadStyleUrl(String url) => styleUrls.add(url);
  @override
  void loadStyleJson(String json) {}
  @override
  int setCamera(MapCamera camera) {
    cameras.add(camera);
    return cameras.length;
  }

  @override
  void resize(Size logicalSize, double pixelRatio) {}
  @override
  void setDisplayRefreshRate(double hz) {}
  @override
  MapTextureStats stats() {
    if (_disposed) throw const MapTextureDisposedException();
    return values;
  }

  @override
  void dispose() {
    _disposed = true;
    _events.close();
    _frames.close();
    _readyFrames.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _map(
  MapTextureLayer layer, {
  double pixelRatio = 1,
  Size size = const Size(800, 600),
}) => MediaQuery(
  data: MediaQueryData(size: size, devicePixelRatio: pixelRatio),
  child: Directionality(
    textDirection: TextDirection.ltr,
    child: FlutterMap(
      options: const MapOptions(
        initialCenter: LatLng(49.25, -123.1),
        initialZoom: 10,
      ),
      children: [
        layer,
        const MarkerLayer(
          markers: [
            Marker(
              point: LatLng(49.25, -123.1),
              child: SizedBox(key: _markerKey),
            ),
          ],
        ),
      ],
    ),
  ),
);

void main() {
  testWidgets('reports a creation failure once to onError', (tester) async {
    final failures = <LayerException>[];
    MapTextureLayer layer() => MapTextureLayer(
      styleUrl: 'https://example.com/style.json',
      createController: _failingCreate,
      onError: failures.add,
    );

    await tester.pumpWidget(_map(layer()));
    // A change of the device pixel ratio changes the layer's dependencies.
    await tester.pumpWidget(_map(layer(), pixelRatio: 2));
    await tester.pumpWidget(_map(layer(), pixelRatio: 3));

    expect(failures, [
      const LayerCreateException('map_texture_create failed with -3'),
    ]);
  });

  testWidgets('occupies the viewport and the overlays are still drawn', (
    tester,
  ) async {
    await tester.pumpWidget(
      _map(
        MapTextureLayer(
          styleUrl: 'https://example.com/style.json',
          createController: _failingCreate,
          onError: (_) {},
        ),
      ),
    );
    // The frame after the creation failed.
    await tester.pump();

    expect(tester.getSize(find.byType(MapTextureLayer)), const Size(800, 600));
    expect(find.byKey(_markerKey), findsOneWidget);
  });

  testWidgets('reports through FlutterError without onError', (tester) async {
    final reports = <FlutterErrorDetails>[];
    final previous = FlutterError.onError;
    FlutterError.onError = reports.add;
    try {
      MapTextureLayer layer() => MapTextureLayer(
        styleUrl: 'https://example.com/style.json',
        createController: _failingCreate,
      );
      await tester.pumpWidget(_map(layer()));
      await tester.pumpWidget(_map(layer(), pixelRatio: 2));
    } finally {
      FlutterError.onError = previous;
    }

    expect(reports, hasLength(1));
    expect(
      reports.single.exception,
      const LayerCreateException('map_texture_create failed with -3'),
    );
    expect(reports.single.library, 'flutter_mapigrade');
    expect(find.byKey(_markerKey), findsOneWidget);
  });

  testWidgets('passes httpHeaders to the factory once', (tester) async {
    final calls = <List<HttpHeaderRule>>[];
    final controllers = <_FakeController>[];
    Future<MapTextureController> create({
      required double pixelRatio,
      required bool copyFree,
      required List<HttpHeaderRule> httpHeaders,
    }) async {
      calls.add(httpHeaders);
      final controller = _FakeController();
      controllers.add(controller);
      return controller;
    }

    MapTextureLayer layer(String key) => MapTextureLayer(
      styleUrl: 'https://example.com/style.json',
      createController: create,
      httpHeaders: [
        HttpHeaderRule(
          url: 'https://tiles.example.com/**',
          headers: {'X-Access-Key': key},
        ),
      ],
    );

    await tester.pumpWidget(_map(layer('k1')));
    await tester.pumpWidget(_map(layer('k2'), pixelRatio: 2));

    expect(calls, [
      [
        HttpHeaderRule(
          url: 'https://tiles.example.com/**',
          headers: {'X-Access-Key': 'k1'},
        ),
      ],
    ]);
    expect(controllers, hasLength(1));
    expect(controllers.single.isDisposed, isFalse);
    await tester.pumpWidget(const SizedBox());
    expect(controllers.single.isDisposed, isTrue);
  });

  testWidgets('reports a rejected header as a creation failure', (
    tester,
  ) async {
    const message = 'HTTP header "Host" is managed by MapLibre';
    final failures = <LayerException>[];
    await tester.pumpWidget(
      _map(
        MapTextureLayer(
          styleUrl: 'https://example.com/style.json',
          createController: ({
            required double pixelRatio,
            required bool copyFree,
            required List<HttpHeaderRule> httpHeaders,
          }) async => throw const MapTextureException(message),
          onError: failures.add,
        ),
      ),
    );

    expect(failures, [const LayerCreateException(message)]);
  });

  group('asynchronous creation', () {
    const style = 'https://example.com/style.json';
    late Completer<MapTextureController> creation;
    late int creations;

    // Called at the start of each test: a completer created in setUp belongs
    // to a zone whose microtasks the tester's pumps don't run.
    void start() {
      creation = Completer();
      creations = 0;
    }

    MapTextureLayer layer({void Function(LayerException)? onError}) =>
        MapTextureLayer(
          styleUrl: style,
          createController:
              ({
                required double pixelRatio,
                required bool copyFree,
                required List<HttpHeaderRule> httpHeaders,
              }) {
                creations++;
                return creation.future;
              },
          onError: onError,
        );

    testWidgets('builds the placeholder until creation completes, then '
        'loads the style', (tester) async {
      start();
      await tester.pumpWidget(_map(layer()));
      // A change of the device pixel ratio while creation is pending starts
      // no second creation.
      await tester.pumpWidget(_map(layer(), pixelRatio: 2));
      expect(creations, 1);
      expect(find.byType(Texture), findsNothing);
      expect(find.byKey(_markerKey), findsOneWidget);

      final controller = _FakeController();
      creation.complete(controller);
      // The creation completes in a microtask after the first pump's frame;
      // the layer's setState builds in the second.
      await tester.pump();
      await tester.pump();
      expect(controller.styleUrls, [style]);
      expect(find.byType(Texture), findsOneWidget);
      expect(creations, 1);
    });

    testWidgets('disposing the layer during creation disposes the controller', (
      tester,
    ) async {
      start();
      await tester.pumpWidget(_map(layer()));
      await tester.pumpWidget(const SizedBox());

      final controller = _FakeController();
      creation.complete(controller);
      await tester.pump();
      expect(controller.isDisposed, isTrue);
      expect(controller.styleUrls, isEmpty);
    });

    testWidgets('a failed creation reports one LayerCreateException', (
      tester,
    ) async {
      start();
      final failures = <LayerException>[];
      await tester.pumpWidget(_map(layer(onError: failures.add)));
      await tester.pumpWidget(
        _map(layer(onError: failures.add), pixelRatio: 2),
      );
      creation.completeError(const MapTextureException('no engine token'));
      await tester.pump();
      await tester.pumpWidget(
        _map(layer(onError: failures.add), pixelRatio: 3),
      );

      expect(failures, [const LayerCreateException('no engine token')]);
      expect(creations, 1);
      expect(
        tester.getSize(find.byType(MapTextureLayer)),
        const Size(800, 600),
      );
    });
  });

  group('metrics', () {
    late List<_FakeController> controllers;
    Future<MapTextureController> create({
      required double pixelRatio,
      required bool copyFree,
      required List<HttpHeaderRule> httpHeaders,
    }) async {
      final controller = _FakeController();
      controllers.add(controller);
      return controller;
    }

    MapTextureLayer layer(
      LayerMetrics metrics, {
      Key? key,
      String style = 'https://example.com/style.json',
    }) => MapTextureLayer(
      key: key,
      styleUrl: style,
      createController: create,
      metrics: metrics,
    );

    MapTextureStats stats(int displayed, int rendered, int renderMs) =>
        MapTextureStats.forTesting(
          presentedFrames: displayed,
          renderedFrames: rendered,
          renderUpdateTotal: Duration(milliseconds: renderMs),
        );

    void expectValues(
      LayerMetrics metrics,
      int displayed,
      int rendered,
      int renderMs,
    ) {
      final snapshot = metrics.snapshot();
      expect(snapshot.displayedFrames, displayed);
      expect(snapshot.renderedFrames, rendered);
      expect(snapshot.renderTime, Duration(milliseconds: renderMs));
    }

    setUp(() => controllers = []);

    testWidgets('No map yet', (tester) async {
      final metrics = LayerMetrics();
      expectValues(metrics, 0, 0, 0);
      // The layer creates its map when the window's size has arrived.
      await tester.pumpWidget(_map(layer(metrics), size: Size.zero));
      expect(controllers, isEmpty);
      expectValues(metrics, 0, 0, 0);
    });

    testWidgets("Map can't be created", (tester) async {
      final metrics = LayerMetrics();
      await tester.pumpWidget(
        _map(
          MapTextureLayer(
            styleUrl: 'https://example.com/style.json',
            createController: _failingCreate,
            onError: (_) {},
            metrics: metrics,
          ),
        ),
      );
      expectValues(metrics, 0, 0, 0);
    });

    testWidgets('Style change', (tester) async {
      final metrics = LayerMetrics();
      await tester.pumpWidget(_map(layer(metrics)));
      controllers.single.values = stats(2, 3, 10);
      expectValues(metrics, 2, 3, 10);

      await tester.pumpWidget(
        _map(layer(metrics, style: 'https://example.com/other.json')),
      );
      controllers.single.values = stats(4, 5, 20);

      expect(controllers, hasLength(1));
      expectValues(metrics, 4, 5, 20);
    });

    testWidgets('Layer removed', (tester) async {
      final metrics = LayerMetrics();
      await tester.pumpWidget(_map(layer(metrics)));
      final controller = controllers.single;
      controller.values = stats(2, 3, 10);
      expectValues(metrics, 2, 3, 10);
      // Frames rendered after the last snapshot are read at the dispose.
      controller.values = stats(4, 5, 20);

      await tester.pumpWidget(const SizedBox());

      expect(controller.isDisposed, isTrue);
      expectValues(metrics, 4, 5, 20);
      expectValues(metrics, 4, 5, 20);
    });

    testWidgets('New key with the same object', (tester) async {
      final metrics = LayerMetrics();
      await tester.pumpWidget(_map(layer(metrics, key: const ValueKey(1))));
      controllers.single.values = stats(4, 5, 20);
      expectValues(metrics, 4, 5, 20);

      await tester.pumpWidget(_map(layer(metrics, key: const ValueKey(2))));

      expect(controllers, hasLength(2));
      expect(controllers.first.isDisposed, isTrue);
      expectValues(metrics, 0, 0, 0);
      controllers.last.values = stats(1, 1, 3);
      expectValues(metrics, 1, 1, 3);
    });

    testWidgets('Different object for the same map', (tester) async {
      final previous = LayerMetrics();
      await tester.pumpWidget(_map(layer(previous)));
      final controller = controllers.single;
      controller.values = stats(2, 3, 10);

      final metrics = LayerMetrics();
      await tester.pumpWidget(_map(layer(metrics)));
      controller.values = stats(4, 5, 20);

      expect(controllers, hasLength(1));
      expectValues(metrics, 4, 5, 20);
      expectValues(previous, 2, 3, 10);
    });
  });

  group('children', () {
    const center = LatLng(49.25, -123.1);
    late _FakeController controller;
    late MapController mapController;
    // The cameras that each probe read in its last build.
    late Map<String, fm.MapCamera> seen;
    late List<(int?, fm.MapCamera)> childCameras;

    setUp(() {
      controller = _FakeController(textureIds: const [10, 11, 12, 13]);
      mapController = MapController();
      seen = {};
      childCameras = [];
    });

    Widget probe(String name) => Builder(
      builder: (context) {
        seen[name] = fm.MapCamera.of(context);
        return const SizedBox.shrink();
      },
    );

    Widget map({
      LayerAlignment alignment = LayerAlignment.none,
      List<Widget>? children,
      _FakeController? fake,
    }) {
      final layerController = fake ?? controller;
      return MediaQuery(
        data: const MediaQueryData(size: Size(800, 600)),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: FlutterMap(
            mapController: mapController,
            options: const MapOptions(initialCenter: center, initialZoom: 10),
            children: [
              MapTextureLayer(
                styleUrl: 'https://example.com/style.json',
                alignment: alignment,
                createController: ({
                  required double pixelRatio,
                  required bool copyFree,
                  required List<HttpHeaderRule> httpHeaders,
                }) async => layerController,
                onChildCamera: (id, camera) => childCameras.add((id, camera)),
                children: children ?? [probe('child')],
              ),
              probe('sibling'),
            ],
          ),
        ),
      );
    }

    // Reports a frame rendered with the camera of sequence number [seq] as
    // ready in [slot].
    Future<void> ready(
      WidgetTester tester,
      int frameId,
      int slot,
      int seq, [
      _FakeController? fake,
    ]) async {
      final c = fake ?? controller;
      final camera = c.cameras[seq - 1];
      c.addReadyFrame(
        FrameCamera(
          frameId: frameId,
          camera: camera,
          physicalSize: const Size(800, 600),
          scaleFactor: 1,
          displayTime: null,
          slot: slot,
          seq: seq,
        ),
      );
      // The stream delivers the event in a microtask after the first pump's
      // frame; the layer's setState builds in the second.
      await tester.pump();
      await tester.pump();
    }

    // Builds [widget], and then the frame in which the layer has its map,
    // which it creates asynchronously (design D155).
    Future<void> show(WidgetTester tester, Widget widget) async {
      await tester.pumpWidget(widget);
      await tester.pump();
    }

    int displayedTexture(WidgetTester tester) =>
        tester.widget<Texture>(find.byType(Texture)).textureId;

    testWidgets('get the camera of the chosen frame', (tester) async {
      await show(tester, map());
      final first = mapController.camera;
      expect(controller.cameras, hasLength(1));
      await ready(tester, 1, 2, 1);
      expect(controller.selected.single.frameId, 1);
      expect(displayedTexture(tester), 12);
      expect(seen['child'], same(first));
      expect(childCameras.last, (1, first));

      // The live camera moves; until a frame of it is ready, the children
      // keep the camera of the chosen frame.
      mapController.move(const LatLng(49.3, -123.0), 10);
      await tester.pump();
      expect(controller.cameras, hasLength(2));
      final second = mapController.camera;
      expect(seen['child'], same(first));
      expect(seen['sibling'], same(second));
      expect(displayedTexture(tester), 12);

      await ready(tester, 2, 0, 2);
      expect(seen['child'], same(second));
      expect(displayedTexture(tester), 10);
      expect(controller.selected.map((f) => f.frameId), [1, 2]);
    });

    testWidgets('get a frame newer than the frame reported last', (
      tester,
    ) async {
      await show(tester, map());
      await ready(tester, 1, 2, 1);
      mapController.move(const LatLng(49.3, -123.0), 10);
      await tester.pump();
      final second = mapController.camera;
      FrameCamera frame(int id, int slot) => FrameCamera(
        frameId: id,
        camera: controller.cameras[1],
        physicalSize: const Size(800, 600),
        scaleFactor: 1,
        displayTime: null,
        slot: slot,
        seq: 2,
      );
      // The map reports frame 2, then replaces it with frame 3 before the
      // layer builds; the layer hasn't handled the report of frame 3.
      controller.addReadyFrame(frame(2, 0));
      controller.finished = frame(3, 3);
      await tester.pump();
      await tester.pump();
      expect(controller.selected.map((f) => f.frameId), [1, 3]);
      expect(controller.readyFrame?.frameId, 2);
      expect(childCameras.last, (3, second));
      expect(displayedTexture(tester), 13);
    });

    testWidgets('keep the frame chosen before when no frame has finished', (
      tester,
    ) async {
      await show(tester, map());
      final first = mapController.camera;
      await ready(tester, 1, 2, 1);
      mapController.move(const LatLng(49.3, -123.0), 10);
      await tester.pump();
      expect(controller.selected.map((f) => f.frameId), [1]);
      expect(seen['child'], same(first));
      expect(childCameras.last, (1, first));
      expect(displayedTexture(tester), 12);
    });

    testWidgets('get the predicted camera of the chosen frame', (tester) async {
      await show(tester, map(alignment: const LayerAlignment.prediction()));
      // A steady pan, so that the predictor extrapolates.
      for (var i = 1; i <= 6; i++) {
        mapController.move(LatLng(49.25, -123.1 + i * 0.01), 10);
        await tester.pump(const Duration(milliseconds: 16));
      }
      final seq = controller.cameras.length;
      final live = mapController.camera;
      final predicted = controller.cameras.last;
      expect(viewCameraOf(live).camera.longitude, isNot(predicted.longitude));
      await ready(tester, 1, 1, seq);
      final child = seen['child']!;
      expect(viewCameraOf(child), ViewCamera(predicted, live.nonRotatedSize));
      expect(child.crs, live.crs);
      expect(seen['sibling'], same(live));
    });

    testWidgets('get the live camera before the first frame', (tester) async {
      await show(tester, map());
      expect(seen['child'], same(mapController.camera));
      expect(childCameras.last, (null, mapController.camera));
      expect(displayedTexture(tester), 10);
      expect(controller.selected, isEmpty);
    });

    // Android: six slots share one texture id (design D135 of the
    // android-layer-children-alignment change).
    testWidgets('get the chosen frame camera with one shared texture id', (
      tester,
    ) async {
      final fake = _FakeController(textureIds: const [7, 7, 7, 7, 7, 7]);
      await show(tester, map(fake: fake));
      await ready(tester, 1, 4, 1, fake);
      final sent = seen['child'];
      mapController.move(const LatLng(49.3, -123.0), 10);
      await tester.pump();
      expect(fake.selected, hasLength(1));
      expect(childCameras.last.$1, 1);
      expect(seen['child'], isNot(same(mapController.camera)));
      expect(seen['child'], same(sent));
      expect(displayedTexture(tester), 7);
    });

    testWidgets("get flutter_map's controller and options", (tester) async {
      MapController? childController;
      MapOptions? childOptions;
      MapOptions? siblingOptions;
      await show(
        tester,
        map(
          children: [
            Builder(
              builder: (context) {
                childController = MapController.of(context);
                childOptions = MapOptions.of(context);
                return const SizedBox.shrink();
              },
            ),
          ],
        ),
      );
      siblingOptions = MapOptions.of(
        tester.element(find.byType(MapTextureLayer)),
      );
      expect(childController, same(mapController));
      expect(childOptions, same(siblingOptions));
    });

    testWidgets('fill the viewport above the map', (tester) async {
      await show(
        tester,
        map(children: [const SizedBox.expand(key: _markerKey)]),
      );
      expect(tester.getSize(find.byKey(_markerKey)), const Size(800, 600));
      expect(
        tester.getSize(find.byType(MapTextureLayer)),
        const Size(800, 600),
      );
    });

    testWidgets('a polyline hit-tests where it is drawn', (tester) async {
      final hits = LayerHitNotifier<String>(null);
      const line = [LatLng(49.20, -123.1), LatLng(49.30, -123.1)];
      await show(
        tester,
        map(
          children: [
            GestureDetector(
              behavior: HitTestBehavior.deferToChild,
              onTap: () {},
              child: PolylineLayer<String>(
                hitNotifier: hits,
                polylines: [
                  Polyline(points: line, strokeWidth: 4, hitValue: 'line'),
                ],
              ),
            ),
          ],
        ),
      );
      await ready(tester, 1, 1, 1);
      final drawnAt = mapController.camera.latLngToScreenOffset(center);
      // The live camera moves 200 px to the east; the polyline stays drawn
      // at the camera of the chosen frame.
      mapController.move(
        mapController.camera.screenOffsetToLatLng(
          mapController.camera.size.center(Offset.zero) + const Offset(200, 0),
        ),
        10,
      );
      await tester.pump();
      final liveAt = mapController.camera.latLngToScreenOffset(center);
      expect((liveAt - drawnAt).dx, closeTo(-200, 1));

      await tester.tapAt(drawnAt);
      expect(hits.value?.hitValues, ['line']);
      hits.value = null;
      await tester.tapAt(liveAt);
      expect(hits.value?.hitValues ?? const <String>[], isEmpty);
      // flutter_map's double-tap timer.
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('MapInheritedModel gives its camera to layers', (tester) async {
      final camera = fm.MapCamera(
        crs: const Epsg3857(),
        center: center,
        zoom: 10,
        rotation: 0,
        nonRotatedSize: const Size(800, 600),
      );
      const options = MapOptions();
      final model = MapInheritedModel(
        camera: camera,
        controller: mapController,
        options: options,
        child: probe('model'),
      );
      await tester.pumpWidget(model);
      expect(seen['model'], same(camera));
      expect(model.data.options, same(options));
    });
  });
}
