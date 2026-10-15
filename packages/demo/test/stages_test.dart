// The scenario "Data file contents" of the demo-app spec, requirement "Stage
// data".
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:mapigrade_demo/src/stages.dart';

void main() {
  final stages = parseStages(File(stagesAsset).readAsStringSync());

  test('the asset has stages 9, 7 and 4 in that order', () {
    expect([for (final s in stages) s.number], [9, 7, 4]);
  });

  test('the facts are those of the official stage pages', () {
    String facts(Stage s) =>
        '${s.number} | ${s.date.toIso8601String().substring(0, 10)} | '
        '${s.start} | ${s.finish} | ${s.distanceKm} km | ${s.type} | '
        '${s.winner} | ${s.team}';
    expect(stages.map(facts), [
      '9 | 2026-08-09 | Nice | Nice | 99.2 km | Mountain | Demi Vollering | '
          'FDJ United–Suez',
      '7 | 2026-08-07 | La Voulte-sur-Rhône | Mont Ventoux | 146.8 km | '
          'Mountain | Katarzyna Niewiadoma-Phinney | Canyon//SRAM',
      '4 | 2026-08-04 | Gevrey-Chambertin | Dijon | 21.0 km | '
          'Individual time trial | Marlen Reusser | Movistar Team',
    ]);
    for (final s in stages) {
      expect(
        s.source,
        Uri.parse('https://www.letourfemmes.fr/en/stage-${s.number}'),
      );
    }
  });

  test('each route starts and ends within 1 km of its start and finish', () {
    const distance = Distance();
    for (final s in stages) {
      expect(s.route.length, greaterThan(1), reason: 'stage ${s.number}');
      expect(
        distance.distance(s.route.first, s.startPoint),
        lessThan(1000),
        reason: 'stage ${s.number} start',
      );
      expect(
        distance.distance(s.route.last, s.finishPoint),
        lessThan(1000),
        reason: 'stage ${s.number} finish',
      );
    }
  });

  test('only stage 9 starts and finishes at the same place', () {
    expect([for (final s in stages) s.isLoop], [true, false, false]);
  });
}
