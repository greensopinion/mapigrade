// Unit tests for the layer's alignment option (design D43 of the
// camera-prediction-default change).
import 'package:flutter_mapigrade/flutter_mapigrade.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('prediction defaults to a lead of 1', () {
    expect(const CameraAlignment.prediction().lead, 1);
    expect(const CameraAlignment.prediction(lead: 2.5).lead, 2.5);
    expect(CameraAlignment.transform.lead, isNull);
    expect(CameraAlignment.none.lead, isNull);
  });

  test('only transform is the transform', () {
    expect(CameraAlignment.transform.isTransform, isTrue);
    expect(CameraAlignment.none.isTransform, isFalse);
    expect(const CameraAlignment.prediction().isTransform, isFalse);
  });

  test('values are equal by kind and lead', () {
    // Not const, so that equality doesn't come from canonicalization.
    double lead = 1;
    expect(
      CameraAlignment.prediction(lead: lead),
      const CameraAlignment.prediction(),
    );
    expect(
      CameraAlignment.prediction(lead: lead).hashCode,
      const CameraAlignment.prediction().hashCode,
    );
    expect(
      const CameraAlignment.prediction(lead: 2),
      isNot(const CameraAlignment.prediction()),
    );
    expect(CameraAlignment.transform, isNot(CameraAlignment.none));
    expect(
      CameraAlignment.transform,
      isNot(const CameraAlignment.prediction()),
    );
    expect(CameraAlignment.none, CameraAlignment.none);
  });

  test('the lead must be greater than 0', () {
    double lead = 0;
    expect(
      () => CameraAlignment.prediction(lead: lead),
      throwsA(isA<AssertionError>()),
    );
  });
}
