import 'package:flutter/material.dart';
import 'package:flutter_mapigrade/flutter_mapigrade.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapigrade_demo/src/inspect/feature_panel.dart';

Future<void> _pump(
  WidgetTester tester,
  QueriedFeature? feature, {
  String layerId = 'layer',
}) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: 300,
        child: FeatureDetails(
          selection: feature == null
              ? null
              : (layerId: layerId, feature: feature),
        ),
      ),
    ),
  ),
);

double _top(WidgetTester tester, String text) =>
    tester.getTopLeft(find.text(text)).dy;

void main() {
  testWidgets('states the geometry and the state', (tester) async {
    await _pump(
      tester,
      const QueriedFeature(
        id: 18503910,
        sourceId: 'openmaptiles',
        sourceLayerId: 'building',
        geometry: {
          'type': 'MultiPolygon',
          'coordinates': [[], [], []],
        },
        state: {'selected': true},
      ),
    );
    expect(find.text('MultiPolygon, 3 polygons'), findsOneWidget);
    expect(find.text('{"selected":true}'), findsOneWidget);
  });

  testWidgets('states that labels have no state', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 300,
            child: FeatureDetails(
              selection: (
                layerId: 'poi_r1',
                feature: QueriedFeature(id: 7, sourceId: 's'),
              ),
              symbolLayerIds: {'poi_r1'},
            ),
          ),
        ),
      ),
    );
    expect(find.text('not returned for labels and icons'), findsOneWidget);
  });

  test('describes geometries', () {
    expect(describeGeometry(const {}), 'none');
    expect(
      describeGeometry(const {
        'type': 'Point',
        'coordinates': [0, 0],
      }),
      'Point',
    );
    expect(
      describeGeometry(const {
        'type': 'MultiLineString',
        'coordinates': [[]],
      }),
      'MultiLineString, 1 line',
    );
  });

  testWidgets('lists the other hits and selects one', (tester) async {
    const building = (
      layerId: 'building-3d',
      feature: QueriedFeature(id: 1, sourceId: 's', sourceLayerId: 'building'),
    );
    const park = (
      layerId: 'park',
      feature: QueriedFeature(id: 2, sourceId: 's', sourceLayerId: 'park'),
    );
    Selection? chosen;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(
              width: 300,
              child: FeatureDetails(
                selection: building,
                hits: const [building, park],
                onSelect: (hit) => chosen = hit,
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.text('Also at the tap'), findsOneWidget);
    expect(find.text('building-3d  ·  building  ·  1'), findsNothing);
    await tester.tap(find.text('park  ·  park  ·  2'));
    expect(chosen, park);
  });

  testWidgets('sorts the properties by key', (tester) async {
    await _pump(
      tester,
      const QueriedFeature(
        id: 42,
        sourceId: 'openmaptiles',
        sourceLayerId: 'transportation',
        properties: {
          'subclass': 'pedestrian',
          'class': 'path',
          'brunnel': 'bridge',
        },
      ),
      layerId: 'road_path_pedestrian',
    );
    expect(find.text('road_path_pedestrian'), findsOneWidget);
    expect(find.text('openmaptiles'), findsOneWidget);
    expect(find.text('transportation'), findsOneWidget);
    expect(find.text('42'), findsOneWidget);
    expect(_top(tester, 'brunnel'), lessThan(_top(tester, 'class')));
    expect(_top(tester, 'class'), lessThan(_top(tester, 'subclass')));
    expect(find.textContaining('no ID'), findsNothing);
  });

  testWidgets('states "none" for a source without layers', (tester) async {
    await _pump(tester, const QueriedFeature(id: 'cafe', sourceId: 'points'));
    // Source layer, geometry, state and properties.
    expect(find.text('none'), findsNWidgets(4));
  });

  testWidgets('encodes values that aren\'t strings as JSON', (tester) async {
    await _pump(
      tester,
      const QueriedFeature(
        id: 1,
        sourceId: 's',
        properties: {
          'rank': 3,
          'oneway': true,
          'names': ['a', 'b'],
          'label': 'Nice',
        },
      ),
    );
    expect(find.text('3'), findsOneWidget);
    expect(find.text('true'), findsOneWidget);
    expect(find.text('["a","b"]'), findsOneWidget);
    expect(find.text('Nice'), findsOneWidget);
  });

  testWidgets('states that a feature without an ID can\'t be highlighted', (
    tester,
  ) async {
    await _pump(
      tester,
      const QueriedFeature(sourceId: 's', sourceLayerId: 'poi'),
    );
    expect(
      find.text('This feature has no ID, so it can\'t be highlighted.'),
      findsOneWidget,
    );
  });

  testWidgets('states that no feature is selected', (tester) async {
    await _pump(tester, null);
    expect(find.text('No feature selected.'), findsOneWidget);
  });
}
