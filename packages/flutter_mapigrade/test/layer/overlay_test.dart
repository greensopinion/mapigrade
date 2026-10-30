// Widget tests for the overlay host of MapTextureLayer (D198 and D200 of
// add-mapigrade-polyline-layer) and for MapigradePolylineLayer (D195, D196,
// D202 and D203), against a map without native code. The tests assert the
// calls sent to the map.
import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart' hide MapCamera, MapEvent;
import 'package:flutter_mapigrade/src/layer/layer_exception.dart';
import 'package:flutter_mapigrade/src/layer/layer_placement.dart';
import 'package:flutter_mapigrade/src/layer/map_texture_layer.dart';
import 'package:flutter_mapigrade/src/polyline/mapigrade_polyline.dart';
import 'package:flutter_mapigrade/src/polyline/mapigrade_polyline_layer.dart';
import 'package:flutter_mapigrade/src/polyline/polyline_translation.dart';
import 'package:flutter_mapigrade/src/texture/map_texture_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

typedef _LayersCall = ({
  int id,
  String layersJson,
  int kind,
  String? below,
  int child,
  int seq,
});

class _FakeController implements MapTextureController {
  final layers = <_LayersCall>[];
  final data = <({int id, int source, bool lineMetrics, Uint8List bytes})>[];
  final removes = <int>[];
  final sourceRemoves = <(int, int)>[];
  // The overlay calls in order, as `<name> <overlay ID>[ <source index>]`.
  final log = <String>[];
  final backgroundGates = <Completer<void>>[];
  bool background = false;
  MapTextureException? dataFailure;

  @override
  final List<int> textureIds = const [1];
  @override
  FrameCamera? readyFrame;
  @override
  FrameCamera? get selectedFrame => null;
  @override
  Stream<FrameCamera> get readyFrames => const Stream.empty();
  @override
  Stream<MapEvent> get events => const Stream.empty();
  @override
  Stream<FrameCamera> get frames => const Stream.empty();
  @override
  bool isDisposed = false;

  @override
  FrameCamera? selectNewest() => null;
  @override
  void loadStyleUrl(String url) {}
  @override
  int setCamera(MapCamera camera) => 1;
  @override
  void resize(Size logicalSize, double pixelRatio) {}
  @override
  void setDisplayRefreshRate(double hz) {}
  @override
  void dispose() => isDisposed = true;

  @override
  void setOverlaySource(
    int overlayId,
    int sourceIndex,
    Uint8List geoJson, {
    required bool lineMetrics,
  }) {
    if (dataFailure case final failure?) throw failure;
    log.add('set_source $overlayId $sourceIndex');
    data.add((
      id: overlayId,
      source: sourceIndex,
      lineMetrics: lineMetrics,
      bytes: geoJson,
    ));
  }

  @override
  Future<void> setOverlaySourceInBackground(
    int overlayId,
    int sourceIndex,
    Uint8List Function() encode, {
    required bool lineMetrics,
  }) async {
    final bytes = encode();
    final gate = Completer<void>();
    backgroundGates.add(gate);
    await gate.future;
    setOverlaySource(overlayId, sourceIndex, bytes, lineMetrics: lineMetrics);
  }

  @override
  void removeOverlaySource(int overlayId, int sourceIndex) {
    log.add('remove_source $overlayId $sourceIndex');
    sourceRemoves.add((overlayId, sourceIndex));
  }

  @override
  void setOverlayLayers(
    int overlayId, {
    required String layersJson,
    required int placementKind,
    String? belowLayerId,
    required int orderChild,
    required int orderSeq,
  }) {
    log.add('set_layers $overlayId');
    layers.add((
      id: overlayId,
      layersJson: layersJson,
      kind: placementKind,
      below: belowLayerId,
      child: orderChild,
      seq: orderSeq,
    ));
  }

