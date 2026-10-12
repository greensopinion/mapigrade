// Unit tests for the layer's alignment option (design D43 of the
// camera-prediction-default change).
import 'package:flutter_mapigrade/flutter_mapigrade.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('prediction defaults to a lead of 1', () {
    expect(const LayerAlignment.prediction().lead, 1);
    expect(const LayerAlignment.prediction(lead: 2.5).lead, 2.5);
    expect(LayerAlignment.none.lead, isNull);
  });

  test('values are equal by kind and lead', () {
    // Not const, so that equality doesn't come from canonicalization.
    double lead = 1;
    expect(
      LayerAlignment.prediction(lead: lead),
      const LayerAlignment.prediction(),
    );
    expect(
      LayerAlignment.prediction(lead: lead).hashCode,
      const LayerAlignment.prediction().hashCode,
    );
    expect(
      const LayerAlignment.prediction(lead: 2),
      isNot(const LayerAlignment.prediction()),
    );
    expect(LayerAlignment.none, isNot(const LayerAlignment.prediction()));
    expect(LayerAlignment.none, LayerAlignment.none);
  });

  test('the lead must be greater than 0', () {
    double lead = 0;
    expect(
      () => LayerAlignment.prediction(lead: lead),
      throwsA(isA<AssertionError>()),
    );
  });
}
