// Widget tests for the public layer (design D66 of the public-api change).
import 'package:flutter/widgets.dart';
import 'package:flutter_mapigrade/src/layer/http_header_rule.dart';
import 'package:flutter_mapigrade/src/layer/layer_alignment.dart';
import 'package:flutter_mapigrade/src/layer/layer_exception.dart';
import 'package:flutter_mapigrade/src/layer/mapigrade_layer.dart';
import 'package:flutter_mapigrade/src/layer/map_texture_layer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('builds a copy-free MapTextureLayer with the same values', (
    tester,
  ) async {
    void onStyleLoaded() {}
    void onError(LayerException exception) {}
    final httpHeaders = [
      HttpHeaderRule(url: 'https://a.example.com/**', headers: {'X-Key': 'k'}),
    ];
    // With an empty size the layer doesn't create its map, which needs the
    // native library (see the comment in MapTextureLayer.didChangeDependencies).
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size.zero),
        child: MapigradeLayer(
          styleUrl: 'https://example.com/style.json',
          alignment: LayerAlignment.none,
          httpHeaders: httpHeaders,
          onStyleLoaded: onStyleLoaded,
          onError: onError,
        ),
      ),
    );

    final layer = tester.widget<MapTextureLayer>(find.byType(MapTextureLayer));
    expect(layer.styleUrl, 'https://example.com/style.json');
    expect(layer.styleJson, isNull);
    expect(layer.alignment, LayerAlignment.none);
    expect(layer.httpHeaders, same(httpHeaders));
    expect(layer.onStyleLoaded, same(onStyleLoaded));
    expect(layer.onError, same(onError));
    expect(layer.copyFree, isTrue);
    expect(layer.onController, isNull);
    expect(layer.createController, isNull);
  });

  testWidgets('passes styleJson, the default alignment and no rules', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(size: Size.zero),
        child: MapigradeLayer(styleJson: '{}'),
      ),
    );

    final layer = tester.widget<MapTextureLayer>(find.byType(MapTextureLayer));
    expect(layer.styleUrl, isNull);
    expect(layer.styleJson, '{}');
    expect(layer.alignment, const LayerAlignment.prediction());
    expect(layer.httpHeaders, isEmpty);
  });

  test('requires exactly one of styleUrl and styleJson', () {
    String? none;
    expect(() => MapigradeLayer(styleUrl: none), throwsAssertionError);
    expect(
      () => MapigradeLayer(styleUrl: 'a', styleJson: '{}'),
      throwsAssertionError,
    );
  });

  test('maximumCacheSizeBytes is 50 MiB until set', () {
    expect(MapigradeLayer.maximumCacheSizeBytes, 52428800);
  });

  test('a negative maximumCacheSizeBytes throws and is not stored', () {
    expect(
      () => MapigradeLayer.maximumCacheSizeBytes = -1,
      throwsArgumentError,
    );
    expect(MapigradeLayer.maximumCacheSizeBytes, 52428800);
  });
}