  @override
  void removeOverlay(int overlayId) {
    log.add('remove $overlayId');
    removes.add(overlayId);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final _line = [const LatLng(49, -123), const LatLng(49.1, -123.1)];

MapigradePolyline _polyline({
  List<LatLng>? points,
  List<double>? dashes,
  double strokeWidth = 4,
  List<Color>? gradientColors,
}) => MapigradePolyline(
  points: points ?? _line,
  dashes: dashes,
  strokeWidth: strokeWidth,
  gradientColors: gradientColors,
);

const _gradient = [Color(0xFFFF0000), Color(0xFF0000FF)];

List<LatLng> _points(int count) => [
  for (var i = 0; i < count; i++) LatLng(i * 0.0001, i * 0.0001),
];

int _pointCount(Uint8List geoJson) {
  final json = jsonDecode(utf8.decode(geoJson)) as Map<String, Object?>;
  return [
    for (final f in json['features']! as List)
      ((f as Map)['geometry'] as Map)['coordinates'] as List,
  ].fold(0, (sum, c) => sum + c.length);
}

Widget _app(
  List<Widget> children,
  MapTextureControllerFactory create, {
  List<LayerException>? errors,
}) => MediaQuery(
  data: const MediaQueryData(size: Size(800, 600)),
  child: Directionality(
    textDirection: TextDirection.ltr,
    child: FlutterMap(
      options: const MapOptions(
        initialCenter: LatLng(49.25, -123.1),
        initialZoom: 10,
      ),
      children: [
        MapTextureLayer(
          styleUrl: 'https://example.com/style.json',
          createController: create,
          onError: (e) => errors?.add(e),
          children: children,
        ),
      ],
    ),
  ),
);

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
}

KeyedSubtree _named(
  String name,
  List<MapigradePolyline> polylines, {
  LayerPlacement placement = const LayerPlacement.belowLabels(),
}) => KeyedSubtree(
  key: ValueKey(name),
  child: MapigradePolylineLayer(polylines: polylines, placement: placement),
);

void main() {
  late _FakeController fake;
  late List<LayerException> errors;

  Future<MapTextureController> create({
    required double pixelRatio,
    required bool copyFree,
    required List<dynamic> httpHeaders,
  }) async => fake;

  setUp(() {
    fake = _FakeController();
    errors = [];
  });

  Widget app(List<Widget> children) => _app(children, create, errors: errors);

  group('overlay host', () {
    testWidgets('sends overlays registered before the map exists when it is '
        'created', (tester) async {
      final creation = Completer<MapTextureController>();
      Future<MapTextureController> pending({
        required double pixelRatio,
        required bool copyFree,
        required List<dynamic> httpHeaders,
      }) => creation.future;
      await tester.pumpWidget(
        _app([
          _named('a', [_polyline()]),
          _named('b', [
            _polyline(points: _points(3)),
          ], placement: const LayerPlacement.top()),
        ], pending),
      );
      expect(fake.layers, isEmpty);
      expect(fake.data, isEmpty);

      creation.complete(fake);
      await _settle(tester);

      expect(
        {for (final c in fake.layers) c.id: (c.kind, c.child, c.seq)},
        {1: (0, 0, 0), 2: (2, 1, 1)},
      );
      expect(
        {for (final d in fake.data) d.id: _pointCount(d.bytes)},
        {1: 2, 2: 3},
      );
    });

    testWidgets('sends only the newest data of an overlay that changed before '
        'the map exists', (tester) async {
      final creation = Completer<MapTextureController>();
      Future<MapTextureController> pending({
        required double pixelRatio,
        required bool copyFree,
        required List<dynamic> httpHeaders,
      }) => creation.future;
      await tester.pumpWidget(
        _app([
          _named('a', [_polyline()]),
        ], pending),
      );
      await tester.pumpWidget(
        _app([
          _named('a', [_polyline(points: _points(5))]),
        ], pending),
      );
      creation.complete(fake);
      await _settle(tester);

      expect(fake.data.map((d) => _pointCount(d.bytes)), [5]);
      expect(fake.layers, hasLength(1));
    });

    testWidgets('the order key follows children after a reorder and an '
        'insert', (tester) async {
      final a = _named('a', [_polyline()]);
      final b = _named('b', [_polyline()]);
      await tester.pumpWidget(app([a, b]));
      await _settle(tester);

      Map<int, int> lastChildren() => {
        for (final c in fake.layers) c.id: c.child,
      };
      expect(lastChildren(), {1: 0, 2: 1});

      await tester.pumpWidget(app([b, a]));
      await _settle(tester);
      expect(lastChildren(), {1: 1, 2: 0});

      final c = _named('c', [_polyline()]);
      await tester.pumpWidget(app([c, b, a]));
      await _settle(tester);
      expect(lastChildren(), {1: 2, 2: 1, 3: 0});
      expect(fake.layers.singleWhere((c) => c.id == 3).seq, 2);
    });

    testWidgets('a polyline layer deeper in a child has the index of the '
        'child', (tester) async {
      await tester.pumpWidget(
        app([
          const SizedBox(),
          Builder(
            builder: (_) => Padding(
              padding: EdgeInsets.zero,
              child: MapigradePolylineLayer(polylines: [_polyline()]),
            ),
          ),
        ]),
      );
      await _settle(tester);
      expect(fake.layers.single.child, 1);
    });

    testWidgets('removes the overlay when the widget is disposed', (
      tester,
    ) async {
      await tester.pumpWidget(
        app([
          _named('a', [_polyline()]),
          _named('b', [_polyline()]),
        ]),
      );
      await _settle(tester);
      expect(fake.removes, isEmpty);

      await tester.pumpWidget(
        app([
          _named('b', [_polyline()]),
        ]),
      );
      expect(fake.removes, [1]);

      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
      expect(errors, isEmpty);
    });
  });

  group('MapigradePolylineLayer', () {
    testWidgets('a rebuild with an equal list sends nothing', (tester) async {
      final points = _line;
      await tester.pumpWidget(
        app([
          MapigradePolylineLayer(polylines: [_polyline(points: points)]),
        ]),
      );
      await _settle(tester);
      final sent = (fake.layers.length, fake.data.length);
      expect(sent, (1, 1));

      await tester.pumpWidget(
        app([
          MapigradePolylineLayer(
            polylines: [_polyline(points: List.of(points))],
          ),
        ]),
      );
      expect((fake.layers.length, fake.data.length), sent);

      final list = [_polyline()];
      await tester.pumpWidget(app([MapigradePolylineLayer(polylines: list)]));
      final afterChange = (fake.layers.length, fake.data.length);
      await tester.pumpWidget(app([MapigradePolylineLayer(polylines: list)]));
      expect((fake.layers.length, fake.data.length), afterChange);
    });

    testWidgets('a points change sends data and no layers', (tester) async {
      await tester.pumpWidget(
        app([
          MapigradePolylineLayer(polylines: [_polyline()]),
        ]),
      );
      await _settle(tester);
      await tester.pumpWidget(
        app([
          MapigradePolylineLayer(
            polylines: [
              _polyline(points: [..._line, const LatLng(49.2, -123.2)]),
            ],
          ),
        ]),
      );

      expect(fake.layers, hasLength(1));
      expect(fake.data.map((d) => _pointCount(d.bytes)), [2, 3]);
    });

    testWidgets('a dashes change sends layers', (tester) async {
      await tester.pumpWidget(
        app([
          MapigradePolylineLayer(polylines: [_polyline()]),
        ]),
      );
      await _settle(tester);
      await tester.pumpWidget(
        app([
          MapigradePolylineLayer(
            polylines: [
              _polyline(dashes: [2, 1]),
            ],
          ),
        ]),
      );

      expect(fake.layers, hasLength(2));
      expect(fake.layers.last.layersJson, contains('line-dasharray'));
      expect(fake.layers.first.layersJson, isNot(contains('line-dasharray')));
      expect(fake.layers.last.id, fake.layers.first.id);
    });

    testWidgets('a placement change sends layers and no data', (tester) async {
      await tester.pumpWidget(
        app([
          MapigradePolylineLayer(polylines: [_polyline()]),
        ]),
      );
      await _settle(tester);
      expect(fake.layers.single.kind, 0);

      await tester.pumpWidget(
        app([
          MapigradePolylineLayer(
            polylines: [_polyline()],
            placement: const LayerPlacement.belowLayer('water'),
          ),
        ]),
      );
      expect(fake.layers.last.kind, 1);
      expect(fake.layers.last.below, 'water');

      await tester.pumpWidget(
        app([
          MapigradePolylineLayer(
            polylines: [_polyline()],
            placement: const LayerPlacement.top(),
          ),
        ]),
      );
      expect(fake.layers.last.kind, 2);
      expect(fake.layers, hasLength(3));
      expect(fake.data, hasLength(1));
    });

    testWidgets('writes the overlay source and layer IDs into the layers', (
      tester,
    ) async {
      await tester.pumpWidget(
        app([
          MapigradePolylineLayer(polylines: [_polyline()]),
        ]),
      );
      await _settle(tester);
      final layers = jsonDecode(fake.layers.single.layersJson) as List;
      expect(
        [for (final l in layers) (l as Map)['id']],
        ['mapigrade-overlay-1-0', 'mapigrade-overlay-1-1'],
      );
      expect(
        {for (final l in layers) (l as Map)['source']},
        {'mapigrade-overlay-1-source-0'},
      );
      expect(fake.data.single.source, 0);
      expect(fake.data.single.lineMetrics, isFalse);
    });

    testWidgets('a gradient polyline goes in a second source with line '
        'metrics, which is removed after the layers when it goes', (
      tester,
    ) async {
      await tester.pumpWidget(
        app([
          MapigradePolylineLayer(polylines: [_polyline()]),
        ]),
      );
      await _settle(tester);
      expect(fake.log, ['set_source 1 0', 'set_layers 1']);

      fake.log.clear();
      await tester.pumpWidget(
        app([
          MapigradePolylineLayer(
            polylines: [_polyline(), _polyline(gradientColors: _gradient)],
          ),
        ]),
      );
      expect(fake.log, ['set_source 1 1', 'set_layers 1']);
      expect(fake.data.last.lineMetrics, isTrue);
      expect(_pointCount(fake.data.last.bytes), 2);
      expect(_pointCount(fake.data[fake.data.length - 2].bytes), 2);
      final layers = jsonDecode(fake.layers.last.layersJson) as List;
      expect([for (final l in layers) (l as Map)['source']], [
        'mapigrade-overlay-1-source-0',
        'mapigrade-overlay-1-source-0',
        'mapigrade-overlay-1-source-1',
        'mapigrade-overlay-1-source-1',
      ]);

      fake.log.clear();
      await tester.pumpWidget(
        app([
          MapigradePolylineLayer(polylines: [_polyline()]),
        ]),
      );
      expect(fake.log, ['set_layers 1', 'remove_source 1 1']);

      // Without a gradient source there is nothing to remove.
      fake.log.clear();
      await tester.pumpWidget(
        app([
          MapigradePolylineLayer(polylines: [_polyline(strokeWidth: 2)]),
        ]),
      );
      expect(fake.log, ['set_source 1 0']);
    });

    testWidgets('a change sends only the source whose features changed', (
      tester,
    ) async {
      final plain = _polyline();
      final gradient = _polyline(points: _points(3), gradientColors: _gradient);
      await tester.pumpWidget(
        app([
          MapigradePolylineLayer(polylines: [plain, gradient]),
        ]),
      );
      await _settle(tester);

      fake.log.clear();
      await tester.pumpWidget(
        app([
          MapigradePolylineLayer(
            polylines: [
              plain,
              _polyline(points: _points(4), gradientColors: _gradient),
            ],
          ),
        ]),
      );
      expect(fake.log, ['set_source 1 1']);

      fake.log.clear();
      await tester.pumpWidget(
        app([
          MapigradePolylineLayer(
            polylines: [
              _polyline(points: _points(5)),
              _polyline(points: _points(4), gradientColors: _gradient),
            ],
          ),
        ]),
      );
      expect(fake.log, ['set_source 1 0']);

      // A plain polyline inserted before the gradient one changes the gradient
      // feature's index, so both sources are sent; the runs stay the same.
      fake.log.clear();
      await tester.pumpWidget(
        app([
          MapigradePolylineLayer(
            polylines: [
              _polyline(points: _points(6)),
              _polyline(points: _points(5)),
              _polyline(points: _points(4), gradientColors: _gradient),
            ],
          ),
        ]),
      );
      expect(fake.log, ['set_source 1 0', 'set_source 1 1']);
    });

    testWidgets('fails an assertion outside a MapigradeLayer', (tester) async {
      await tester.pumpWidget(MapigradePolylineLayer(polylines: [_polyline()]));
      expect(
        tester.takeException(),
        isA<AssertionError>().having(
          (e) => '${e.message}',
          'message',
          contains('MapigradeLayer'),
        ),
      );
    });

    testWidgets("doesn't throw when the map can't be created", (tester) async {
      Future<MapTextureController> failing({
        required double pixelRatio,
        required bool copyFree,
        required List<dynamic> httpHeaders,
      }) async => throw const MapTextureException('map_texture_create failed');
      await tester.pumpWidget(
        _app(
          [
            MapigradePolylineLayer(polylines: [_polyline()]),
          ],
          failing,
          errors: errors,
        ),
      );
      await _settle(tester);
      await tester.pumpWidget(
        _app(
          [
            MapigradePolylineLayer(
              polylines: [_polyline(points: _points(4))],
              placement: const LayerPlacement.top(),
            ),
          ],
          failing,
          errors: errors,
        ),
      );
      await tester.pumpWidget(const SizedBox());

      expect(tester.takeException(), isNull);
      expect(errors, [const LayerCreateException('map_texture_create failed')]);
    });

    testWidgets('reports a data failure as a render error that names the '
        'operation', (tester) async {
      fake.dataFailure = const MapTextureException('bad GeoJSON');
      await tester.pumpWidget(
        app([
          MapigradePolylineLayer(polylines: [_polyline()]),
        ]),
      );
      await _settle(tester);

      expect(errors, hasLength(1));
      expect(errors.single, isA<LayerRenderException>());
      expect(errors.single.message, contains('map_texture_overlay_set_source'));
      expect(errors.single.message, contains('bad GeoJSON'));
    });
  });

  group('background encoding', () {
    Widget big(int points) =>
        MapigradePolylineLayer(polylines: [_polyline(points: _points(points))]);

    List<int> sent() => [for (final d in fake.data) _pointCount(d.bytes)];

    Future<void> release(WidgetTester tester, int index) async {
      fake.backgroundGates[index].complete();
      await _settle(tester);
    }

    testWidgets('data above the threshold is sent from the background, and '
        'data below it is not', (tester) async {
      await tester.pumpWidget(app([big(polylineBackgroundPointThreshold)]));
      await _settle(tester);
      expect(fake.backgroundGates, isEmpty);
      expect(sent(), [polylineBackgroundPointThreshold]);

      await tester.pumpWidget(app([big(polylineBackgroundPointThreshold + 1)]));
      expect(fake.backgroundGates, hasLength(1));
      expect(sent(), [polylineBackgroundPointThreshold]);
      await release(tester, 0);
      expect(sent(), [
        polylineBackgroundPointThreshold,
        polylineBackgroundPointThreshold + 1,
      ]);
    });

    testWidgets('updates during a running call are replaced by the newest, '
        'and never sent before older data', (tester) async {
      const n = polylineBackgroundPointThreshold;
      await tester.pumpWidget(app([big(n + 1)]));
      await _settle(tester);
      await tester.pumpWidget(app([big(n + 2)]));
      await tester.pumpWidget(app([big(n + 3)]));
      await tester.pumpWidget(app([big(n + 4)]));
      expect(fake.backgroundGates, hasLength(1));
      expect(sent(), isEmpty);

      await release(tester, 0);
      expect(sent(), [n + 1]);
      expect(fake.backgroundGates, hasLength(2));

      // A small update waits for the call that is running.
      await tester.pumpWidget(app([big(7)]));
      expect(sent(), [n + 1]);
      await release(tester, 1);
      expect(sent(), [n + 1, n + 4, 7]);
      expect(fake.backgroundGates, hasLength(2));
    });

    testWidgets('a gradient source is removed after its running call', (
      tester,
    ) async {
      const n = polylineBackgroundPointThreshold;
      await tester.pumpWidget(
        app([
          MapigradePolylineLayer(
            polylines: [
              _polyline(points: _points(n)),
              _polyline(gradientColors: _gradient),
            ],
          ),
        ]),
      );
      await _settle(tester);
      expect(fake.backgroundGates, hasLength(2));
      await tester.pumpWidget(app([big(n + 1)]));
      expect(fake.sourceRemoves, isEmpty);
      await release(tester, 0);
      await release(tester, 1);
      expect(fake.log, [
        'set_layers 1',
        'set_layers 1',
        'set_source 1 0',
        'set_source 1 1',
        'remove_source 1 1',
      ]);
      expect(fake.backgroundGates, hasLength(3));
      await release(tester, 2);
      expect(fake.log.last, 'set_source 1 0');
      expect(sent(), [n, 2, n + 1]);
    });

    testWidgets('removal waits for the call that is running', (tester) async {
      await tester.pumpWidget(app([big(polylineBackgroundPointThreshold + 1)]));
      await _settle(tester);
      await tester.pumpWidget(app(const []));
      expect(fake.removes, isEmpty);

      await release(tester, 0);
      expect(fake.removes, [1]);
      expect(fake.backgroundGates, hasLength(1));
    });
  });

  test(
    'the polylines and the encoder can be sent to another isolate',
    () async {
      final polylines = [
        MapigradePolyline(
          points: _line,
          gradientColors: const [Color(0xFF000000), Color(0xFFFFFFFF)],
        ),
        _polyline(dashes: [1, 2]),
      ];
      for (final source in PolylineSource.values) {
        final fromIsolate = await Isolate.run(
          () => polylineGeoJson(polylineFeatures(polylines, source)),
        );
        expect(fromIsolate, polylineGeoJson(polylineFeatures(polylines, source)));
      }
    },
  );
}
