// Widget tests for the layer when its map can't be created (design D67 of the
// public-api change). The other scenarios need the native map and are
// integration tests in packages/test_harness/integration_test/.
import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_mapigrade/src/layer/layer_exception.dart';
import 'package:flutter_mapigrade/src/layer/map_texture_layer.dart';
import 'package:flutter_mapigrade/src/texture/map_texture_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

const _markerKey = Key('marker');

MapTextureController _failingCreate({
  required double pixelRatio,
  required bool copyFree,
}) => throw const MapTextureException('map_texture_create failed with -3');

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
}
