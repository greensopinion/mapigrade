import 'package:flutter_test/flutter_test.dart';
import 'package:mapigrade_demo/src/rates.dart';

Counts _counts(int ms, int displayed, int rendered, int renderMs) => (
  time: Duration(milliseconds: ms),
  displayedFrames: displayed,
  renderedFrames: rendered,
  renderTime: Duration(milliseconds: renderMs),
);

void main() {
  test('rates are count differences over the time difference', () {
    final rates = ratesBetween(
      _counts(1000, 100, 110, 400),
      _counts(3000, 220, 250, 960),
    );
    expect(rates.displayedFps, 60);
    expect(rates.renderedFps, 70);
  });

  test('the render time is averaged over the rendered frames', () {
    final rates = ratesBetween(_counts(0, 0, 0, 0), _counts(1000, 50, 80, 400));
    expect(rates.renderMs, 5);
  });

  test('an interval without rendered frames has no render time', () {
    final rates = ratesBetween(
      _counts(0, 30, 30, 120),
      _counts(1000, 30, 30, 120),
    );
    expect(rates.displayedFps, 0);
    expect(rates.renderedFps, 0);
    expect(rates.renderMs, isNull);
  });

  test('an empty interval has zero rates', () {
    final counts = _counts(1000, 30, 30, 120);
    final rates = ratesBetween(counts, counts);
    expect(rates.displayedFps, 0);
    expect(rates.renderedFps, 0);
  });
}
