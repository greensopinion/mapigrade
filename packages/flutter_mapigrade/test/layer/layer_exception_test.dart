// Unit tests for the layer's failures (design D68 of the public-api change).
import 'package:flutter_mapigrade/src/layer/layer_exception.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('failures are equal by type and message', () {
    // Not const, so that equality doesn't come from canonicalization.
    var message = 'not found';
    expect(LayerLoadException(message), const LayerLoadException('not found'));
    expect(
      LayerLoadException(message).hashCode,
      const LayerLoadException('not found').hashCode,
    );
    expect(const LayerLoadException('a'), isNot(const LayerLoadException('b')));
  });

  test('failures of different types are not equal', () {
    const load = LayerLoadException('m');
    const render = LayerRenderException('m');
    const create = LayerCreateException('m');
    expect(load, isNot(render));
    expect(render, isNot(create));
    expect(create, isNot(load));
  });

  test('toString names the type and the message', () {
    expect(
      const LayerLoadException('not found').toString(),
      'LayerLoadException: not found',
    );
    expect(
      const LayerRenderException('lost').toString(),
      'LayerRenderException: lost',
    );
    expect(
      const LayerCreateException('-3').toString(),
      'LayerCreateException: -3',
    );
  });

  test('failures are exceptions', () {
    expect(const LayerLoadException('m'), isA<Exception>());
  });
}
