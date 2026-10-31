import 'package:flutter_test/flutter_test.dart';
import 'package:mapigrade_demo/src/common/recording.dart';

void main() {
  test('without the variable the flyover is recorded', () {
    expect(RecordingShowcase.parse(null), RecordingShowcase.flyover);
  });

  test('the variable names the showcase', () {
    expect(RecordingShowcase.parse('flyover'), RecordingShowcase.flyover);
    expect(RecordingShowcase.parse('3d-routes'), RecordingShowcase.routes3d);
  });

  test('an unknown showcase is null', () {
    expect(RecordingShowcase.parse('inspect'), isNull);
    expect(RecordingShowcase.parse(''), isNull);
  });
}
