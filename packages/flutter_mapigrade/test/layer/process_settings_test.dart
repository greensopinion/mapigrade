import 'package:flutter_mapigrade/flutter_mapigrade.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapigrade/src/integration.dart' show Mapigrade;
import 'package:mapigrade/src/testing.dart';

void main() {
  tearDown(() => Mapigrade.maximumCacheSizeBytes = 50 * 1024 * 1024);

  test(
    'a cache size set through Mapigrade reads the same through the layer',
    () {
      Mapigrade.maximumCacheSizeBytes = 10 * 1024 * 1024;
      expect(MapigradeLayer.maximumCacheSizeBytes, 10 * 1024 * 1024);
    },
  );

  test(
    'a cache size set through the layer reads the same through Mapigrade',
    () {
      MapigradeLayer.maximumCacheSizeBytes = 3 * 1024 * 1024;
      expect(Mapigrade.maximumCacheSizeBytes, 3 * 1024 * 1024);
    },
  );

  test('a negative cache size is refused through either class', () {
    expect(
      () => MapigradeLayer.maximumCacheSizeBytes = -1,
      throwsArgumentError,
    );
    expect(() => Mapigrade.maximumCacheSizeBytes = -1, throwsArgumentError);
    expect(Mapigrade.maximumCacheSizeBytes, 50 * 1024 * 1024);
  });

  test('both classes report the same support', () {
    nativeLibraryAvailableOverride = true;
    addTearDown(() => nativeLibraryAvailableOverride = null);
    expect(Mapigrade.isSupported, isTrue);
    expect(MapigradeLayer.isSupported, isTrue);
    nativeLibraryAvailableOverride = false;
    expect(Mapigrade.isSupported, isFalse);
    expect(MapigradeLayer.isSupported, isFalse);
  });
}
