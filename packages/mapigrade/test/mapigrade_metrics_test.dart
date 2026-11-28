// Unit tests for LayerMetrics (designs D109 and D110 of the layer-metrics
// change).
import 'package:flutter_mapigrade/src/layer/layer_metrics.dart';
import 'package:flutter_mapigrade/src/texture/map_texture_controller.dart';
import 'package:flutter_test/flutter_test.dart';

// A controller without a native map that returns [values] from stats().
class _FakeController implements MapTextureController {
  MapTextureStats values = const MapTextureStats();
  Object? error;
  bool _disposed = false;

  @override
  bool get isDisposed => _disposed;
  @override
  MapTextureStats stats() {
    if (error case final error?) throw error;
    return values;
  }

  @override
  void dispose() => _disposed = true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

MapTextureStats _stats(int displayed, int rendered, int renderMs) =>
    MapTextureStats(
      presentedFrames: displayed,
      renderedFrames: rendered,
      renderUpdateTotal: Duration(milliseconds: renderMs),
    );

void _expectValues(
  LayerMetricsSnapshot snapshot,
  int displayed,
  int rendered,
  int renderMs,
) {
  expect(snapshot.displayedFrames, displayed);
  expect(snapshot.renderedFrames, rendered);
  expect(snapshot.renderTime, Duration(milliseconds: renderMs));
}

void main() {
  test('an unbound object returns zeros', () {
    _expectValues(LayerMetrics().snapshot(), 0, 0, 0);
  });

  test("a bound object returns the controller's values", () {
    final metrics = LayerMetrics();
    final controller = _FakeController()..values = _stats(3, 4, 20);
    bindMetrics(metrics, controller);
    _expectValues(metrics.snapshot(), 3, 4, 20);
    controller.values = _stats(5, 6, 30);
    _expectValues(metrics.snapshot(), 5, 6, 30);
  });

  test('release keeps the last values for later snapshots', () {
    final metrics = LayerMetrics();
    final controller = _FakeController()..values = _stats(3, 4, 20);
    bindMetrics(metrics, controller);
    releaseMetrics(metrics, controller);
    controller.values = _stats(5, 6, 30);
    controller.dispose();
    _expectValues(metrics.snapshot(), 3, 4, 20);
    _expectValues(metrics.snapshot(), 3, 4, 20);
  });

  test('release with a different controller does nothing', () {
    final metrics = LayerMetrics();
    final old = _FakeController()..values = _stats(3, 4, 20);
    final current = _FakeController()..values = _stats(1, 1, 5);
    bindMetrics(metrics, old);
    bindMetrics(metrics, current);
    releaseMetrics(metrics, old);
    _expectValues(metrics.snapshot(), 1, 1, 5);
    current.values = _stats(2, 2, 8);
    _expectValues(metrics.snapshot(), 2, 2, 8);
  });

  test('a bind after a release starts from the new map', () {
    final metrics = LayerMetrics();
    final old = _FakeController()..values = _stats(3, 4, 20);
    bindMetrics(metrics, old);
    releaseMetrics(metrics, old);
    bindMetrics(metrics, _FakeController());
    _expectValues(metrics.snapshot(), 0, 0, 0);
  });

  test('stats() throwing MapTextureException returns the kept values', () {
    final metrics = LayerMetrics();
    final controller = _FakeController()
      ..error = const MapTextureException('failed');
    bindMetrics(metrics, controller);
    // A bind clears the kept values.
    _expectValues(metrics.snapshot(), 0, 0, 0);
    releaseMetrics(metrics, controller);
    _expectValues(metrics.snapshot(), 0, 0, 0);
  });

  test(
    'stats() throwing MapTextureDisposedException returns the kept values',
    () {
      final metrics = LayerMetrics();
      final controller = _FakeController()
        ..error = const MapTextureDisposedException();
      bindMetrics(metrics, controller);
      _expectValues(metrics.snapshot(), 0, 0, 0);
    },
  );

  test('time increases between snapshots', () async {
    final metrics = LayerMetrics();
    final first = metrics.snapshot();
    await Future<void>.delayed(const Duration(milliseconds: 2));
    final second = metrics.snapshot();
    expect(second.time, greaterThan(first.time));
    expect(LayerMetrics().snapshot().time, greaterThan(first.time));
  });
}
