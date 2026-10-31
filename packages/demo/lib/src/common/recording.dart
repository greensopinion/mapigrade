import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_mapigrade/flutter_mapigrade.dart';

/// The showcase that the recording mode records (design D213).
enum RecordingShowcase {
  flyover('flyover'),
  routes3d('3d-routes');

  const RecordingShowcase(this.value);

  /// The value of `MAPIGRADE_DEMO_RECORDING_SHOWCASE`.
  final String value;

  /// The showcase for [value]: the flyover when [value] is null, and null when
  /// it names no showcase.
  static RecordingShowcase? parse(String? value) => value == null
      ? flyover
      : values.where((s) => s.value == value).firstOrNull;
}

/// The recording mode, in which `tool/record_readme.sh` records the README
/// image (designs D144 to D147 of the readme-demo-recording change).
class Recording {
  Recording._(this.seconds, this.showcase);

  /// The recording mode when `MAPIGRADE_DEMO_RECORDING_SECONDS` is set on
  /// macOS, otherwise null. Exits for a value that isn't a whole number
  /// greater than 0.
  static Recording? fromEnvironment() {
    if (!Platform.isMacOS) return null;
    final value = Platform.environment[_variable];
    if (value == null) return null;
    final seconds = int.tryParse(value);
    if (seconds == null || seconds <= 0) {
      fail('$_variable is "$value"; it must be a whole number greater than 0');
    }
    final showcaseValue = Platform.environment[_showcaseVariable];
    final showcase = RecordingShowcase.parse(showcaseValue);
    if (showcase == null) {
      fail(
        '$_showcaseVariable is "$showcaseValue"; it must be one of '
        '${RecordingShowcase.values.map((s) => s.value).join(', ')}',
      );
    }
    return Recording._(seconds, showcase);
  }

  static const _variable = 'MAPIGRADE_DEMO_RECORDING_SECONDS';
  static const _showcaseVariable = 'MAPIGRADE_DEMO_RECORDING_SHOWCASE';

  /// How long the map has to render no frame to be at rest.
  static const _rest = Duration(seconds: 1);

  /// How long to wait for the map to be at rest, and for `go`.
  static const _timeout = Duration(seconds: 30);

  /// The clip length in seconds.
  final int seconds;

  final RecordingShowcase showcase;

  /// The warm-up pass covers the clip and 1 s more.
  Duration get warmUp => Duration(seconds: seconds + 1);

  /// Writes [line] to standard output for the capture helper.
  void log(String line) => stdout.writeln(line);

  /// Waits until [metrics] reports no rendered frame for 1 s, writes `ready`,
  /// and returns when `go` arrives on standard input. Exits on the timeouts
  /// and when standard input closes first.
  Future<void> ready(LayerMetrics metrics) async {
    final waited = Stopwatch()..start();
    final atRest = Stopwatch()..start();
    var rendered = metrics.snapshot().renderedFrames;
    while (atRest.elapsed < _rest) {
      if (waited.elapsed > _timeout) {
        fail(
          'the map wasn\'t at rest within ${_timeout.inSeconds} s after the '
          'warm-up pass',
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final now = metrics.snapshot().renderedFrames;
      if (now != rendered) {
        rendered = now;
        atRest.reset();
      }
    }
    stdout.writeln('ready');
    await stdout.flush();
    try {
      await stdin
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .firstWhere((line) => line == 'go')
          .timeout(_timeout);
    } on TimeoutException {
      fail('go didn\'t arrive within ${_timeout.inSeconds} s after ready');
    } on StateError {
      fail('standard input closed before go');
    }
  }

  /// Writes [reason] to standard error and exits with status 1.
  static Never fail(String reason) {
    stderr.writeln('mapigrade_demo: $reason');
    exit(1);
  }
}
