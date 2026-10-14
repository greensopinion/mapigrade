// Unit tests of MapTextureController that don't need the native library.
import 'package:flutter_mapigrade/src/texture/map_texture_controller.dart';
import 'package:flutter_mapigrade/src/texture/native_library.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() => nativeLibraryAvailableOverride = null);

  test('create throws MapTextureException without the native library', () {
    nativeLibraryAvailableOverride = false;
    expect(
      () => MapTextureController.create(pixelRatio: 1),
      throwsA(
        isA<MapTextureException>().having(
          (e) => e.message,
          'message',
          'the native library of flutter_mapigrade is not available in this '
              'process',
        ),
      ),
    );
  });

  test('setMaximumCacheSize rejects a negative size', () {
    expect(
      () => MapTextureController.setMaximumCacheSize(-1),
      throwsArgumentError,
    );
  });
}
