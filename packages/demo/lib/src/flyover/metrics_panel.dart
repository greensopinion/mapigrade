import 'dart:async';
import 'dart:collection';
import 'dart:ui' show FramePhase, FrameTiming;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_mapigrade/flutter_mapigrade.dart';

import 'rates.dart';

const _interval = Duration(seconds: 1);

/// The map's frame rates and render time, and the Flutter UI frame rate,
/// updated once per second (design D115).
class MetricsPanel extends StatefulWidget {
  const MetricsPanel({super.key, required this.metrics});

  /// The metrics object given to the map screen's layer.
  final LayerMetrics metrics;

  @override
  State<MetricsPanel> createState() => _MetricsPanelState();
}

class _MetricsPanelState extends State<MetricsPanel> {
  late final Timer _timer;
  late Counts _previous;
  Rates? _rates;
  int? _uiFps;
  final _uiFrames = _UiFrameCounter();

  @override
  void initState() {
    super.initState();
    _previous = _counts(widget.metrics.snapshot());
    SchedulerBinding.instance.addTimingsCallback(_uiFrames.add);
    _timer = Timer.periodic(_interval, (_) => _update());
  }

  @override
  void dispose() {
    _timer.cancel();
    SchedulerBinding.instance.removeTimingsCallback(_uiFrames.add);
    super.dispose();
  }

  void _update() {
    final counts = _counts(widget.metrics.snapshot());
    setState(() {
      _rates = ratesBetween(_previous, counts);
      _uiFps = _uiFrames.lastCompleteSecond();
    });
    _previous = counts;
  }

  static Counts _counts(LayerMetricsSnapshot s) => (
    time: s.time,
    displayedFrames: s.displayedFrames,
    renderedFrames: s.renderedFrames,
    renderTime: s.renderTime,
  );

  @override
  Widget build(BuildContext context) {
    final rates = _rates;
    final renderMs = rates?.renderMs;
    final atRest = rates != null && rates.renderedFps == 0;
    final style = Theme.of(context).textTheme.bodySmall!
        .copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
    return DefaultTextStyle(
      style: style,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Map displayed: ${_fps(rates?.displayedFps)} fps'),
          Text('Map rendered: ${_fps(rates?.renderedFps)} fps'),
          Text(
            'Map render time: '
            '${renderMs == null ? '–' : renderMs.toStringAsFixed(1)} ms/frame',
          ),
          Text('Flutter UI: ${_uiFps ?? '–'} fps'),
          Text(
            atRest
                ? 'The map is at rest: it renders no frames.'
                : 'At rest, the map renders no frames.',
            style: style.copyWith(fontStyle: FontStyle.italic),
          ),
        ],
      ),
    );
  }
}

String _fps(double? fps) => fps == null ? '–' : fps.toStringAsFixed(0);

/// Counts the rasterized Flutter frames per second of their `rasterFinish`
/// time. Flutter reports the timings in batches up to a second late, so the
/// count of a second is complete only later than the batch that contains it.
class _UiFrameCounter {
  final _clock = Stopwatch()..start();
  final _perSecond = SplayTreeMap<int, int>();

  /// The smallest seen difference between [_clock] and a timing's
  /// `rasterFinish`: it maps the clock to the timings' clock without
  /// assuming that the two are the same.
  int? _offsetMicros;

  void add(List<FrameTiming> timings) {
    final now = _clock.elapsedMicroseconds;
    for (final timing in timings) {
      final finish = timing.timestampInMicroseconds(FramePhase.rasterFinish);
      final second = finish ~/ Duration.microsecondsPerSecond;
      _perSecond[second] = (_perSecond[second] ?? 0) + 1;
      final offset = now - finish;
      if (_offsetMicros == null || offset < _offsetMicros!) {
        _offsetMicros = offset;
      }
    }
  }

  /// The frames of the latest second that no later batch can add to, or null
  /// before the first timing.
  int? lastCompleteSecond() {
    final offset = _offsetMicros;
    if (offset == null) return null;
    final now = _clock.elapsedMicroseconds - offset;
    final second = now ~/ Duration.microsecondsPerSecond - 2;
    _perSecond.removeWhere((s, _) => s < second);
    return _perSecond[second] ?? 0;
  }
}
