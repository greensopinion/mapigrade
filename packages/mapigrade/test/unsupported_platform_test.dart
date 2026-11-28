// A process without the native library, without
// nativeLibraryAvailableOverride (design D165 of the web-build-compatibility
// change). Run it in Chrome with `flutter test --platform chrome`; under
// flutter_tester on a macOS host the process has no native library either, so
// it also passes there. flutter_mapigrade's test of the same name covers the
// layer.
import 'package:flutter_test/flutter_test.dart';
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
}
