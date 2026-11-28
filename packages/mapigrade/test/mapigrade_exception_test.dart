// Unit tests for the layer's failures (design D68 of the public-api change).
import 'package:mapigrade/src/mapigrade_exception.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('failures are equal by type and message', () {
    // Not const, so that equality doesn't come from canonicalization.
    var message = 'not found';
    expect(
      MapigradeLoadException(message),
      const MapigradeLoadException('not found'),
    );
    expect(
      MapigradeLoadException(message).hashCode,
      const MapigradeLoadException('not found').hashCode,
    );
    expect(
      const MapigradeLoadException('a'),
      isNot(const MapigradeLoadException('b')),
    );
  });

  test('failures of different types are not equal', () {
    const load = MapigradeLoadException('m');
    const render = MapigradeRenderException('m');
    const create = MapigradeCreateException('m');
    expect(load, isNot(render));
    expect(render, isNot(create));
    expect(create, isNot(load));
  });

  test('toString names the type and the message', () {
    expect(
      const MapigradeLoadException('not found').toString(),
      'MapigradeLoadException: not found',
    );
    expect(
      const MapigradeRenderException('lost').toString(),
      'MapigradeRenderException: lost',
    );
    expect(
      const MapigradeCreateException('-3').toString(),
      'MapigradeCreateException: -3',
    );
  });

  test('failures are exceptions', () {
    expect(const MapigradeLoadException('m'), isA<Exception>());
  });
}
