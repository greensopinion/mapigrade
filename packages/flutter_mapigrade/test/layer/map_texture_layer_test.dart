// Widget tests for the layer when its map can't be created (design D67 of the
// public-api change) and its header rules (D80 of http-headers-and-assets).
// The other scenarios need the native map and are integration tests in
// packages/test_harness/integration_test/.
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart' hide MapCamera, MapEvent;
import 'package:flutter_mapigrade/src/layer/http_header_rule.dart';
import 'package:flutter_mapigrade/src/layer/layer_exception.dart';
import 'package:flutter_mapigrade/src/layer/map_texture_layer.dart';
import 'package:flutter_mapigrade/src/texture/map_texture_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

const _markerKey = Key('marker');

MapTextureController _failingCreate({
  required double pixelRatio,
  required bool copyFree,
  required List<HttpHeaderRule> httpHeaders,
}) => throw const MapTextureException('map_texture_create failed with -3');

// A controller without a native map.
class _FakeController implements MapTextureController {
  final _events = StreamController<MapEvent>.broadcast();
  final _frames = StreamController<FrameCamera>.broadcast();
  bool _disposed = false;

  @override
  int get textureId => 1;
  @override
  bool get isDisposed => _disposed;
  @override
  Stream<MapEvent> get events => _events.stream;
  @override
  Stream<FrameCamera> get frames => _frames.stream;
  @override
  void loadStyleUrl(String url) {}
  @override
  void loadStyleJson(String json) {}
  @override
  void setCamera(MapCamera camera) {}
  @override
  void resize(Size logicalSize, double pixelRatio) {}
  @override
  void setDisplayRefreshRate(double hz) {}
  @override
  void dispose() {
    _disposed = true;
    _events.close();
    _frames.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _map(MapTextureLayer layer, {double pixelRatio = 1}) => MediaQuery(
  data: MediaQueryData(
    size: const Size(800, 600),
    devicePixelRatio: pixelRatio,
  ),
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
    MapTextureController create({
      required double pixelRatio,
      required bool copyFree,
      required List<HttpHeaderRule> httpHeaders,
    }) {
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
          }) => throw const MapTextureException(message),
          onError: failures.add,
        ),
      ),
    );

    expect(failures, [const LayerCreateException(message)]);
  });
}
