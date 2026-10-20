import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_mapigrade/flutter_mapigrade.dart';

/// The recording mode, in which `tool/record_readme.sh` records the README
/// image (designs D144 to D147 of the readme-demo-recording change).
class Recording {
  Recording._(this.seconds);

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
    return Recording._(seconds);
  }

  static const _variable = 'MAPIGRADE_DEMO_RECORDING_SECONDS';

  /// How long the map has to render no frame to be at rest.
  static const _rest = Duration(seconds: 1);

  /// How long to wait for the map to be at rest, and for `go`.
  static const _timeout = Duration(seconds: 30);

  /// The clip length in seconds.
  final int seconds;

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
