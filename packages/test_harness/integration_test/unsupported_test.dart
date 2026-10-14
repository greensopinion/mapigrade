// Integration test for the layer without the native library (map-layer spec,
// requirement "Unsupported architectures"; design D88 of the
// unsupported-architectures change). Run it on an arm64 Android emulator or
// device with an APK that lacks the library. `flutter test` has no
// --android-project-arg option, so the Gradle property is set through the
// environment:
//
//   cd packages/test_harness && env 'ORG_GRADLE_PROJECT_mapigrade.omitNativeLibrary=true' \
//     flutter test integration_test/unsupported_test.dart
//
// That the test runs at all shows that the app started: the plugin registers
// when the Flutter engine starts.
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_mapigrade/flutter_mapigrade.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:latlong2/latlong.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'without the native library the layer reports a creation failure',
    (tester) async {
      expect(MapigradeLayer.isSupported, isFalse);

      final failures = <LayerException>[];
      await tester.pumpWidget(
        MaterialApp(
          home: FlutterMap(
            options: const MapOptions(
              initialCenter: LatLng(51.5, -0.12),
              initialZoom: 12,
            ),
            children: [
              MapigradeLayer(
                styleUrl: 'https://demotiles.maplibre.org/style.json',
                onError: failures.add,
              ),
            ],
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(failures, hasLength(1));
      expect(failures.single, isA<LayerCreateException>());
      expect(
        failures.single.message,
        contains('native library of flutter_mapigrade is not available'),
      );
    },
  );
}
