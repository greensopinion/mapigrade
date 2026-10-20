// The scenarios "Application runs on web" and "Layer placed without the
// native library" of the map-layer spec in a process that has no native
// library, without nativeLibraryAvailableOverride (design D165 of the
// web-build-compatibility change). Run it in Chrome with
// `flutter test --platform chrome`; under flutter_tester on a macOS host the
// process has no native library either, so it also passes there.
import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_mapigrade/flutter_mapigrade.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

const _markerKey = Key('marker');

void main() {
  test('isSupported is false', () {
    expect(MapigradeLayer.isSupported, isFalse);
  });

  test('maximumCacheSizeBytes is stored', () {
    addTearDown(() => MapigradeLayer.maximumCacheSizeBytes = 52428800);
    MapigradeLayer.maximumCacheSizeBytes = 1024;
    expect(MapigradeLayer.maximumCacheSizeBytes, 1024);
  });

  testWidgets('a placed layer reports a creation failure', (tester) async {
    final failures = <LayerException>[];
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(800, 600)),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: FlutterMap(
            options: const MapOptions(
              initialCenter: LatLng(49.25, -123.1),
              initialZoom: 10,
            ),
            children: [
              MapigradeLayer(
                styleUrl: 'https://example.com/style.json',
                onError: failures.add,
              ),
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
      ),
    );

    expect(tester.takeException(), isNull);
    expect(failures, hasLength(1));
    expect(failures.single, isA<LayerCreateException>());
    expect(
      failures.single.message,
      contains('native library of flutter_mapigrade is not available'),
    );
    expect(find.byKey(_markerKey), findsOneWidget);
  });
}
