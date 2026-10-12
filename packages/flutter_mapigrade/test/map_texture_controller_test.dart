// Unit tests of MapTextureController that don't need the native library.
import 'package:flutter_mapigrade/src/texture/map_texture_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('setMaximumCacheSize rejects a negative size', () {
    expect(
      () => MapTextureController.setMaximumCacheSize(-1),
      throwsArgumentError,
    );
  });
}
