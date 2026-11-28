// A process without the native library, without
// nativeLibraryAvailableOverride (design D165 of the web-build-compatibility
// change). Run it in Chrome with `flutter test --platform chrome`; under
// flutter_tester on a macOS host the process has no native library either, so
// it also passes there.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:mapigrade/mapigrade.dart';
import 'package:mapigrade/src/texture/map_texture_controller.dart';
import 'package:mapigrade/src/texture/native_library.dart';

void main() {
  test('the native library is not available', () {
    expect(nativeLibraryAvailable, isFalse);
  });

  test('creating a map fails with a MapTextureException', () async {
    await expectLater(
      MapTextureController.create(pixelRatio: 1),
      throwsA(
        isA<MapTextureException>().having(
          (e) => e.message,
          'message',
          contains('native library of mapigrade is not available'),
        ),
      ),
    );
  });

  test('Mapigrade.isSupported is false', () {
    expect(Mapigrade.isSupported, isFalse);
  });

  testWidgets('a MapigradeMap reports one create exception and builds its '
      'children', (tester) async {
    final errors = <MapigradeException>[];
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: MapigradeMap(
          styleUrl: 'https://example.com/style.json',
          initialCamera: const MapigradeCamera(center: LatLng(0, 0), zoom: 1),
          onError: errors.add,
          children: const [Text('child')],
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(errors.single, isA<MapigradeCreateException>());
    expect(find.text('child'), findsOneWidget);
  });
}
