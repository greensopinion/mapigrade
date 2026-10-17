/// The metrics of a layer's map (designs D109 and D110 of the layer-metrics
/// change). The main library exports [LayerMetrics] and
/// [LayerMetricsSnapshot] only; [bindMetrics] and [releaseMetrics] are for
/// the layer.
library;

import '../texture/map_texture_controller.dart';

typedef _Values = ({
  int displayedFrames,
  int renderedFrames,
  Duration renderTime,
});

const _Values _zero = (
  displayedFrames: 0,
  renderedFrames: 0,
  renderTime: Duration.zero,
);

// One clock for all metrics objects in the process, started by the first
// snapshot.
final _clock = Stopwatch()..start();

/// Reads the frame counts and render time of the map of a `MapigradeLayer`.
///
/// Create one object for each layer and pass it to the layer as `metrics`;
/// when two layers are given the same object, it reports the map of the layer
/// that was given it last. Call [snapshot] to read the values, for example
/// once per second, and compute rates from two snapshots.
///
/// The values are those of one map, from the map's creation. Before the layer
/// has a map, and when its map can't be created, every count is 0. A style
/// change keeps the map and its counts. When the layer is removed from the
/// tree, the object keeps the values it read just before the layer disposed
/// its map; they can lack a frame that the map rendered after that read.
///
/// A new `key` gives the layer a new map. Create a new [LayerMetrics] with the
/// new key: an object given to the new layer reports the new map, starting
/// from 0, even when it is the object of the previous layer.
final class LayerMetrics {
  /// An object that no layer has been given yet; its snapshots report 0.
  LayerMetrics();

  MapTextureController? _controller;
  _Values _kept = _zero;

  /// The current values. Doesn't throw.
  LayerMetricsSnapshot snapshot() {
    final values = _read();
    return LayerMetricsSnapshot._(
      time: _clock.elapsed,
      displayedFrames: values.displayedFrames,
      renderedFrames: values.renderedFrames,
      renderTime: values.renderTime,
    );
  }

  _Values _read() {
    final controller = _controller;
    if (controller == null || controller.isDisposed) return _kept;
    try {
      final stats = controller.stats();
      return (
        displayedFrames: stats.presentedFrames,
        renderedFrames: stats.renderedFrames,
        renderTime: stats.renderUpdateTotal,
      );
    } on MapTextureException {
      return _kept;
    } on MapTextureDisposedException {
      return _kept;
    }
  }
}

/// The values of a [LayerMetrics] at one time. The counts and [renderTime]
/// are cumulative from the creation of the layer's map.
final class LayerMetricsSnapshot {
  const LayerMetricsSnapshot._({
    required this.time,
    required this.displayedFrames,
    required this.renderedFrames,
    required this.renderTime,
  });

  /// The time of the snapshot on a monotonic clock that all [LayerMetrics]
  /// objects in the process share. Only the difference between two snapshots
  /// has a meaning.
  final Duration time;

  /// The map frames given to Flutter for display, at most [renderedFrames].
  /// On macOS and iOS, a frame counts when Flutter takes it for display; on
  /// Android, when Dart chooses it for display.
  final int displayedFrames;

  /// The frames the map rendered.
  final int renderedFrames;

  /// The total time the map spent in its render calls. It includes the calls
  /// that rendered nothing, so `renderTime` divided by [renderedFrames] is an
  /// upper bound of the average render time of a frame.
  final Duration renderTime;

  @override
  bool operator ==(Object other) =>
      other is LayerMetricsSnapshot &&
      other.time == time &&
      other.displayedFrames == displayedFrames &&
      other.renderedFrames == renderedFrames &&
      other.renderTime == renderTime;

  @override
  int get hashCode =>
      Object.hash(time, displayedFrames, renderedFrames, renderTime);

  @override
  String toString() =>
      'LayerMetricsSnapshot(time: $time, displayedFrames: $displayedFrames, '
      'renderedFrames: $renderedFrames, renderTime: $renderTime)';
}

/// Makes [metrics] report the map of [controller], starting from that map's
/// current values.
void bindMetrics(LayerMetrics metrics, MapTextureController controller) {
  metrics._controller = controller;
  metrics._kept = _zero;
}

/// Keeps the current values of [controller] in [metrics] and stops reading
/// it. Does nothing unless [metrics] reports [controller], so that a later
/// [bindMetrics] to another map isn't undone (design D109).
void releaseMetrics(LayerMetrics metrics, MapTextureController controller) {
  if (!identical(metrics._controller, controller)) return;
  metrics._kept = metrics._read();
  metrics._controller = null;
}
