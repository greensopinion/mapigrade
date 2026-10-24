/// The map's counts at one time, from a `LayerMetricsSnapshot`.
typedef Counts = ({
  Duration time,
  int displayedFrames,
  int renderedFrames,
  Duration renderTime,
});

/// The map's rates between two snapshots (design D115).
typedef Rates = ({
  double displayedFps,
  double renderedFps,

  /// The average render time per rendered frame in milliseconds, or null when
  /// no frame was rendered in the interval.
  double? renderMs,
});

/// The rates from [before] to [after]; zero rates for an empty interval.
Rates ratesBetween(Counts before, Counts after) {
  final seconds = (after.time - before.time).inMicroseconds / 1e6;
  final rendered = after.renderedFrames - before.renderedFrames;
  final renderTime = after.renderTime - before.renderTime;
  return (
    displayedFps: seconds > 0
        ? (after.displayedFrames - before.displayedFrames) / seconds
        : 0,
    renderedFps: seconds > 0 ? rendered / seconds : 0,
    renderMs: rendered > 0 ? renderTime.inMicroseconds / 1000 / rendered : null,
  );
}
