import 'package:flutter_mapigrade/src/layer/layer_exception.dart';
import 'package:flutter_mapigrade/src/layer/queried_feature.dart';
import 'package:flutter_mapigrade/src/texture/pending_queries.dart';
import 'package:flutter_test/flutter_test.dart';

QueriedFeature _decode(String json) =>
    queriedFeatureOf(decodeQueryResult('[$json]').single);

void main() {
  test('a feature of a vector source', () {
    final feature = _decode(
      '{"feature":{"type":"Feature","id":42,'
      '"properties":{"class":"primary","rank":3},'
      '"geometry":{"type":"Point","coordinates":[16.37,48.2]}},'
      '"source":"openmaptiles","sourceLayer":"poi","state":{}}',
    );
    expect(feature.id, 42);
    expect(feature.id, isA<int>());
    expect(feature.properties, {'class': 'primary', 'rank': 3});
    expect(feature.geometry['type'], 'Point');
    expect(feature.geometry['coordinates'], [16.37, 48.2]);
    expect(feature.sourceId, 'openmaptiles');
    expect(feature.sourceLayerId, 'poi');
    expect(feature.state, isEmpty);
  });

  test('a string id, nested properties and no source layer', () {
    final feature = _decode(
      '{"feature":{"type":"Feature","id":"route-7",'
      '"properties":{"tags":["mtb","gravel"],"meta":{"ele":312.5,"lit":false}},'
      '"geometry":{"type":"LineString","coordinates":[[0,0],[1,1]]}},'
      '"source":"routes","sourceLayer":null,"state":{"selected":true}}',
    );
    expect(feature.id, 'route-7');
    expect(feature.properties['tags'], ['mtb', 'gravel']);
    expect(feature.properties['meta'], {'ele': 312.5, 'lit': false});
    expect(feature.sourceLayerId, isNull);
    expect(feature.state, {'selected': true});
  });

  test('a feature without an id or properties', () {
    final feature = _decode(
      '{"feature":{"type":"Feature","properties":null,'
      '"geometry":{"type":"Polygon","coordinates":[]}},'
      '"source":"areas","sourceLayer":null,"state":{}}',
    );
    expect(feature.id, isNull);
    expect(feature.properties, isEmpty);
  });

  test('LayerQueryException names its type', () {
    expect(
      const LayerQueryException('bad filter').toString(),
      'LayerQueryException: bad filter',
    );
    expect(
      const LayerQueryException('m'),
      isNot(const LayerRenderException('m')),
    );
  });
}
